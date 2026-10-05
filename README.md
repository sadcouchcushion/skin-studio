# Skin Studio for Marvel Rivals

## Download

Skin Studio is two downloads, and you need both:

- **[⬇ Skin Studio app 1.0.3 (zip)](https://github.com/sadcouchcushion/skin-studio/releases/download/v1.0.3/SkinStudio-App-1.0.3.zip)**, from this repository · [all releases](https://github.com/sadcouchcushion/skin-studio/releases/latest)
- **The in-game mod** (`!!SkinLive`, for the F8 panel), from Nexus Mods. It is also attached to each release here as `SkinStudio-InGame-<version>.zip`.

To install:

1. Close Marvel Rivals.
2. Install the in-game mod with Vortex, or unzip it into the game's `MarvelGame\Marvel\Content\Paks\~mods` folder (on Steam: right-click Marvel Rivals > Manage > Browse local files; create `~mods` if it isn't there). The three `!!SkinLive_9999999_P` files should sit directly in `~mods`, so they load ahead of other UI mods such as Project Galacta. If Vortex puts them in a subfolder, Skin Studio copies them to the top of `~mods` the next time it opens with the game closed, so open the app once before you play.
3. Unzip the app anywhere outside the game folder and double-click `SkinStudio\Start Skin Studio.bat` once. It installs to `%LOCALAPPDATA%\SkinStudio` and adds Skin Studio to the Start menu.
4. **Open Skin Studio before you launch the game**, then press **F8** in a match for the panel. The panel is drawn by the app, so it only works while the app is running.

Full guide: [docs/NEXUS_GUIDE.md](docs/NEXUS_GUIDE.md).

Skin Studio recolours Marvel Rivals skins on your PC and shows the result on your hero in game. It has two parts:

- **The Skin Studio app** (`SkinStudio.ps1` and the `*lib.ps1` scripts): open a skin, edit its textures and material colours, save designs and build them into mods.
- **The in-game panel** (`!!SkinLive`, press **F8** in game): recolour your hero live while the app is running on the same PC. Its watcher and panel scripts live in `ingame/`.

This repository is the full source of the release published on Nexus Mods. Everything the release runs is plain PowerShell, C# and JavaScript that you can read here. Both release zips (the app and the in-game mod) are built by `nexus/make_nexus_zip.ps1`.

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

Full credits, with authors, links and licence notices: [docs/CREDITS.md](docs/CREDITS.md).

- [three.js](https://threejs.org) (MIT) in `viewer/three/`.
- Black Ops One font (SIL Open Font License, licence in `branding/`).
- WebView2, UAssetAPI, Newtonsoft.Json, ZstdSharp, repak-rivals, retoc and UE4-DDS-Tools ship as unmodified binaries in the release and aren't committed here; BUILDING.md lists where each comes from.

Marvel Rivals is a trademark of its owners. This is an unofficial fan tool and is not affiliated with or endorsed by NetEase or Marvel.
