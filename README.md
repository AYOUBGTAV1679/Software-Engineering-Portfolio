# Software Engineering Portfolio

A collection of independent software projects documenting practical work in programming, debugging, automation, static analysis, data handling, and application development.

This repository is intended as a general technical portfolio. It is not tailored to a particular university, employer, or application process. The goal is to make the engineering work reviewable: source code, design decisions, setup instructions, tests, known limitations, and build evidence should be available wherever the project supports them.

## Project index

| Project | Area | Repository status |
|---|---|---|
| [3D-Model-Loader](3D-Model-Loader/README.md) | Zeno Skin Changer — local skin discovery, selection, persistence, and walk-style controls | Source published; Lua 5.4 syntax check passed; custom-slot and timer behavior still need in-host validation |
| [Crash-Lag-Monitor](Crash-Lag-Monitor/README.md) | Crash Guard — performance monitoring and log diagnostics | Source published; protected warning-log I/O is CI-tested; log-rotation cursor checks added for CI; runtime validation pending |
| [Lua-Code-Checker](Lua-Code-Checker/README.md) | Static checks and conservative automatic fixes for Lua | Source published; Lua 5.4 CI and focused tokenizer/rule/autofix regressions passed; runtime validation pending |
| [Coordinate-Lookup-Tool](Coordinate-Lookup-Tool/README.md) | Position lookup and handling of protected multi-value returns | Source published; Lua 5.4 syntax check passed; host lookup and replay behavior still need validation |
| [Network-Session-Recorder](Network-Session-Recorder/README.md) | Session capture, binary storage, and playback | Source published; Lua 5.4 CI passed; runtime validation pending |
| [Scoreboard-GIF-Decoder](Scoreboard-GIF-Decoder/README.md) | Scoreboard interface and GIF/LZW decoding | Source, isolated parser, malformed-stream tests, interlaced fixtures through 12-bit LZW, and multi-frame animation fixture published; host runtime and broad GIF corpus pending |
| [Threaded-AI-Chat-API](Threaded-AI-Chat-API/README.md) | Non-blocking AI API requests from a cooperative scripting host | Source, provider-error tests, and stale interactive/prefetch/auto-open callback tests published; live host/provider validation pending |
| [Lua-Malware-Scanner — Aegis](Lua-Malware-Scanner/README.md) | Static analysis of Lua scripts, evidence-based findings, deobfuscation, and safe-copy sanitization | Source published; CI tests and Windows packaging build passed; device runtime not independently verified |

The project descriptions above are an index of the work intended for this portfolio. A project is not considered submitted or reviewable until its source is present and its own documentation explains what is actually implemented.

## Current repository contents

All eight projects are published as separate source directories with project-level documentation. The seven Lua-based projects retain their own source files and setup notes. Aegis is a separate Python application with CLI and GUI entry points, a test suite, sample Lua files, and a Windows packaging workflow.

The latest recorded successful Aegis Windows run ([#44254113483](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44254113483)) ran **206 tests**, completed the PyInstaller build, and packaged `Aegis-Windows-x64.zip`. The uploaded artifact is **269,856,329 bytes** (about 270 MB) and is listed to expire on **16 February 2027**. This confirms CI testing and packaging; it does not confirm that the GUI has been smoke-tested on a user's Windows device.

For the seven Lua projects, the [latest successful validation run](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44342873949) parsed all **31 tracked Lua files** with Lua 5.4 and passed a C syntax-only check for the optional FFmpeg bridge against Ubuntu FFmpeg development headers. This does not validate a Windows DLL build or actual playback. It also checked the Lua Code Checker fixture against its expected output (**3 errors, 3 warnings, 0 info**), passed **7 Crash Guard log-writer cases**, **7 Crash Guard log-cursor cases**, **8 Lua Code Checker tokenizer/rule/autofix regression cases**, and ran **17 GIF decoder cases**, **6 video timestamp helper cases**, **7 AI provider-error cases**, **9 asynchronous epoch cases** for interactive responses, prefetch, and delayed auto-open, **9 Network Session Recorder file-I/O cases**, and **8 recorder handshake epoch cases**. The GIF suite includes a 32×32 interlaced sample through 9-bit LZW codes, a 128×128 interlaced sample through 12-bit codes, and a three-frame animation covering transparency and restore-to-previous disposal. Video timestamp selection has its own pure-Lua tests; the FFmpeg bridge and ImGui texture upload remain experimental. The other focused suites cover provider error classification, stale asynchronous callbacks, recorder write/finalization failures, and delayed connection-handshake invalidation. These are repeatable syntax and focused regression checks; they do not establish full GIF conformance, MoonLoader integration, native video compilation, live API behavior, disk failure behavior on the target device, or runtime correctness in each project's target environment.

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
