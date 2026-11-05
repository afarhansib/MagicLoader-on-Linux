# MagicLoader on Linux (Bedrock on Linux)

Run MagicLoader's Java shader packs (Photon, BSL, IterationT, ...) and its built-in MagicRT
in Minecraft Bedrock on Linux, using the [Bedrock on Linux](https://github.com/Wyze3306/BedrockOnLinux) (BOL) launcher.
Once set up it behaves the same as on Windows, including the in-game overlay, and other DLLs
injected through BOL's "Inject DLL" keep working beside it.

Tested with Minecraft 1.26.60.5 (Windows package 1.26.6005.0), BOL's GDK-Proton-xuser engine,
and an NVIDIA RTX 3060.

## What you need

- A working BOL install that can already play the game.
- The MagicLoader install folder from Windows (`%LOCALAPPDATA%\Programs\MagicLoader`).
- `d3dcompiler_47.dll` from a Windows install (`C:\Windows\System32\D3DCompiler_47.dll`).

Below, `BOL` is BOL's data folder: `~/.local/share/bedrock-on-linux` by default, or the
location you picked in BOL (`~/.config/bedrock-on-linux/install_location`).

## 1. Copy MagicLoader into the Wine prefix

Copy the whole MagicLoader folder to:

```
BOL/compatdata/pfx/drive_c/users/steamuser/AppData/Local/Programs/MagicLoader/
```

You don't need to run `MagicLoader.exe`. On Linux the script below injects `magic_windows.dll` for you.

## 2. Use Microsoft's shader compiler

Wine's built-in `d3dcompiler_47.dll` can't compile MagicLoader's shaders. Errors like
`W5300 implicit truncation`, `isnan not defined`, `Unknown modifier "resolve"`,
`the terrain program could not be translated`, or a crash when you press Reload all come from it.

1. Copy Windows' `D3DCompiler_47.dll` into the game folder (the one with `Minecraft.Windows.exe`,
   e.g. `BOL/games/release/<version>/`) and name it `d3dcompiler_47.dll`.
   Wine's own copy in the prefix stays untouched, so you can undo this by deleting the file.
2. In BOL, open **Settings → Custom environment** and add:

   ```
   WINEDLLOVERRIDES=cryptbase=n,b;vrclient=;vrclient_x64=;openvr_api=;wineopenxr=;amd_ags_x64=;d3dcompiler_47=n,b
   ```

   A custom `WINEDLLOVERRIDES` **replaces** BOL's default value, so keep BOL's own entries
   (everything before `d3dcompiler_47=n,b`) in the line.

If you change game versions in BOL, copy the DLL into the new game folder too.

## 3. Turn off anti-aliasing

In Minecraft: **Settings → Video → Anti-Aliasing → 1**.

With anti-aliasing on, MagicLoader can't find the point where the game finishes the world and starts
drawing the hand and HUD. Java packs then wait forever (`waiting for the game's world end`), and
MagicRT draws over the HUD, leaving solid blocks invisible.

## 4. Inject at game start

On Windows, MagicLoader starts the game and injects itself right away. BOL's auto-inject waits for
the main menu, which is too late: the game has already created the camera buffers and block atlas,
so nothing gets shaded and the log keeps saying `camera: searching...` and `atlas NOT found`.

`magic-early-inject.sh` injects about a second after the game process appears:

1. In BOL, turn **auto-inject off** for `magic_windows.dll`. Other DLLs can stay.
2. If you have never used BOL's "Inject DLL", run it once so BOL unpacks `cache/injector.exe`.
3. Every time you play:

   ```bash
   ./magic-early-inject.sh
   ```

   Press **PLAY** in BOL while it says `Waiting for Minecraft to start`.

4. In a world, open the MagicLoader overlay and pick a pack.

The script finds BOL's folders the way BOL does. Override them with `BOL_HOME`, `BOL_PREFIX`,
`BOL_ENGINE`, or `MAGIC_DLL` if yours differ. It writes to `BOL/logs/early-inject.log`.

## Troubleshooting

MagicLoader's log is at
`BOL/compatdata/pfx/drive_c/users/steamuser/AppData/Local/Temp/magicloader_windows_probe.log`.

| Log says | Fix |
| --- | --- |
| compile errors / crash on Reload | Step 2 (the DLL is missing, or the override isn't set) |
| `camera: searching...`, `atlas NOT found` | Step 4 (it was injected too late) |
| `waiting for the game's world end`, `0 at the world end` | Step 3 (anti-aliasing is on) |
| BOL: "Wine/Proton process(es) still use this prefix" | Use **Force stop Minecraft** in BOL, then PLAY again |
| `game: package version unknown` | Normal under BOL, safe to ignore |
