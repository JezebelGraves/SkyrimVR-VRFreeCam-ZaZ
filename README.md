# SkyrimVR-VRFreeCam-ZaZ (ZaZ VR Lock)

> **18+ only.** This patch targets ZaZ Animation Pack, an adult furniture/restraint
> framework distributed on LoversLab. This repository holds only camera and VRIK logic;
> no ZaZ files are included.

A **Skyrim VR** player-only patch for **ZaZ Animation Pack 8** furniture. When the player
sits in a ZaZ furniture piece, the body is pinned on the piece with VRIK and the camera is
held in third person on a viewpoint around the posed body. The headset is decoupled from
the body, the way SexLab VR's third-person mode and OStim VR's VRIK pinning work.
**It does not use `SetVehicle` or `tfc` on the player**, because in Skyrim VR those spin
the camera or crash the game.

NPCs are not touched; ZaZ keeps handling them as usual.

## What it does
- Detects when the player sits in a ZaZ furniture piece (through the `OnSit` event of a
  player alias).
- Stands the player up, plays the furniture's own Enter animation on the spot, then replays
  the loop pose with a keep-alive so the pose holds.
- Pins the VRIK body on the piece (`lockPosition=2`) and turns off the VRIK arms and the
  HIGGS hands while locked.
- Holds the third-person camera on a viewpoint. The "next view" command moves it front,
  right, back, then left. An optional walk-cam mode lets the stick move the camera, but
  moving drops the pose until you stop.
- Releases in a set order and then checks the result: camera, VRIK, HIGGS hands and
  controls are restored.
- Optional rescue: a nearby friendly NPC walks over and releases you. There is also a timer
  global for it.
- Per-furniture calibration (`x812zl.Nudge`), saved to
  `SKSE/Plugins/StorageUtilData/x812zl/calibration.json`.
- Ships a furniture table at `SKSE/Plugins/StorageUtilData/x812zl/furniture.json`. It maps
  ZaZ furniture to its Enter/loop animation events.
- Public API for other mods: global functions on script `x812zl` (`Release`, `IsLocked`,
  `GetMode`, `GetFurniture`, `RequestRescue`, `Panic`, `NextView`, `SetWalkCam`,
  `TryPose`, `KeepPose`, `Nudge`, `Ext*` holds for framework adapters). You can also use
  ModEvents: `x812zl_Release` and `x812zl_RequestRescue` go in, and `x812zl_Locked`,
  `x812zl_Released`, `x812zl_RescueStarted` and `x812zl_RescueFailed` come out.
- Includes `VRFreeCam`, the shared VR free-camera helper script that ZaZ VR Lock calls
  (`LockAt`, `UnlockInPlace`, `Repin`, `IsPinned`, `PanicReset`, ...).

### Console
```
cgf "x812zl.Panic"             ; force-restore everything (camera, VRIK, HIGGS, controls)
cgf "x812zl.Release" "test"    ; normal release
cgf "x812zl.NextView"          ; camera to the next side of the furniture
cgf "x812zl.Nudge" 0 0 0 180   ; calibrate the pin (x right, y forward, z up, yaw degrees)
cgf "VRFreeCam.PanicReset"     ; drop every VRFreeCam pin/lock/override
```

## Important limitation: furniture that a mod puts you in
Furniture you **enter yourself** is caught through `OnSit` and works with stock ZaZ.

Furniture that **a mod or NPC forces you into** goes through ZaZ's own `zbfSlot` script.
Stock ZaZ calls `SetVehicle` on the player there, which is the thing that misbehaves in VR.
The hook `x812zl_Hook` is written so that a modified `zbfSlot` can send those calls to it
(five call sites). **That modified `zbfSlot` is ZaZ's file and is not included here.**
Without it:
- this patch still loads, handles furniture you enter yourself, and offers its API;
- ZaZ does not hand mod-forced seating to it, and stock ZaZ behaviour applies there.

