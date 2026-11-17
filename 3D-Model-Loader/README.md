# Zeno Skin Changer

Zeno Skin Changer is a Lua utility for a supported MoonLoader-based client. It combines a searchable model catalogue, local asset discovery, per-player visual assignments, personal settings, and a small walk-style manager in one interface.

The implementation is useful as a study in keeping several kinds of state separate: the current UI selection, the user's saved choice, imported asset metadata, temporary name-based assignments, and runtime reapplication state.

## Capabilities

- Browse and filter the built-in model catalogue.
- Discover additional model assets from configured folders and an INI file.
- Save or clear a personal model choice and apply it again when the local character is recreated.
- Assign a local visual override by player ID or nickname for the current session.
- Apply one of 21 configured walk styles (IDs `0` through `20`) to the local character or a selected participant.
- Change the interface hotkey and retain that setting between sessions.

The main window is opened with `/zskin` or the configured hotkey. The exact interaction and available controls are defined by the Lua source.

## Asset configuration

The script reads optional manual entries from:

```text
moonloader/zskin_skins.ini
```

It also scans folders under:

```text
moonloader/skins/<folder>/
```

A custom entry may refer to `.dff` and `.txd` files. The generated INI includes a `[Skins]` section and an example row; keep that section header when adding entries. The script performs basic file-size checks before attempting to load binary assets. Those checks can reject obviously truncated files, but they do not prove that an asset is structurally valid or compatible.

The configured walk styles use the host's `ped` animation block. No external `ped.ifp` file is required for these built-in walk styles.

## Commands

| Command | Purpose |
|---|---|
| `/zskin` | Open or close the interface |
| `/sskin <playerID> <skinID>` | Set a local visual model override |
| `/sskin0 <playerID>` | Remove a player-ID override |
| `/zskinsave` | Save the current personal model choice |
| `/zskinclear` | Clear the saved personal choice |
| `/zskinname add <nick> <skinID>` | Add a session-only nickname assignment |
| `/zskinname del <nick>` | Remove a nickname assignment |
| `/zskinname list` | List current nickname assignments |
| `/swalk <styleID>` | Apply a walk style to the local character (`0`–`20`) |
| `/swalkp <playerID> <styleID>` | Apply a walk style to a selected participant |
| `/swalk0` | Reset the local walk style |

## Engineering notes

The implementation separates the logical model ID shown and saved in settings from the internal runtime slot used for a custom DFF. Reapplication compares the character's actual runtime model ID with that slot, avoiding repeated reload attempts caused by comparing two different identifiers. Loading is processed through a pending-state path with a timeout rather than relying on an unbounded blocking wait. Binary model and texture files are opened in binary mode before their sizes are checked.

Personal settings and temporary assignments have different lifetimes: personal choices and the hotkey are stored locally, while nickname-based assignments remain in memory for the current session. These overrides are local presentation behavior; they do not modify server-side records or another user's files.

## Requirements and setup

- A compatible MoonLoader scripting host
- SAMPFUNCS and the host functions used by the script
- MoonLoader ImGui (`imgui`)
- The optional `ped.ifp` file and custom model assets when using those features

Copy `model_loader_3d.lua` into the host's MoonLoader scripts directory, start the host, and open the interface with `/zskin`.

## Host API integration status

TXD loading now calls the documented `loadTextureDictionary` name, and walk-style playback uses `requestAnimation("ped")`, `hasAnimationLoaded("ped")`, and `taskPlayAnim`. The script checks for the animation block before applying a style and retries saved style assignments from its periodic loop. These changes are source-level corrections; they still need a smoke test in the target host.

Custom DFF loading remains dependent on a host extension that provides `loadModelInfo`. That function is not defined or imported in this project and is not listed in the [MoonLoader opcode reference](https://github.com/v3sp4n/Lua/blob/master/moonloader_reference.txt). The script now detects its absence and reports that custom DFF loading is unavailable instead of calling a missing global. The extension and its exact API remain to be identified and tested.

The Lua CI check proves that the file parses; it does not prove that host functions or custom model assets work at runtime.

## Limitations

The script depends on host-provided functions for model, texture, animation, and participant operations. Compatibility varies by host build and installed extensions. The source repository does not include a standalone runtime or a test harness capable of validating custom assets against every supported client build. Treat custom asset compatibility as something to verify in the target environment.
