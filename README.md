# Software Engineering Portfolio

This repository groups eight independent projects built around practical software engineering problems: static analysis, runtime diagnostics, binary data handling, session recording, API integration, and in-game tooling.

Each project has its own folder and README. The project folders, source filenames, and original code are preserved; the documentation has been rewritten to explain what each project actually does, how it is structured, and where its current boundaries are.

## Projects

| Project folder | Focus |
|---|---|
| `3D-Model-Loader` | Zeno Skin Changer — local skin discovery, selection, persistence, and walk-style controls |
| `Crash-Lag-Monitor` | Crash Guard — adaptive performance monitoring and log diagnostics |
| `Lua-Code-Checker` | Lua static checks and conservative automatic fixes |
| `Coordinate-Lookup-Tool` | Position lookup and correct handling of protected multi-value returns |
| `Network-Session-Recorder` | Session capture, binary storage, and reversible playback |
| `Scoreboard-GIF-Decoder` | Live scoreboard UI and a custom GIF/LZW decoder |
| `Threaded-AI-Chat-API` | Non-blocking AI API requests from a cooperative scripting host |
| `Lua-Malware-Scanner` | Aegis — evidence-based static analysis and safe-copy sanitization |

## How to use this portfolio

Open an individual project folder and start with its `README.md`. Each README covers the problem, the implemented behavior, important engineering decisions, setup requirements, and known limitations.

The projects target different environments. In particular, the MoonLoader scripts require a compatible GTA: San Andreas multiplayer client and its supporting components. Aegis and Lua Code Checker are separate tools with their own runtime requirements.

## Documentation standard

The READMEs aim to be specific rather than promotional. They describe tested behavior and documented results, distinguish client-side features from server-side behavior, and call out limitations where the source does not establish broader guarantees.
