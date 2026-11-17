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

A `ped.ifp` file is expected at `moonloader/skins/ped.ifp` for the custom walk-style animation path.

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

The implementation separates the logical model ID from the internal model slot used while preparing a custom asset. Loading is processed through a pending-state path with a timeout rather than relying on an unbounded blocking wait. Binary model and texture files are opened in binary mode before their sizes are checked.

Personal settings and temporary assignments have different lifetimes: personal choices and the hotkey are stored locally, while nickname-based assignments remain in memory for the current session. These overrides are local presentation behavior; they do not modify server-side records or another user's files.

## Requirements and setup

- A compatible MoonLoader scripting host
- SAMPFUNCS and the host functions used by the script
- MoonLoader ImGui (`imgui`)
- The optional `ped.ifp` file and custom model assets when using those features

Copy `model_loader_3d.lua` into the host's MoonLoader scripts directory, start the host, and open the interface with `/zskin`.

## Unresolved host API dependencies

The current source calls `loadTxdDictionary`, `loadModelInfo`, and `setCharAnimationFreezeLastFrame`, but does not define or import those names in this project. The [MoonLoader opcode reference](https://github.com/v3sp4n/Lua/blob/master/moonloader_reference.txt) documents `loadTextureDictionary` for loading a TXD dictionary and `taskPlayAnim` for playing a character animation; it does not list the three names currently called by the source. The source also passes an absolute file path to `requestAnimation`, so that argument still needs verification against the target host.

Until these calls are mapped to supported host functions or a declared extension, custom DFF/TXD loading and walk-style application must be treated as unverified. The current Lua CI check proves that the file parses; it does not prove that these global functions exist at runtime.

## Limitations

The script depends on host-provided functions for model, texture, animation, and participant operations. Compatibility varies by host build and installed extensions. The source repository does not include a standalone runtime or a test harness capable of validating custom assets against every supported client build. Treat custom asset compatibility as something to verify in the target environment.
