# Network Session Recorder

Network Session Recorder captures selected client-observed RPC and packet data into local recording files and provides playback controls for reviewing those recordings. It is a client-side capture tool: it records the events exposed to its hooks, not an authoritative server-side packet trace.

## Recording workflow

Recording is started explicitly and can be paused and stopped. The script writes data incrementally and flushes its output on a five-second elapsed-time schedule. The elapsed display and flush cadence use the host game timer, with a seconds-resolution system-clock fallback; they do not use Lua's process-CPU clock. Stopping moves the recorder into a finalization phase: the pending event queue is drained and the file is closed before another recording can start. This prevents two recorder workers from consuming the same shared queue when a new recording is started immediately after Stop. Before a new recording begins, it caches selected initialization and connection data; it also embeds a snapshot of currently connected participants' display metadata so the recording is less dependent on state that may no longer be available later.

The hook layer handles selected incoming RPCs, incoming packets, and outgoing packet types. Data is serialized into the project's own recording representation and stored under the configured recording directory.

## Playback

The source includes controls for:

- Loading and browsing saved recordings.
- Starting, pausing, and stopping playback.
- Seeking to a selected timestamp.
- Changing playback direction and speed, including reverse playback.
- Using a free-camera view or switching to a captured participant viewpoint.
- Configuring looping, notifications, overlays, and camera behavior.

Playback can only reproduce information that was captured, serialized, and supported by the replay handlers. It should not be described as a complete reconstruction of every event in an original session.

## Commands

| Command | Purpose |
|---|---|
| `/rm` | Open the control panel |
| `/rmstart` | Start a recording |
| `/rmstop` | Stop recording |
| `/rmpause` | Pause or resume recording |
| `/rewind HH:MM:SS` | Seek during playback |
| `/rmpossess <id>` | Switch to a participant viewpoint; omit the ID to leave that mode |

## Engineering work

- File operations at key read/write sites are guarded so ordinary path or file errors do not automatically become unhandled script failures.
- Seeking is committed when the user finishes the slider interaction instead of running for every intermediate drag value.
- Disabling participant viewpoint tracking also releases the associated camera/character state.
- Recording output is flushed on a periodic schedule, reducing the amount of buffered data exposed to an unexpected exit.

## Requirements and setup

- A compatible MoonLoader scripting host
- SAMPFUNCS and the packet/RPC hook functions used by the script
- The host's ImGui integration

Copy `network_session_recorder.lua` into the host's MoonLoader scripts directory. The script creates its working directory for recordings and settings when needed. Recording filename prefixes and nicknames are reduced to safe alphanumeric, underscore, and hyphen components, and a numeric suffix is added when a timestamp-based name already exists so a new session is not appended to an older recording.

## Data and limitations

The recording contains selected client-observed events and participant metadata. It is not a universal network sniffer, it does not guarantee that every event is captured, and playback fidelity depends on the recording data and the replay handlers available in the current host build. Keep in mind that recordings may contain session-identifying information; store and share them accordingly.
