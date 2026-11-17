/*
 * video_bridge.c
 *
 * A thin C wrapper around FFmpeg's libavformat/libavcodec/swscale,
 * exposing a small, flat C API that's easy to call from LuaJIT FFI
 * (no C++ classes, no complex structs passed by value - just opaque
 * handles and plain output buffers).
 *
 * IMPORTANT - READ BEFORE USING:
 * This file was written without the ability to compile or test it in
 * the development environment (no Windows toolchain, no FFmpeg dev
 * headers available there). It follows FFmpeg's well-documented,
 * standard decode-loop pattern, but it has NOT been verified to
 * actually compile or run. Treat it as a strong starting point that
 * will likely need real debugging once you build and run it for real.
 *
 * BUILD (on a Windows machine, with MinGW-w64 and FFmpeg's dev
 * package - "shared" build with the lib/ and include/ folders):
 *
 *   gcc -shared -O2 -o video_bridge.dll video_bridge.c ^
 *       -Ipath\to\ffmpeg\include -Lpath\to\ffmpeg\lib ^
 *       -lavformat -lavcodec -lavutil -lswscale
 *
 * You'll also need to ship avformat-*.dll, avcodec-*.dll, avutil-*.dll
 * and swscale-*.dll (from the same FFmpeg build) next to video_bridge.dll
 * and next to gta_sa.exe, or LoadLibrary will fail at runtime.
 */

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API
#endif

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
} VideoHandle;

/*
 * Opens a video file and prepares it for frame-by-frame decoding.
 * Returns an opaque handle, or NULL on failure.
 */
API void *video_open(const char *path) {
    VideoHandle *v = (VideoHandle *)calloc(1, sizeof(VideoHandle));
    if (!v) return NULL;

    if (avformat_open_input(&v->fmt_ctx, path, NULL, NULL) != 0) {
        free(v);
        return NULL;
    }

    if (avformat_find_stream_info(v->fmt_ctx, NULL) < 0) {
        avformat_close_input(&v->fmt_ctx);
        free(v);
        return NULL;
    }

    v->video_stream_index = -1;
    for (unsigned int i = 0; i < v->fmt_ctx->nb_streams; i++) {
        if (v->fmt_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            v->video_stream_index = (int)i;
            break;
        }
    }
    if (v->video_stream_index == -1) {
        avformat_close_input(&v->fmt_ctx);
        free(v);
        return NULL;
    }

    AVCodecParameters *codecpar = v->fmt_ctx->streams[v->video_stream_index]->codecpar;
    const AVCodec *codec = avcodec_find_decoder(codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&v->fmt_ctx);
        free(v);
        return NULL;
    }

    v->codec_ctx = avcodec_alloc_context3(codec);
    if (!v->codec_ctx || avcodec_parameters_to_context(v->codec_ctx, codecpar) < 0) {
        avformat_close_input(&v->fmt_ctx);
        free(v);
        return NULL;
    }

    if (avcodec_open2(v->codec_ctx, codec, NULL) < 0) {
        avcodec_free_context(&v->codec_ctx);
        avformat_close_input(&v->fmt_ctx);
        free(v);
        return NULL;
    }

    v->width  = v->codec_ctx->width;
    v->height = v->codec_ctx->height;

    v->sws_ctx = sws_getContext(
        v->width, v->height, v->codec_ctx->pix_fmt,
        v->width, v->height, AV_PIX_FMT_RGBA,
        SWS_BILINEAR, NULL, NULL, NULL
    );
    if (!v->sws_ctx) {
        avcodec_free_context(&v->codec_ctx);
        avformat_close_input(&v->fmt_ctx);
        free(v);
        return NULL;
    }

    v->frame      = av_frame_alloc();
    v->rgba_frame = av_frame_alloc();
    v->packet     = av_packet_alloc();

    v->rgba_buffer_size = av_image_get_buffer_size(AV_PIX_FMT_RGBA, v->width, v->height, 1);
    v->rgba_buffer = (uint8_t *)av_malloc(v->rgba_buffer_size);
    av_image_fill_arrays(v->rgba_frame->data, v->rgba_frame->linesize,
                          v->rgba_buffer, AV_PIX_FMT_RGBA, v->width, v->height, 1);

    return v;
}

/*
 * Decodes and returns the next video frame as RGBA.
 *
 * out_rgba must point to a buffer of at least width*height*4 bytes
 * (call video_get_width/video_get_height first to size it).
 * out_pts receives the frame's presentation timestamp in seconds
 * (relative to the start of the video), for sync purposes.
 *
 * Returns 1 if a frame was written, 0 at end of stream, -1 on error.
 */
API int video_get_frame(void *handle, uint8_t *out_rgba, double *out_pts) {
    VideoHandle *v = (VideoHandle *)handle;
    if (!v) return -1;

    while (av_read_frame(v->fmt_ctx, v->packet) >= 0) {
        if (v->packet->stream_index != v->video_stream_index) {
            av_packet_unref(v->packet);
            continue;
        }

        int send_ret = avcodec_send_packet(v->codec_ctx, v->packet);
        av_packet_unref(v->packet);
        if (send_ret < 0) return -1;

        int recv_ret = avcodec_receive_frame(v->codec_ctx, v->frame);
        if (recv_ret == AVERROR(EAGAIN)) {
            continue; // need more packets before a frame is ready
        }
        if (recv_ret < 0) {
            return -1;
        }

        sws_scale(v->sws_ctx,
                  (const uint8_t *const *)v->frame->data, v->frame->linesize,
                  0, v->height,
                  v->rgba_frame->data, v->rgba_frame->linesize);

        memcpy(out_rgba, v->rgba_buffer, v->rgba_buffer_size);

        if (out_pts) {
            AVRational tb = v->fmt_ctx->streams[v->video_stream_index]->time_base;
            *out_pts = (v->frame->pts == AV_NOPTS_VALUE)
                ? 0.0
                : v->frame->pts * av_q2d(tb);
        }

        return 1;
    }

    return 0; // end of stream
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
    VideoHandle *v = (VideoHandle *)handle;
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
