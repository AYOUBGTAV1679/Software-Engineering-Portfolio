# Portfolio Review and Verification Notes

This document records the current engineering state of the eight projects. It distinguishes checks that can be repeated in CI from behavior that still requires the original host application, native dependencies, Windows, or live services.

## Repository-wide verification

The latest Lua validation run, [GitHub Actions #44257398339](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44257398339), completed successfully on commit `8f1a7a5fbcc70ec68e92d36e59d6cab3fab86db9`.

The workflow:
- Parsed all **29 tracked Lua files** across the seven Lua projects with Lua 5.4.
- Ran **7 Crash Guard log-writer regression cases** covering open, write, and close failures, including thrown errors and handle cleanup.
- Checked the Lua Code Checker fixture against its expected result: **3 errors, 3 warnings, 0 info**.
- Ran **8 Lua Code Checker regression cases** for module allowlisting, escaped-newline line tracking, `io.popen()` call boundaries, nested `do` loop scopes, and conservative autofix behavior.
- Ran **17 GIF decoder regression cases**, including the malformed-input cases, an independently encoded interlaced multi-pixel fixture that crosses LZW code-width boundaries, and a three-frame transparency/disposal fixture.
- Ran **7 provider-error classifier cases**, including rate-limit and missing-model responses plus an unrelated invalid-key response.
- Ran **9 AI asynchronous epoch regression cases**, checking token freshness for interactive responses, prefetch requests, and delayed auto-open tasks.
- Ran **6 video timestamp helper cases**, covering valid variable frame intervals and fallback behavior for repeated, backward, missing, non-finite, and excessive timestamp gaps.
- Ran **9 Network Session Recorder file-I/O regression cases**, including reported/thrown write failures and cleanup after flush/close errors.
- Ran **8 Network Session Recorder handshake epoch cases**, covering stale callback rejection and include-once handling across a new Start snapshot.

The Aegis Windows packaging workflow completed [run #44254113483](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44254113483) with **206 passing tests**, a successful PyInstaller build, and an uploaded `Aegis-Windows-x64.zip` artifact of 269,856,329 bytes. The artifact is listed to expire on **16 February 2027**. This is CI build and test evidence; it is not a GUI smoke test on a separate Windows device.

## Project-specific engineering notes

### 3D Model Loader — Zeno Skin Changer

The source now uses the documented `loadTextureDictionary` and animation request/playback flow rather than the earlier unsupported calls. The walk-style IDs documented by the project are **0–20**. The pending skin-load timeout and periodic UI/reapplication timers now use the host elapsed game timer instead of `os.clock()` process time; host runtime behavior still needs a smoke test. The custom DFF path still depends on an external extension exposing `loadModelInfo`; that extension and the complete custom-model path need to be identified and tested in the target host.

### Crash Guard

The script uses the host game timer for elapsed-time measurements and scans vehicles around the local character through `findAllRandomVehiclesInSphere`. Warning-log appends now use a small helper that protects open, write, and close separately; even when a write throws or returns an I/O error, the file handle is still closed and the failure does not escape into monitoring. The documented scan radius is **250 units**, with duplicate handling and a per-scan ceiling. The scan is not a count of every vehicle in the full game world. Iterator behavior and returned handles still require a MoonLoader runtime test.

### Lua Code Checker

The checker includes tokenizer, rules, conservative automatic fixes, and focused regression cases. CI checks the intentional sample fixture's exact summary and validates path handling, namespace allowlisting, and escaped-newline line tracking. The implementation uses `goto`, so it should be described as compatible with Lua 5.2+ and LuaJIT 2.1 rather than plain Lua 5.1.

### Coordinate Lookup Tool

Player IDs are checked as integers in the supported **0–999** range before host lookup calls. A cached slot is invalidated when a different nickname is observed for that ID. The cache is session-only; a nickname change check cannot prove identity if names are reused, and cached positions can become stale. Host behavior has not been independently smoke-tested.

### Network Session Recorder

The recorder prevents overlapping workers during stop/finalization, drains the pending queue before closing, resets queue state at the next start, and sanitizes user-controlled filename parts. A generation token invalidates delayed connection-handshake callbacks when a newer INITGAME arrives; the cached player-ID/nickname handshake is cleared immediately so a new recording cannot combine initialization data with stale connection metadata. Start freezes its initialization snapshot, while the callback tracks whether that same INITGAME generation has already been written or queued, preventing duplicate preambles. The eight-case pure-Lua epoch suite checks freshness and this include-once bookkeeping; the nine file-I/O helper cases remain separate. The final quiet interval is now written as a trailing wait record. Checked file operations detect write and periodic-flush failures; the worker uses a protected cleanup path, and finalization attempts close even when flush fails. The recording page's elapsed display now uses the same host timer and millisecond-to-second conversion as the recording overlay and flush scheduler. The pure-Lua file-I/O helper suite passed 9 controlled fake-handle cases. This is not a real disk-full test: packet/RPC capture, replay compatibility, sustained traffic, and actual disk failure behavior still need validation in the target host.

### Scoreboard GIF Decoder

The GIF parsing and LZW logic has been separated into the pure-Lua `gif_decoder_core.lua` module. A small `video_timing.lua` helper chooses a safe frame interval from increasing presentation timestamps and falls back to 30fps when timestamps are unusable; its standalone regression tests do not verify native video decoding or the ImGui texture API. The 17-case CI regression suite constructs malformed GIF streams in memory and reads three valid fixtures. A 32×32 interlaced image exercises code-width growth through 9 bits. A separate 128×128 high-entropy interlaced sample, generated by a Python GIF-LZW encoder and decoded successfully by Pillow, exercises 9-, 10-, 11-, and 12-bit codes, including dictionary resets. A three-frame Pillow-generated animation verifies transparency, frame composition, delay values, and restore-to-previous disposal. A background-index bounds check is also covered. A malformed restore-to-background fixture was removed because its LZW stream lacked a valid end code; restore-to-background disposal is therefore not currently covered by a valid fixture. The malformed-input cases check accepted GIF87a/GIF89a headers, graphic-control extensions, trailer handling, truncated extension and image sub-blocks, logical-screen bounds, palette-index validation, invalid LZW dictionary references, missing LZW end codes, missing color tables, and unknown block markers.

The suite is now broader than the original generated-only tests, but it is still a focused regression set, not a complete third-party GIF conformance corpus. Texture loading and playback still need testing in the target MoonLoader/ImGui environment. The optional `video_bridge.c` remains uncompiled and untested, and the Lua texture upload call is explicitly a placeholder; MP4 playback must remain labelled experimental. The Lua wrapper now validates the loop-reopen handle and avoids tight retry loops after native decode errors.

Installation note: the scoreboard script requires `gif_decoder_core.lua` and `video_timing.lua` in the host's `moonloader/lib` directory.

### Threaded AI Chat API

HTTP requests run in Lua Lanes workers, and the main coroutine polls for a result. The request captures its provider, model, endpoint, and API key at creation so a provider switch during an in-flight request does not redirect it. Delayed model errors only rotate the active model when the failed request still matches the current provider/model selection.

Provider error classification is isolated in `provider_error_classifier.lua` and covered by seven pure-Lua regression cases. Recognized rate-limit and unavailable-model payloads are normalized before reaching model rotation. Interactive response callbacks, prefetch callbacks, and delayed auto-open tasks use generation tokens. Context changes invalidate stale requests and any pending auto-open timer; toggling auto-open also cancels its pending delay. Provider switches and model rotation invalidate stale prefetch results so they cannot be associated with the new selection. The nine-case helper suite checks token freshness and separation, but it does not simulate the full MoonLoader event loop. The script deliberately requests lane cancellation on timeout without force-killing a worker; cancellation may not interrupt a worker blocked in a native or network call.

No live Groq or OpenRouter request has been verified. The exact Lua Lanes and HTTP module versions in the target host also need compatibility testing. Installation note: copy `provider_error_classifier.lua` and `prefetch_epoch.lua` into `moonloader/lib` alongside the other documented dependencies. Do not commit real API keys.

### Lua Malware Scanner — Aegis

Aegis is a separate Python application with CLI and GUI entry points. Its CI evidence currently covers the 206-test suite and Windows packaging. A separate Windows runtime smoke test is still needed for GUI startup, scanning, report export, and shutdown.

## Remaining validation work

1. Test the seven MoonLoader projects in their supported host and record reproducible smoke-test results.
2. Expand GIF coverage with an external conformance corpus and test real texture loading/playback.
3. Compile and integrate the optional native video bridge only after the FFmpeg toolchain and ImGui texture API are confirmed.
4. Test provider switching, model rotation, worker timeout, and cancellation against live services using private credentials.
5. Run Aegis on a Windows device and verify the GUI workflow.
6. Exercise Network Session Recorder under sustained traffic and controlled file-write failures.

A successful syntax or unit-test run is useful evidence, but it does not replace integration testing in each project's actual runtime.
