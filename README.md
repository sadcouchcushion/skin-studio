# Skin Studio for Marvel Rivals

Skin Studio recolours Marvel Rivals skins on your PC and shows the result on your hero in game. It has two parts:

- **The Skin Studio app** (`SkinStudio.ps1` and the `*lib.ps1` scripts): open a skin, edit its textures and material colours, save designs and build them into mods.
- **The in-game panel** (`!!SkinLive`, press **F8** in game): recolour your hero live while the app is running on the same PC. Its watcher and panel scripts live in `ingame/`.

This repository is the full source of the release published on Nexus Mods. Everything the release runs is plain PowerShell, C# and JavaScript that you can read here. The release zip is built by `nexus/make_nexus_zip.ps1`.

## Layout

| Folder | What it holds |
| --- | --- |
| root | The app (`SkinStudio.ps1`), shared libraries, build scripts and notes |
| `ingame/` | The F8 panel server, watcher and live-mod build scripts |
| `standalone/` | The no-app material-colour mod (experimental) |
| `colortool/` | `SkinColorTool`, a small .NET 8 tool that edits material colours with UAssetAPI |
| `viewer/` | The 3D preview (three.js in WebView2) |
| `blender/` | Optional Blender bridge for 3D painting |
| `designs/` | Example designs (colour recipes) |
| `nexus/` | Installer and release packaging |
| `docs/` | Install and usage guide (`docs/NEXUS_GUIDE.md`) |

## Building

See [BUILDING.md](BUILDING.md) for the full step-by-step build, the third-party tools in the download and SHA-256 hashes for every binary.

- `colortool/`: `dotnet build -c Release` (needs the .NET 8 SDK and the three DLLs listed in BUILDING.md in `colortool/lib/`).
- The `!!SkinLive` pak is cooked from an Unreal Engine 5.3 project that isn't in this repository; `ingame/build_live_mod.ps1` shows the steps.
- Game files, paks, extracted textures and build output are deliberately not committed.

## Third-party pieces

- [three.js](https://threejs.org) (MIT) in `viewer/three/`.
- Black Ops One font (SIL Open Font License, licence in `branding/`).
- WebView2, UAssetAPI, Newtonsoft.Json, ZstdSharp, repak-rivals, retoc and UE4-DDS-Tools ship as unmodified binaries in the release and aren't committed here; BUILDING.md lists where each comes from.

Marvel Rivals is a trademark of its owners. This is an unofficial fan tool and is not affiliated with or endorsed by NetEase or Marvel.
