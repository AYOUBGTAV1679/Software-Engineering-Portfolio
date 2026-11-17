# Software Engineering Portfolio

A collection of independent software projects documenting practical work in programming, debugging, automation, static analysis, data handling, and application development.

This repository is intended as a general technical portfolio. It is not tailored to a particular university, employer, or application process. The goal is to make the engineering work reviewable: source code, design decisions, setup instructions, tests, known limitations, and build evidence should be available wherever the project supports them.

## Project index

| Project | Area | Repository status |
|---|---|---|
| 3D-Model-Loader | Zeno Skin Changer — local skin discovery, selection, persistence, and walk-style controls | Source published; Lua 5.4 CI passed; runtime validation pending |
| Crash-Lag-Monitor | Crash Guard — performance monitoring and log diagnostics | Source published; Lua 5.4 CI passed; runtime validation pending |
| Lua-Code-Checker | Static checks and conservative automatic fixes for Lua | Source published; Lua 5.4 CI passed; runtime validation pending |
| Coordinate-Lookup-Tool | Position lookup and handling of protected multi-value returns | Source published; Lua 5.4 CI passed; runtime validation pending |
| Network-Session-Recorder | Session capture, binary storage, and playback | Source published; Lua 5.4 CI passed; runtime validation pending |
| Scoreboard-GIF-Decoder | Scoreboard interface and GIF/LZW decoding | Source published; Lua 5.4 CI passed; runtime validation pending |
| Threaded-AI-Chat-API | Non-blocking AI API requests from a cooperative scripting host | Source published; Lua 5.4 CI passed; runtime validation pending |
| [Lua-Malware-Scanner — Aegis](Lua-Malware-Scanner/README.md) | Static analysis of Lua scripts, evidence-based findings, deobfuscation, and safe-copy sanitization | Source published; CI tests and Windows packaging build passed; device runtime not independently verified |

The project descriptions above are an index of the work intended for this portfolio. A project is not considered submitted or reviewable until its source is present and its own documentation explains what is actually implemented.

## Current repository contents

All eight projects are published as separate source directories with project-level documentation. The seven Lua-based projects retain their own source files and setup notes. Aegis is a separate Python application with CLI and GUI entry points, a test suite, sample Lua files, and a Windows packaging workflow.

The latest recorded successful Aegis Windows run ([#43928542059](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/43928542059)) ran **206 tests**, completed the PyInstaller build, and packaged the application as `Aegis-Windows-x64.zip`. GitHub Actions reports an artifact size of about **270 MB**, available through **14 February 2027**. This confirms CI testing and packaging; it does not confirm that the GUI has been smoke-tested on a user's Windows device.

For the seven Lua projects, the [latest Lua validation run](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44122458011) parsed all **17 tracked Lua files** with Lua 5.4, ran the GIF decoder's generated valid/malformed-input regression suite, checked the Lua Code Checker fixture against its expected output (**3 errors, 3 warnings, 0 info**), and passed focused regression tests for module allowlisting and escaped-newline line tracking. The latest run (#44122458011) includes the current Coordinate Lookup, Network Session Recorder, Scoreboard, and Threaded AI Chat source updates, and passed the same Lua 5.4 syntax and checker regression steps. These checks confirm syntax and the tested analyzer cases only. They do not verify MoonLoader integrations, GIF conformance, native video compilation, live API requests, or runtime behavior in each project's target environment.

The [portfolio review](PORTFOLIO_REVIEW.md) records completed checks, unresolved integration issues, and the next validation priorities. Check the [GitHub Actions history](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions) for the latest run state and artifact availability.

## How to review a project

Each project README should make it possible to understand the work without relying on a verbal explanation. Depending on the project, it should cover:

- The problem being addressed and the intended use.
- Implemented behavior, with pointers to the relevant source modules.
- Architecture, data flow, and important design decisions.
- Runtime requirements, dependencies, installation, and usage.
- Tests that can be repeated, with actual results rather than estimates.
- Known limitations, unsupported cases, and security considerations.
- Build and release status, distinguishing source availability from tested binaries.

## Engineering and evidence standard

The portfolio avoids unsupported performance claims, inflated feature descriptions, and claims of production readiness without evidence. Test results must identify the test set and environment; benchmark results must not be presented as universal real-world accuracy. Optional integrations must be identified as optional, and anything that has not been tested against a live service should be described accordingly.

The projects target different runtimes and environments. MoonLoader-based scripts require a compatible host runtime and supporting components. Aegis and Lua Code Checker are separate tools with their own runtime requirements.
