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

- Parsed all 14 Lua source/fixture files in the seven projects with the installed Lua 5.4 shared library: **14 passed, 0 syntax errors**.
- Executed Lua Code Checker's included `tests/sample_bad.lua` fixture with the bundled checker: **3 errors and 2 warnings**, matching the fixture's documented expected output.
- Ran the checker across the 14 Lua files: it reported the intentional findings in `sample_bad.lua` plus heuristic warnings in some project files. These warnings need manual review; the checker is pattern-based and does not establish that each warning is a defect.
- Verified that the source archive can be recreated and read back as a ZIP without a CRC error.

## Not verified in this environment

- Runtime behavior that depends on the MoonLoader host, native functions, ImGui integration, packet/RPC hooks, or installed extensions.
- Successful live requests to Groq or OpenRouter; no live credentials or provider integration test were used.
- MP4 bridge compilation or execution. FFmpeg development headers/libraries were not available, and the source itself marks the bridge and texture-upload integration as unverified.
- Behavior against every supported host/client version or all possible input assets and recordings.

A syntax pass does not establish runtime correctness. The documented dependencies and limitations remain part of each project's setup and evaluation criteria.
