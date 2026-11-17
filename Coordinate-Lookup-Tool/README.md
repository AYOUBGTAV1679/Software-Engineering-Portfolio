# Coordinate Lookup Tool

Coordinate Lookup Tool is a compact Lua utility that resolves a participant's current position and moves the local character to that position. It also keeps an in-memory cache of positions observed while participants are available, which can be used by the host's replay workflow when a live session is no longer active.

## Behavior

- Resolve the current position of a connected participant when a live character handle is available.
- Attempt the host's streamed-out position lookup when a connected participant has no live character handle.
- Cache observed participant names and coordinates in memory while a session is active.
- In replay mode, use a cached coordinate rather than attempting a live lookup.
- Repeat the last successful target using the numpad `+` key.
- Move to the next cached participant using the numpad `*` key.

The cache is session memory. It is not a persistent coordinate database, and the script does not provide a saved fallback location on disk. The current navigation controls move forward through sorted cached IDs; there is no previous-target cycling control.

## Command

```text
.goto <player_id>
```

The command accepts an integer player ID from 0 through 999 and rejects fractional or out-of-range values before calling host APIs. It reports when the target is unavailable or its position cannot be resolved.

## Correctness detail: protected multi-value returns

The host position function returns a status value followed by three coordinate components. Wrapping it in Lua's `pcall` adds a second status value. The caller must therefore capture both flags and all three coordinates:

```lua
local call_ok, found, x, y, z = pcall(sampGetStreamedOutPlayerPos, id)
```

Capturing too few values shifts the coordinates into the wrong variables and drops the final component. The current implementation checks the `pcall` status and the native lookup status separately before using the coordinates.

The script also updates `lastId` only after a successful move, so a failed replay lookup does not replace the previous successful target.

## Requirements and setup

- A compatible MoonLoader scripting host
- SAMPFUNCS and the host position/participant functions used by the script

Copy `coordinate_lookup_tool.lua` into the host's MoonLoader scripts directory and reload it. The implementation relies on the host for live coordinates and on the in-memory cache for replay-mode behavior.

## Limitations

This is an environment-specific navigation utility, not a general GPS or mapping library. The cache is keyed by player ID; when an active slot is observed with a different nickname, its previous cached entry is discarded to avoid carrying coordinates across a visible slot reassignment. Cached positions may still become stale, disappear when the script session ends, or be unavailable for participants that were never observed. A successful coordinate lookup also does not guarantee that moving to the coordinate is safe or valid in every host state.
