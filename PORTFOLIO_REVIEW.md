# Portfolio Review and Verification Notes

This note records the checks performed on the seven Lua-based project sources in this portfolio, alongside the separately documented Aegis application. It separates syntax/static checks from integration tests that require each project's target host or external service.

## Changes made

- Reworked the seven project READMEs to match the source more closely, preserve each project's identity, and describe limitations where a feature is incomplete or depends on host-specific APIs.
- Corrected the documented walk-style range in Zeno Skin Changer to IDs `0` through `20`.
- Corrected Coordinate Lookup Tool documentation: its coordinate cache is in memory, its replay navigation moves to the next cached participant and repeats the last successful target, and it does not implement a persistent fallback-coordinate store or previous-target cycling.
- Removed unsupported claims about replaying dialog events from Network Session Recorder documentation.
- Marked the MP4 bridge in Scoreboard GIF Decoder as experimental: the C bridge is explicitly uncompiled/untested in its own source, and the Lua texture-upload call is a placeholder.
- Corrected RP Respond AI's provider-routing defect. Requests now select the endpoint and API key associated with the active provider, and key validation follows the active provider rather than always requiring the Groq key.
- Rewrote the portfolio index to describe the engineering focus of all eight project folders without promotional claims.

## Verification performed

- Parsed all 15 tracked Lua source and test files in the seven projects with Lua 5.4: **15 passed, 0 syntax errors** in GitHub Actions run [#44120765189](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44120765189).
- Executed Lua Code Checker's included `tests/sample_bad.lua` fixture with the bundled checker: **3 errors and 3 warnings**, matching the fixture's expected output. The CI job checks both the expected exit code and the exact summary. The focused regression script also passed its namespace allowlist and escaped-newline line-number assertions.
- Ran the checker across the 15 Lua files: it reported the intentional findings in `sample_bad.lua` plus heuristic warnings in some project files. These warnings need manual review; the checker is pattern-based and does not establish that each warning is a defect.
- Added `.github/workflows/validate-lua-projects.yml` to parse all 15 Lua files, validate the analyzer fixture, and run focused regression checks on pushes and pull requests. GitHub Actions run [#44120765189](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44120765189) completed successfully.

## Not verified in this environment

- Runtime behavior that depends on the MoonLoader host, native functions, ImGui integration, packet/RPC hooks, or installed extensions.
- Successful live requests to Groq or OpenRouter; no live credentials or provider integration test were used.
- MP4 bridge compilation or execution. FFmpeg development headers/libraries were not available, and the source itself marks the bridge and texture-upload integration as unverified.
- Behavior against every supported host/client version or all possible input assets and recordings.

A syntax pass does not establish runtime correctness. The documented dependencies and limitations remain part of each project's setup and evaluation criteria.

## Follow-up API and build audit

- **Zeno Skin Changer:** replaced the undocumented TXD call with the documented `loadTextureDictionary` function and changed walk-style playback to the documented `requestAnimation` / `taskPlayAnim` flow, including an animation-loaded check. The source now reports missing host APIs rather than blindly calling an absent TXD/DFF loader. It also compares the logical saved skin ID against the correct runtime slot for custom models, preventing an unnecessary reload loop. Custom DFF loading still requires an extension that supplies `loadModelInfo`; the target host must be identified and smoke-tested before these paths can be called operational.
- **Aegis Windows package:** run [#43928542059](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/43928542059) passed **206 tests**, built `dist/Aegis/Aegis.exe`, and uploaded `Aegis-Windows-x64.zip` (269,855,143 bytes). PyInstaller emitted Qt-related collection warnings during the successful build. The workflow did not launch the GUI for a smoke test on a separate Windows device.
- **Threaded AI Chat API:** the source now resolves the endpoint and API key together from the selected provider. No live Groq or OpenRouter request has been verified, because no live credentials were used.

## Next validation priorities

1. Identify or replace the external DFF-loading extension required by Zeno Skin Changer, then smoke-test the TXD and walk-style paths in the target host.
2. Run each MoonLoader project in its supported host and record reproducible smoke-test steps and results.
3. Launch the packaged Aegis application on a Windows device and verify startup, scanning, report export, and shutdown.
4. Exercise provider selection with test credentials while keeping secrets out of the repository.
5. Add generated GIF fixtures and native bridge build checks before describing the video path as supported.

## Crash Guard API and timing audit

- Replaced the project’s unsupported `FindFirstVehicle` / `FindNextVehicle` / `EndFindVehicle` enumeration calls. Those names are not present in the checked MoonLoader opcode reference. Vehicle counting now uses `findAllRandomVehiclesInSphere` around the local character, with a 250-unit radius, a duplicate guard, and a per-scan ceiling.
- Replaced `os.clock()` for frame timing and periodic intervals with the host's `getGameTimer()`. Lua's `os.clock()` measures process CPU time; it is not a reliable wall-clock source for frame-to-frame intervals across calls to `wait(0)`.
- Updated command/UI messaging and the README to state the actual scan radius. The script now reports when the vehicle scan API is unavailable rather than presenting an empty result as zero vehicles.
- These changes are source-level corrections. They need MoonLoader runtime validation, especially the iterator behavior and its returned vehicle handles, before they can be considered verified in the target host.

## Lua Code Checker follow-up regression fixes

- Tightened `unverified-require` so the allowlist matches only the first module namespace segment. A trusted word appearing later in a dotted module name no longer suppresses a finding for an unknown root module.
- Corrected tokenizer line tracking when a short string contains an escaped newline.
- Made command-line module lookup accept both Unix and Windows path separators when the checker is invoked through a path.
- Extended the intentional fixture to cover a misleading nested module name and added focused Lua regression tests. CI now checks **15 Lua files**, the expected fixture summary (**3 errors, 3 warnings, 0 info**), and the focused regression assertions.
- Clarified interpreter compatibility: the implementation uses `goto`, which is native in Lua 5.2+ and supported by LuaJIT 2.1; it should not be advertised as compatible with a plain Lua 5.1 interpreter.
- CI follow-up: the first regression-test invocation ran from the repository root, so Lua's default module path could not resolve the checker modules. The workflow now runs that test from the project directory, matching its module layout.

## Coordinate Lookup Tool input and cache audit

- Added an explicit integer player-ID guard for the supported scan/cache range (0–999). Invalid, fractional, negative, and out-of-range command values are rejected before host lookup or teleport functions are called.
- When a connected player slot is observed with a different nickname, the prior cached entry for that slot is invalidated before refreshing its coordinates. This reduces the risk of replay navigation using coordinates associated with a previous visible occupant of the same ID.
- The cache remains session-only and keyed by numeric player ID. Nickname comparison cannot prove identity when names are reused, and cached positions can still be stale. Runtime behavior still requires validation in the target host.


## Network Session Recorder lifecycle and filename audit

- Prevented overlapping recorder workers. Stop now enters a finalization phase; the active worker drains queued events, flushes and closes its file, then releases the closing guard. A new recording is rejected until this finishes, preventing two workers from consuming the shared event queue.
- A new recording resets its queue and wait counters. File-open failure also clears the pending state so events collected during a failed start are not carried into a later recording.
- Sanitized the user-configurable filename prefix and captured nickname before building a path. Existing timestamp collisions receive a numeric suffix instead of opening the previous recording in append mode.
- These are source-level lifecycle and path-safety corrections. Packet/RPC capture and replay still require runtime testing in the target host; the changes do not validate replay compatibility across host versions.


## Scoreboard GIF decoder input and allocation audit

- Hardened the LZW decoder to reject invalid dictionary references, truncated streams without an end code, and decoded output that does not exactly match the image descriptor's pixel count. It stops before appending output beyond the declared count.
- Added validation for GIF LZW minimum code size, missing color tables, truncated global/local palettes, truncated image sub-blocks, and invalid image descriptors.
- Added an aggregate decoded-frame pixel budget in addition to logical-screen and per-image dimension checks. The README documents that this bounds allocations but may reject long animations.
- The changes have not yet been exercised against a generated GIF regression corpus or the target host's texture-loading path. CI syntax validation is not a substitute for GIF conformance tests.


## Threaded AI Chat API timeout and worker error audit

- Replaced os.clock deadlines in both HTTP-result polling loops. That function measures process CPU time, so it is unsuitable for elapsed request deadlines in a cooperative script that yields frequently. The code now uses the host game timer in milliseconds, with a seconds-resolution os.time fallback when the host timer is unavailable.
- Moved the requests module load inside the worker's protected call. A missing HTTP dependency now travels back as an error result instead of terminating the lane without notifying its caller.
- Protected Linda/channel and worker creation. Setup failures are placed into the request result queue so the UI can surface an actionable error.
- This does not forcibly cancel a running HTTP call after its deadline, and no live provider request has been verified. The script still requires real credentials and the documented host dependencies.


## Network Session Recorder timing and write-buffer audit

- Removed the per-record flush from the queue writer. The writer now buffers sequential writes and flushes on a five-second elapsed-time schedule, followed by a final flush at close, avoiding a disk flush for every captured event.
- Replaced process-CPU-time measurements for recording duration and periodic flush checks with the host game timer (milliseconds), falling back to system time at one-second resolution. This makes the displayed duration and five-second flush interval track elapsed time while the script yields.
- The recorder still needs host runtime testing under sustained packet load and forced file-write failures. The CI Lua parser does not exercise disk throughput or native hooks.


- The short response-correlation window used by the RP-script heuristic now uses the same elapsed-time clock as request deadlines. It no longer compares events with os.clock process-CPU time, which could distort a three-second window while the host yields.


- Replaced process-CPU-time clock reads for GIF frame delays, experimental video frame scheduling, image transitions, and automatic background cycling with the host game timer in seconds. A one-second-resolution system clock is used only if the host timer is unavailable. This corrects elapsed-time measurement but does not validate the experimental video bridge.


- Added defensive handling for the experimental video bridge: null native handles are rejected, and invalid or oversized dimensions are closed and rejected before the Lua side allocates a raw RGBA frame buffer. The bridge remains uncompiled and untested; this guard is not evidence that video playback works.


## Latest repository-wide Lua CI result

- Workflow run [#44116518796](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44116518796) completed successfully on the current source commit before this documentation-only refresh.
- The workflow parsed all 15 tracked Lua source/test files with Lua 5.4, checked the fixture's expected **3 errors, 3 warnings, 0 info** output, and ran the Lua Code Checker regression tests.
- The run confirms Lua syntax and these focused regression assertions. It does not exercise the MoonLoader runtime, decode a generated GIF corpus, compile the FFmpeg bridge, or make a live provider request.


## GIF decoder malformed-input handling

- Tightened container validation to accept only GIF87a/GIF89a signatures, validate Graphic Control Extension size and terminator, bounds-check generic extension sub-blocks, reject unknown block markers, and require the GIF trailer before returning decoded frames.
- The LZW decoder rejects invalid dictionary references, truncated streams, and output that does not exactly match the frame descriptor. The aggregate decoded-screen pixel budget remains in place.
- No generated fixture corpus or target-host texture integration test has been run. These changes are source-level defensive checks and remain subject to decoder conformance testing.

## Threaded AI request worker lifecycle

- Retained the lane handle for each active HTTP request. When the request deadline expires, the polling coroutine now requests hard lane cancellation and reports the timeout rather than silently abandoning the worker.
- The implementation deliberately does not force-kill a worker. Lua Lanes cancellation is cooperative; a worker blocked inside a native/network call may not process cancellation until control returns to Lua. This limitation is documented.
- Provider routing and API-key selection remain paired at request creation. No live provider request has been made as part of this source review.


## Latest validation after the November 17 source updates

- GitHub Actions run [#44120765189](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44120765189) completed successfully on commit `695f9b0`.
- All 15 tracked Lua files parsed with Lua 5.4; the Lua Code Checker fixture produced its expected 3 errors and 3 warnings; the focused regression script passed.
- The run validates syntax and the checker's included regression cases. It does not execute the GIF decoder against a conformance corpus, compile the optional native video bridge, exercise the host-specific Lua scripts, or send a live AI provider request.


## Additional parser and worker failure checks

- GIF image descriptors that extend outside the logical screen are rejected instead of silently clipped. Decoded color indices that are absent from the selected global/local palette are rejected instead of silently leaving pixels transparent.
- The Threaded AI polling coroutine now checks the retained lane's status. A lane ending in an error, cancellation, or kill state is surfaced as a worker error rather than waiting until the full request deadline.
- These are source-level checks. The GIF decoder still needs a generated valid/malformed fixture corpus, and the AI worker lifecycle still needs integration testing with the exact Lua Lanes and HTTP module versions used by the target host.


- Scoped the Threaded AI response-cache key by the active provider and model. A prompt cached under one backend/model can no longer be reused after switching to a different provider or rotating models.


## Final CI check for the latest source commit

- Commit `701f3a2` scopes Threaded AI cache entries by provider and model, in addition to the worker lifecycle and GIF parser validation updates in its parent commit.
- GitHub Actions run [#44120765189](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44120765189) completed successfully: all 15 tracked Lua files parsed, the analyzer fixture matched its expected 3 errors and 3 warnings, and the focused regression tests passed.
- These checks do not execute MoonLoader runtime paths, GIF conformance fixtures, native video compilation, or live provider requests.
