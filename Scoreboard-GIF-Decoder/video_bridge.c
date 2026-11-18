/*
 * video_bridge.c
 *
 * A thin C wrapper around FFmpeg's libavformat/libavcodec/swscale,
 * exposing an opaque handle and a flat LuaJIT FFI API.
 *
 * STATUS:
 * The source is syntax-checked by CI against the Ubuntu FFmpeg development
 * headers. It has NOT been built as a Windows DLL or tested in the target
 * MoonLoader/ImGui runtime. Video playback must remain experimental.
 *
 * BUILD (Windows, MinGW-w64 + a matching shared FFmpeg development package):
 *
 *   gcc -shared -O2 -o video_bridge.dll video_bridge.c ^
 *       -Ipath\to\ffmpeg\include -Lpath\to\ffmpeg\lib ^
 *       -lavformat -lavcodec -lavutil -lswscale
 *
 * Ship the FFmpeg runtime DLLs from the same build beside video_bridge.dll
 * and the host executable. ABI and DLL compatibility still need validation.
 */

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/error.h>
#include <libavutil/imgutils.h>
#include <libavutil/mem.h>
#include <libswscale/swscale.h>

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API
#endif

#define VIDEO_MAX_PIXELS 4000000LL

typedef struct {
    AVFormatContext *fmt_ctx;
    AVCodecContext  *codec_ctx;
    struct SwsContext *sws_ctx;
    AVFrame *frame;
    AVFrame *rgba_frame;
    AVPacket *packet;
    int video_stream_index;
    int width;
    int height;
    uint8_t *rgba_buffer;
    int rgba_buffer_size;
    int input_eof;
    int flush_sent;
} VideoHandle;

static void video_release(VideoHandle *v) {
    if (!v) return;

    if (v->rgba_buffer) av_free(v->rgba_buffer);
    if (v->packet) av_packet_free(&v->packet);
    if (v->frame) av_frame_free(&v->frame);
    if (v->rgba_frame) av_frame_free(&v->rgba_frame);
    if (v->sws_ctx) sws_freeContext(v->sws_ctx);
    if (v->codec_ctx) avcodec_free_context(&v->codec_ctx);
    if (v->fmt_ctx) avformat_close_input(&v->fmt_ctx);
    free(v);
}

API void *video_open(const char *path) {
    if (!path || !path[0]) return NULL;

    VideoHandle *v = (VideoHandle *)calloc(1, sizeof(VideoHandle));
    if (!v) return NULL;
    v->video_stream_index = -1;

    if (avformat_open_input(&v->fmt_ctx, path, NULL, NULL) != 0) {
        video_release(v);
        return NULL;
    }

    if (avformat_find_stream_info(v->fmt_ctx, NULL) < 0) {
        video_release(v);
        return NULL;
    }

    for (unsigned int i = 0; i < v->fmt_ctx->nb_streams; i++) {
        if (v->fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            v->video_stream_index = (int)i;
            break;
        }
    }
    if (v->video_stream_index < 0) {
        video_release(v);
        return NULL;
    }

    AVCodecParameters *codecpar =
        v->fmt_ctx->streams[v->video_stream_index]->codecpar;
    const AVCodec *codec = avcodec_find_decoder(codecpar->codec_id);
    if (!codec) {
        video_release(v);
        return NULL;
    }

    v->codec_ctx = avcodec_alloc_context3(codec);
    if (!v->codec_ctx
        || avcodec_parameters_to_context(v->codec_ctx, codecpar) < 0
        || avcodec_open2(v->codec_ctx, codec, NULL) < 0) {
        video_release(v);
        return NULL;
    }

    v->width = v->codec_ctx->width;
    v->height = v->codec_ctx->height;
    if (v->width <= 0 || v->height <= 0
        || (int64_t)v->width * (int64_t)v->height > VIDEO_MAX_PIXELS) {
        video_release(v);
        return NULL;
    }

    v->frame = av_frame_alloc();
    v->rgba_frame = av_frame_alloc();
    v->packet = av_packet_alloc();
    if (!v->frame || !v->rgba_frame || !v->packet) {
        video_release(v);
        return NULL;
    }

    v->rgba_buffer_size = av_image_get_buffer_size(
        AV_PIX_FMT_RGBA, v->width, v->height, 1
    );
    if (v->rgba_buffer_size <= 0) {
        video_release(v);
        return NULL;
    }

    v->rgba_buffer = (uint8_t *)av_malloc((size_t)v->rgba_buffer_size);
    if (!v->rgba_buffer) {
        video_release(v);
        return NULL;
    }

    if (av_image_fill_arrays(
            v->rgba_frame->data,
            v->rgba_frame->linesize,
            v->rgba_buffer,
            AV_PIX_FMT_RGBA,
            v->width,
            v->height,
            1) < 0) {
        video_release(v);
        return NULL;
    }

    return v;
}

