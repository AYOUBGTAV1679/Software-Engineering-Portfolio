# Crash Guard — Runtime Diagnostics Monitor

## Overview

Crash Guard is a Lua diagnostics script that combines performance sampling, resource-count monitoring, warning history, and log inspection. Its purpose is to provide useful signals for investigation; it does not claim to prevent every crash or raise the host application's engine-level resource limits.

## What it monitors

- **Adaptive frame-rate baseline:** records a rolling set of FPS samples and maintains a slower-moving baseline so a sustained drop can be compared with the current session's normal behavior.
- **Nearby resource counts by model:** enumerates vehicles within a 250-unit sphere around the local character and groups them by model ID. A configurable threshold controls when a repeated model count is reported.
- **Warning history:** appends diagnostic warnings to `moonloader/CrashGuard_log.txt` for later review.
- **Runtime log changes:** watches the host's log for other script failures and reports matching new lines. It observes the log; it does not repair or restart the affected script.
- **Lua garbage collection:** performs incremental collection steps and offers a manual cleanup command. This concerns Lua-managed memory, not the host engine's asset or streaming pool.
- **Status interface:** displays current FPS, resource counts, watchdog state, and the configured warning threshold.

## Commands

| Command | Purpose |
|---|---|
| `/cgstatus` | Print the current resource count and FPS |
| `/cgthreshold <number>` | Set the same-model warning threshold |
| `/cgclean` | Run the cleanup action |
| `/cgmenu` | Open the status and settings panel |
| `/cgwatchdog` | Toggle log-based monitoring of other scripts |
| `/cglog` | Show recent warnings from the persistent log |

## Bugs Fixed & Engineering Challenges

A single global FPS threshold is not a useful signal across machines with very different normal performance. Crash Guard therefore compares the recent frame-rate window with a slowly updated session baseline using the host game timer, and only treats a drop as an additional signal when nearby resource counts are already elevated. The vehicle scan is bounded to a 250-unit sphere around the local character rather than claiming to count every vehicle loaded anywhere in the world.

The user interface reads a cached monitoring snapshot rather than repeating full resource enumeration and log reads on every rendered frame. This keeps diagnostic work on the periodic monitoring path and avoids turning the panel itself into an unnecessary source of load.

Input for the resource threshold is converted to an integer before it is validated, preventing a positive fractional value from being accepted and then rounded down to zero.

## Tech Stack

- Lua in a MoonLoader-based client runtime
- MoonLoader game-timer, character-coordinate, and vehicle-enumeration functions
- ImGui for the monitoring and settings interface
- Standard Lua file I/O for warning history and log inspection
- A small protected file-writer helper for warning-log appends

## How to Use / Installation

- A compatible MoonLoader scripting host
- The host's ImGui integration (`imgui`)
- MoonLoader's vehicle-in-sphere search and game-timer functions

Copy `crash_lag_monitor.lua` into the host's MoonLoader scripts directory, and copy `crash_guard_log_writer.lua` into `moonloader/lib`. The script creates or appends its warning log under the MoonLoader directory. File open, write, and close failures are handled without raising through the monitoring path; the pure-Lua regression suite uses controlled fake file handles, not an actual disk-full device test.

The accompanying `.ini` file is a separate host-configuration artifact, not part of the Lua monitor. Review it against the local installation before using it; do not overwrite an existing configuration blindly.

## Scope and limitations

Crash Guard reports selected runtime signals. It cannot guarantee that an application will remain stable, detect every failure mode, diagnose every root cause, or change engine-level resource limits. Log matching is only as complete as the patterns recognized by the script and the data written by the host.

## License

No project-specific license file is currently included for this project. Review the source and any upstream notices before redistributing or reusing it; publication in this portfolio does not by itself grant additional redistribution rights.
