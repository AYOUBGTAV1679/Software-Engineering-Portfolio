# Software Engineering Portfolio

A collection of independent software projects documenting practical work in programming, debugging, automation, static analysis, data handling, and application development.

This repository is intended as a general technical portfolio. It is not tailored to a particular university, employer, or application process. Project descriptions are kept factual: implemented behavior, requirements, test evidence, and known limitations should be stated separately.

## Project index

| Project | Area |
|---|---|
| [3D-Model-Loader](3D-Model-Loader/) | Zeno Skin Changer — local skin discovery, selection, persistence, and walk-style controls |
| [Crash-Lag-Monitor](Crash-Lag-Monitor/) | Crash Guard — performance monitoring and log diagnostics |
| [Lua-Code-Checker](Lua-Code-Checker/) | Static checks and conservative automatic fixes for Lua |
| [Coordinate-Lookup-Tool](Coordinate-Lookup-Tool/) | Position lookup and handling of protected multi-value returns |
| [Network-Session-Recorder](Network-Session-Recorder/) | Session capture, binary storage, and playback |
| [Scoreboard-GIF-Decoder](Scoreboard-GIF-Decoder/) | Scoreboard interface and GIF/LZW decoding |
| [Threaded-AI-Chat-API](Threaded-AI-Chat-API/) | Non-blocking AI API requests from a cooperative scripting host |
| [Lua-Malware-Scanner](Lua-Malware-Scanner/) | Aegis — static analysis of Lua files and safe-copy sanitization |

## Repository status

The project index describes the intended portfolio structure; it must not be read as proof that every project has already been published in this repository.

At the current revision, the repository contains the portfolio overview, the Aegis source archive, and initial Aegis build/bootstrap files. The complete Aegis source restoration is being validated through GitHub Actions. The other seven project source directories have not yet been published here.

Build status and test results will only be described as successful after the corresponding workflow or test run completes successfully. A source archive, a successful static check, and a tested executable are different deliverables and will be identified separately.

## Documentation and evidence standard

Each project README should cover, where applicable:

- Problem statement and intended use.
- Implemented features, tied to source code.
- Architecture and important design choices.
- Runtime, dependencies, and setup instructions.
- Reproducible test commands and actual test results.
- Known limitations, unsupported cases, and security considerations.
- Build and release status, distinguishing source availability from tested binaries.

The portfolio avoids unsupported performance claims, inflated descriptions, and claims of production readiness without evidence. Where something has not been tested, that fact should be stated directly.

## Compatibility note

The projects target different runtimes and environments. For example, MoonLoader scripts require a compatible GTA: San Andreas multiplayer client and supporting components. Aegis and Lua Code Checker are separate tools with their own runtime requirements.
