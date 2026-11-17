# Portfolio Review and Verification Notes

This note records the checks performed on the seven project sources in this bundle. It separates syntax/static checks from integration tests that require each project's target host or external service.

## Changes made

- Reworked the seven project READMEs to match the source more closely, preserve each project's identity, and describe limitations where a feature is incomplete or depends on host-specific APIs.
- Corrected the documented walk-style range in Zeno Skin Changer to IDs `0` through `20`.
- Corrected Coordinate Lookup Tool documentation: its coordinate cache is in memory, its replay navigation moves to the next cached participant and repeats the last successful target, and it does not implement a persistent fallback-coordinate store or previous-target cycling.
- Removed unsupported claims about replaying dialog events from Network Session Recorder documentation.
- Marked the MP4 bridge in Scoreboard GIF Decoder as experimental: the C bridge is explicitly uncompiled/untested in its own source, and the Lua texture-upload call is a placeholder.
- Corrected RP Respond AI's provider-routing defect. Requests now select the endpoint and API key associated with the active provider, and key validation follows the active provider rather than always requiring the Groq key.
- Rewrote the portfolio index to describe the engineering focus of all eight project folders without promotional claims.

## Verification performed

- Parsed all 14 Lua source/fixture files in the seven projects locally with Lua 5.4: **14 passed, 0 syntax errors**. The same check is now enforced by the repository's GitHub Actions workflow.
- Executed Lua Code Checker's included `tests/sample_bad.lua` fixture with the bundled checker: **3 errors and 2 warnings**, matching the fixture's expected output. The CI job checks both the expected exit code and the exact summary.
- Ran the checker across the 14 Lua files: it reported the intentional findings in `sample_bad.lua` plus heuristic warnings in some project files. These warnings need manual review; the checker is pattern-based and does not establish that each warning is a defect.
- Added `.github/workflows/validate-lua-projects.yml` to parse all 14 Lua files and validate the analyzer fixture on pushes and pull requests. GitHub Actions run [#44066484765](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44066484765) completed successfully.

## Not verified in this environment

- Runtime behavior that depends on the MoonLoader host, native functions, ImGui integration, packet/RPC hooks, or installed extensions.
- Successful live requests to Groq or OpenRouter; no live credentials or provider integration test were used.
- MP4 bridge compilation or execution. FFmpeg development headers/libraries were not available, and the source itself marks the bridge and texture-upload integration as unverified.
- Behavior against every supported host/client version or all possible input assets and recordings.

A syntax pass does not establish runtime correctness. The documented dependencies and limitations remain part of each project's setup and evaluation criteria.

## Follow-up API and build audit

- **Zeno Skin Changer:** replaced the undocumented TXD call with the documented `loadTextureDictionary` function and changed walk-style playback to the documented `requestAnimation` / `taskPlayAnim` flow, including an animation-loaded check. The source now reports missing host APIs rather than blindly calling an absent TXD/DFF loader. Custom DFF loading still requires an extension that supplies `loadModelInfo`; the target host must be identified and smoke-tested before these paths can be called operational.
- **Aegis Windows package:** run [#43928542059](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/43928542059) passed **206 tests**, built `dist/Aegis/Aegis.exe`, and uploaded `Aegis-Windows-x64.zip` (269,855,143 bytes). PyInstaller emitted Qt-related collection warnings during the successful build. The workflow did not launch the GUI for a smoke test on a separate Windows device.
- **Threaded AI Chat API:** the source now resolves the endpoint and API key together from the selected provider. No live Groq or OpenRouter request has been verified, because no live credentials were used.

## Next validation priorities

1. Identify or replace the external DFF-loading extension required by Zeno Skin Changer, then smoke-test the TXD and walk-style paths in the target host.
2. Run each MoonLoader project in its supported host and record reproducible smoke-test steps and results.
3. Launch the packaged Aegis application on a Windows device and verify startup, scanning, report export, and shutdown.
4. Exercise provider selection with test credentials while keeping secrets out of the repository.
5. Add generated GIF fixtures and native bridge build checks before describing the video path as supported.
