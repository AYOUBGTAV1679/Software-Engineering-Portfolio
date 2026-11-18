# Scoreboard with a Custom GIF Decoder

## Overview

This project combines a configurable scoreboard and session-statistics interface with a GIF89a decoder implemented in Lua. The decoder is the main technical component: it parses the image structure, decompresses LZW data, composites frames, and stores decoded frame assets for reuse.

## Scoreboard interface

The script provides a live leaderboard, sorting and filtering controls, session statistics, configurable layout and colors, and selectable background media. The interface is designed for a MoonLoader-based host and is not a standalone desktop program.

## GIF decoding pipeline

The Lua decoder handles:

- GIF headers and logical screen descriptors.
- Global and local color tables, with bounds checks for truncated palette data.
- Graphic control extensions and image descriptors, including validation of control-block size, terminators, and extension sub-block boundaries.
- GIF87a/GIF89a signature validation and a required trailer marker; unknown block markers and incomplete files are rejected.
- Image rectangles must fit inside the logical screen, and decoded palette indices must exist in the active color table.
- LZW decompression with variable-width codes from 2 to 12 bits. Invalid or truncated code streams are rejected, and decoded output is capped at the image's declared pixel count.
- Clear and end-of-information codes and dictionary growth.
- Frame transparency, composition, and disposal handling.
- Frame timing and playback independent of the host's render callback rate, using elapsed host time rather than Lua's process-CPU clock.
- An on-disk cache of decoded frames and a manifest so repeat loads can reuse prior work.

This pipeline performs the parsing and decompression itself instead of delegating GIF decoding to a system image library.

## Bugs Fixed & Engineering Challenges

The development notes identify a boundary condition in LZW code-width growth as an important defect. The code's width transition must account for the decoder learning dictionary entries one step after the encoder creates them; an off-by-one change can desynchronize the remaining bitstream even when the first few pixels look correct.

The decoder now lives in a small pure-Lua core module, separate from the host-specific scoreboard UI and file-cache layer. This separation allows the parser to be exercised under standard Lua without loading MoonLoader, ImGui, or SAMPFUNCS. The regression suite builds compact GIF byte streams in memory and checks valid GIF87a/GIF89a files, a graphic-control extension, missing trailers, truncated extensions and image sub-blocks, out-of-bounds frames, invalid palette indices, invalid LZW references, missing LZW end codes, missing color tables, and unknown top-level markers. These are targeted regression fixtures, not a complete GIF conformance corpus.

## Decoder regression tests

Run the standalone checks from this project directory with Lua 5.4:

```sh
lua5.4 tests/test_gif_decoder.lua
```

The test suite exercises both accepted GIF signatures and the malformed-input boundaries listed above. It does not replace validation against a broad third-party GIF conformance corpus or testing in the target MoonLoader host.

## Video bridge status

`video_bridge.c` contains a proposed FFmpeg-based native bridge for frame decoding. It is explicitly marked in the source as not compiled or tested. The Lua integration also calls `imgui.CreateTextureFromRawBytes`, which is marked as a placeholder that must be matched to the actual ImGui binding. Consequently, MP4/video playback is experimental and should not be presented as a working feature. The Lua wrapper validates initial and reopened handles, checks frame dimensions against the 4,000,000-pixel limit, avoids retrying a failed decode on every render frame, and uses presentation-timestamp differences for pacing when they are usable (with a 30fps fallback). The timestamp calculation is covered by a small pure-Lua helper test, not by native playback tests. The current dependable media path documented here is GIF decoding and playback.

## Tech Stack

- Lua for the MoonLoader script and standalone GIF decoder core
- LuaJIT FFI for the optional, experimental native-video integration
- ImGui for the scoreboard and texture display
- C and FFmpeg for the proposed native bridge; the bridge is not compiled or runtime-verified
- Lua 5.4 for the standalone decoder and timing regression suites

## How to Use / Installation

- A compatible MoonLoader scripting host
- SAMPFUNCS and the ImGui integration used by the host
- LuaJIT FFI is needed only for the experimental native video bridge

Copy `scoreboard_gif_decoder.lua` into the host's MoonLoader scripts directory and `gif_decoder_core.lua` and `video_timing.lua` into the host's `moonloader/lib` directory so Lua can resolve both helper modules. The pure-Lua video timestamp helper can be checked separately with `lua5.4 tests/test_video_timing.lua`. These tests validate timestamp-delta selection only; they do not verify the FFmpeg bridge or ImGui texture upload. The test harness is for development/CI and does not need to be installed in the game. The default interface toggle is **F9**; it can be changed through the settings panel.

## Limitations

The decoder limits the logical screen and each image descriptor to 4,000,000 pixels, and limits the aggregate logical-screen pixels copied across frames to 4,000,000 per decode. GIF timing, video frame scheduling, image transitions, and automatic image cycling use the host game timer; a one-second-resolution system clock is used only as a fallback. These bounds reduce runaway allocations but can reject long animations or very large images. Large or malformed media should still be tested carefully. The native video bridge requires a compatible FFmpeg build, a working compiler toolchain, and a verified texture-upload function before it can be considered usable.


### GIF fixture regression tests

The checked-in fixtures live in `tests/fixtures/`. The 32×32 interlaced LZW sample exercises variable code widths through 9 bits. A separate 128×128 high-entropy interlaced sample, generated by a small Python GIF-LZW encoder and decoded successfully by Pillow, exercises 9-, 10-, 11-, and 12-bit codes, including dictionary resets. The three-frame restore-to-previous sample is generated by Pillow's GIF writer. Tests check decoded frame data with stable RGBA hashes and per-frame delays. A malformed restore-to-background sample was removed after inspection showed its LZW stream lacked a valid end code; that disposal case remains unverified. The parser validates the logical-screen background index and applies that palette color when disposal method 2 clears a frame rectangle. This remains a focused fixture set, not a complete GIF conformance corpus.


The 128×128 fixture extends coverage through the 9-to-10, 10-to-11, and 11-to-12-bit transitions. This is still a focused regression set rather than a full third-party GIF conformance corpus.

## License

No project-specific license file is currently included for this project. Review the source and any upstream notices before redistributing or reusing it; publication in this portfolio does not by itself grant additional redistribution rights.
