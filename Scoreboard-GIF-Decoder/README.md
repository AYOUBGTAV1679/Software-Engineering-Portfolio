# Scoreboard with a Custom GIF Decoder

This project combines a configurable scoreboard and session-statistics interface with a GIF89a decoder implemented in Lua. The decoder is the main technical component: it parses the image structure, decompresses LZW data, composites frames, and stores decoded frame assets for reuse.

## Scoreboard interface

The script provides a live leaderboard, sorting and filtering controls, session statistics, configurable layout and colors, and selectable background media. The interface is designed for a MoonLoader-based host and is not a standalone desktop program.

## GIF decoding pipeline

The Lua decoder handles:

- GIF headers and logical screen descriptors.
- Global and local color tables, with bounds checks for truncated palette data.
- Graphic control extensions and image descriptors, including validation of control-block size, terminators, and extension sub-block boundaries.
- GIF87a/GIF89a signature validation and a required trailer marker; unknown block markers and incomplete files are rejected.
- LZW decompression with variable-width codes from 2 to 12 bits. Invalid or truncated code streams are rejected, and decoded output is capped at the image's declared pixel count.
- Clear and end-of-information codes and dictionary growth.
- Frame transparency, composition, and disposal handling.
- Frame timing and playback independent of the host's render callback rate, using elapsed host time rather than Lua's process-CPU clock.
- An on-disk cache of decoded frames and a manifest so repeat loads can reuse prior work.

This pipeline performs the parsing and decompression itself instead of delegating GIF decoding to a system image library.

## Decoder correctness work

The development notes identify a boundary condition in LZW code-width growth as an important defect. The code's width transition must account for the decoder learning dictionary entries one step after the encoder creates them; an off-by-one change can desynchronize the remaining bitstream even when the first few pixels look correct.

The project README supplied with the source describes a reference encoder/decoder exercise used during development. There is no independent automated test suite for the GIF decoder in this repository, so those historical results should not be interpreted as a currently repeatable CI test. A durable regression suite with generated GIF fixtures would be the next validation improvement.

## Video bridge status

`video_bridge.c` contains a proposed FFmpeg-based native bridge for frame decoding. It is explicitly marked in the source as not compiled or tested. The Lua integration also calls `imgui.CreateTextureFromRawBytes`, which is marked as a placeholder that must be matched to the actual ImGui binding. Consequently, MP4/video playback is experimental and should not be presented as a working feature. When the native bridge is present, the Lua side also rejects null handles and frame dimensions above 4,000,000 pixels before allocating a raw RGBA frame buffer. The current dependable media path documented here is GIF decoding and playback.

## Setup and requirements

- A compatible MoonLoader scripting host
- SAMPFUNCS and the ImGui integration used by the host
- LuaJIT FFI is needed only for the experimental native video bridge

Copy `scoreboard_gif_decoder.lua` into the host's MoonLoader scripts directory. The default interface toggle is **F9**; it can be changed through the settings panel.

## Limitations

The decoder limits the logical screen and each image descriptor to 4,000,000 pixels, and limits the aggregate logical-screen pixels copied across frames to 4,000,000 per decode. GIF timing, video frame scheduling, image transitions, and automatic image cycling use the host game timer; a one-second-resolution system clock is used only as a fallback. These bounds reduce runaway allocations but can reject long animations or very large images. Large or malformed media should still be tested carefully. The native video bridge requires a compatible FFmpeg build, a working compiler toolchain, and a verified texture-upload function before it can be considered usable.