## Requirements
- **Skyrim VR** with **SKSEVR**: https://skse.silverlock.org/
- **ZaZ Animation Pack 8 / 8+ for SE** (LoversLab, 18+):
  https://www.loverslab.com/files/file/5957-zaz-animation-packs-for-se/
- **VRIK Player Avatar** (its Papyrus API is used heavily):
  https://www.nexusmods.com/skyrimspecialedition/mods/23416
- **PapyrusUtil** (VR build; StorageUtil/JsonUtil):
  https://www.nexusmods.com/skyrimspecialedition/mods/13048
- **HIGGS** (hands are blocked while locked):
  https://www.nexusmods.com/skyrimspecialedition/mods/43930
- **Skyrim VR ESL Support**, because `ZazVRLock.esp` is flagged as a light plugin (ESL):
  https://www.nexusmods.com/skyrimspecialedition/mods/106712
- `VRFreeCam.pex` is **included** in this mod. No separate download is needed.

### Building the scripts yourself (optional)
The compiled `.pex` files are included. To recompile `Scripts/Source/*.psc` you need the
Papyrus sources of the base game, SKSEVR, PapyrusUtil, VRIK, HIGGS and **ZaZ Animation
Pack** (the scripts reference the ZaZ types `zbfBondageShell`, `zbfSlot`,
`xPlayFurnitureOpenClose`, `xRandomFurnitureIdle` and `wncRapingMachineScript`). Those headers are
other authors' work and are not shipped here; get them from the mods listed above.

## Install (Mod Organizer 2)
1. Get out of any furniture first, and keep a save from before installing.
2. Download `SkyrimVR-VRFreeCam-ZaZ.zip` from the
   [v1.0 release](https://github.com/JezebelGraves/SkyrimVR-VRFreeCam-ZaZ/releases/tag/v1.0).
3. In MO2, click **Install a new mod from an archive** and pick the zip. Its contents are
   already in Data layout (`ZazVRLock.esp`, `Scripts/`, `SKSE/`).
4. Place the mod **below** (so it wins over) ZaZ Animation Pack and any other VRFreeCam
   patch.
5. Enable `ZazVRLock.esp` in the plugin list.
6. Disable any older ZaZ VR camera patch that ships the same `x812zl*` scripts.
7. Fully restart the game.

`VRFreeCam.pex` is meant to be byte-identical across VRFreeCam patches, so an MO2
conflict on that one file is expected.

## Uninstall
1. Get out of the furniture, or run `cgf "x812zl.Panic"`, then save.
2. Disable or remove the mod in MO2.
3. Optionally delete `SKSE/Plugins/StorageUtilData/x812zl/calibration.json` from your
   overwrite or mod folder, if one was created.
4. As with any scripted mod, removing it mid-playthrough can leave stale script data in the
   save. Use a save from before install if you can.

## Known limitations and what is untested
- **Player only.** NPC handling is left to ZaZ.
- Mod-forced seating needs a modified `zbfSlot`, which is not included (see above).
- Developed and used on one VR setup only and **not broadly tested**. No testing has been
  done with other headsets, other VRIK versions or large modlists.
- This public build renames the plugin to `ZazVRLock.esp`. The compiled scripts were
  updated to look it up under that name by editing their string tables, not by
  recompiling. That edit is checked byte-for-byte, but **this exact build has not been
  run in-game yet**. Please report problems on the issue tracker.
- A save made with a differently named private build of this plugin will not carry its
  state over. Release first, then switch.
- Some functions refer to companion features from other patches (for example an
  `x812sq.DommeLock` StorageUtil key and the `Ext*` adapter API). They do nothing unless
  another mod uses them.

## Credits
- Method follows SexLab VR's third-person mode and OStim VR's VRIK pinning.
- ZaZ Animation Pack by its authors (SE port by pfiffy). VRIK by prog. HIGGS by
  FlyingParticle. PapyrusUtil by its authors. Skyrim VR ESL Support by Nightfallstorm and
  alandtse. All credit for those mods goes to their authors.
- Written with help from AI assistants.

## License
MIT for the files in this repository. See [LICENSE](LICENSE).