API int video_get_frame(void *handle, uint8_t *out_rgba, double *out_pts) {
    VideoHandle *v = (VideoHandle *)handle;
    if (!v || !out_rgba) return -1;

    for (;;) {
        int receive_ret = avcodec_receive_frame(v->codec_ctx, v->frame);

        if (receive_ret == 0) {
            if (v->frame->width != v->width || v->frame->height != v->height) {
                av_frame_unref(v->frame);
                return -1;
            }

            v->sws_ctx = sws_getCachedContext(
                v->sws_ctx,
                v->frame->width,
                v->frame->height,
                (enum AVPixelFormat)v->frame->format,
                v->width,
                v->height,
                AV_PIX_FMT_RGBA,
                SWS_BILINEAR,
                NULL,
                NULL,
                NULL
            );
            if (!v->sws_ctx) {
                av_frame_unref(v->frame);
                return -1;
            }

            int rows = sws_scale(
                v->sws_ctx,
                (const uint8_t *const *)v->frame->data,
                v->frame->linesize,
                0,
                v->height,
                v->rgba_frame->data,
                v->rgba_frame->linesize
            );
            if (rows != v->height) {
                av_frame_unref(v->frame);
                return -1;
            }

            memcpy(out_rgba, v->rgba_buffer, (size_t)v->rgba_buffer_size);

            if (out_pts) {
                AVStream *stream = v->fmt_ctx->streams[v->video_stream_index];
                int64_t timestamp = v->frame->best_effort_timestamp;
                if (timestamp == AV_NOPTS_VALUE) timestamp = v->frame->pts;

                if (timestamp == AV_NOPTS_VALUE) {
                    *out_pts = 0.0;
                } else {
                    int64_t stream_start =
                        stream->start_time == AV_NOPTS_VALUE ? 0 : stream->start_time;
                    *out_pts = (double)(timestamp - stream_start)
                        * av_q2d(stream->time_base);
                }
            }

            av_frame_unref(v->frame);
            return 1;
        }

        if (receive_ret == AVERROR_EOF) return 0;
        if (receive_ret != AVERROR(EAGAIN)) return -1;

        if (v->input_eof) {
            if (v->flush_sent) return 0;

            int flush_ret = avcodec_send_packet(v->codec_ctx, NULL);
            if (flush_ret < 0 && flush_ret != AVERROR_EOF) return -1;
            v->flush_sent = 1;
            continue;
        }

        int read_ret;
        for (;;) {
            read_ret = av_read_frame(v->fmt_ctx, v->packet);
            if (read_ret < 0) break;

            if (v->packet->stream_index != v->video_stream_index) {
                av_packet_unref(v->packet);
                continue;
            }

            int send_ret = avcodec_send_packet(v->codec_ctx, v->packet);
            av_packet_unref(v->packet);
            if (send_ret < 0) return -1;
            break;
        }

        if (read_ret == AVERROR_EOF) {
            v->input_eof = 1;
        } else if (read_ret < 0) {
            return -1;
        }
    }
}

API int video_get_width(void *handle) {
    VideoHandle *v = (VideoHandle *)handle;
    return v ? v->width : 0;
}

API int video_get_height(void *handle) {
    VideoHandle *v = (VideoHandle *)handle;
    return v ? v->height : 0;
}

API void video_close(void *handle) {
    video_release((VideoHandle *)handle);
}
