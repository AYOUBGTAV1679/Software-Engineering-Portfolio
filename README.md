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

Aegis v0.8.2 is the first complete project source tree published in this repository. It includes the Python package, command-line and GUI entry points, analysis rules, sample Lua files, and a dedicated test suite. Its Windows packaging workflow is configured to run the tests and build a standalone application. The current build result and any downloadable artifact must be checked in the [GitHub Actions history](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions); the presence of a workflow does not by itself mean that a tested executable has been released.

The seven additional projects are now available as separate source directories. Each folder retains its project identity and includes the source files and a README describing implemented behavior, setup, validation, and known limitations. The portfolio-level [review note](PORTFOLIO_REVIEW.md) records static checks and distinguishes syntax validation from host-specific runtime testing. A dedicated [Lua validation workflow](https://github.com/AYOUBGTAV1679/Software-Engineering-Portfolio/actions/runs/44066484765) parses all 14 Lua files and checks the bundled analyzer fixture.

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
