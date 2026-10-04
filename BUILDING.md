# Building Skin Studio

This explains how every file in the Nexus download (`Skin Studio 1.0.zip`) is made, so anyone can check it. Tag `v1.0` is the source of that release.

## What the download contains

| Part | Where it comes from |
| --- | --- |
| `SkinStudio/app/*.ps1`, `*.cs`, `*.json`, `*.txt`, `*.bat`, `ingame/`, `viewer/*.js`, `viewer/index.html`, `branding/`, `blender/*.py` | Copied as-is from this repository. These are plain-text scripts; nothing is compiled or obfuscated. |
| `SkinStudio/setup.ps1`, `SkinStudio/Start Skin Studio.bat` | `nexus/setup.ps1`, and a one-line launcher written by `nexus/make_nexus_zip.ps1`. |
| `SkinStudio/app/colortool/bin/Release/net8.0/SkinColorTool.exe` / `.dll` | Built from `colortool/Program.cs` (step 2). |
| `SkinStudio/app/tools/`, `viewer/lib/`, the colortool's `UAssetAPI.dll`, `Newtonsoft.Json.dll`, `ZstdSharp.dll`, `blender/Marvel.usmap` | Unmodified third-party files (step 3). |
| `!!SkinLive_9999999_P.pak/.ucas/.utoc` | The in-game F8 panel, cooked from an Unreal Engine 5.3 project (step 4). It contains Unreal widget assets only, no executable code. |

## 1. Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in).
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (only for step 2).
- Git, to clone this repository.

```bat
git clone https://github.com/sadcouchcushion/skin-studio.git
cd skin-studio
git checkout v1.0
```

## 2. Build the colour tool (SkinColorTool)

SkinColorTool is a small console program the app runs to read and write material colours in game assets. It uses UAssetAPI.

1. Create `colortool\lib\` and put these three DLLs in it: `UAssetAPI.dll`, `Newtonsoft.Json.dll`, `ZstdSharp.dll`. The release uses the copies from the `KawaiiPhysicsBinding` folder of repak-rivals 3.5.0 (see step 3). UAssetAPI is open source at https://github.com/atenfyr/UAssetAPI.
2. Build:

   ```bat
   cd colortool
   dotnet build -c Release
   ```

3. The output is in `colortool\bin\Release\net8.0\`. Run `SkinColorTool.exe` with no arguments and it prints its usage (`dump` and `patch`).

To use DLLs from another folder, pass `-p:LibDir=C:\path\to\dlls\`.

## 3. Third-party tools bundled in the download

These are shipped unchanged from their authors' releases. Skin Studio only runs them as command-line tools.

| Path in the zip | What it is | Source / licence |
| --- | --- | --- |
| `tools/rrcli/retoc-rivals-cli.exe`, `tools/rrcli/oo2core_9_win64.dll` | repak-rivals CLI 3.8.0: extracts and packs Marvel Rivals `.pak`/`.utoc`/`.ucas` | Nexus Mods, Marvel Rivals mod 1717 (MIT / Apache / GPL, licence files included with it). `oo2core_9_win64.dll` is the Oodle decompressor that tool ships with. |
| `tools/retoc.exe` | retoc 0.1.5: Unreal IoStore packer | https://github.com/trumank/retoc |
| `tools/ddstools/` | UE4-DDS-Tools 0.6.1 with its embedded Python 3.10 and `texconv.dll` | https://github.com/matyalatte/UE4-DDS-Tools (MIT) |
| `viewer/lib/Microsoft.Web.WebView2.*.dll`, `WebView2Loader.dll` | Microsoft WebView2 SDK 1.0.2957.106, for the 3D preview window | NuGet package `Microsoft.Web.WebView2` |
| `colortool/.../UAssetAPI.dll`, `Newtonsoft.Json.dll`, `ZstdSharp.dll` | UAssetAPI 1.0.2 and its dependencies | https://github.com/atenfyr/UAssetAPI (MIT) |
| `blender/Marvel.usmap` | Marvel Rivals type mappings used to read game assets | Generated from the game; commonly shared by the Rivals modding community |

`make_nexus_zip.ps1` copies these from a `tools` folder next to the app (or `C:\rs\tools`). Lay it out as `tools\rrcli\`, `tools\ddstools\` and `tools\retoc.exe`.

## 4. The in-game panel (`!!SkinLive`)

The panel is two Unreal widget assets cooked with Unreal Engine 5.3 and packed with repak-rivals. `ingame/build_live_mod.ps1` does the packing and documents each step:

1. Cook the `WBP_SkinLivePreviewBootstrap01` and `WBP_SkinLiveEditor` widgets from the Unreal project.
2. Copy the game's own `WBP_UIDPanel` asset and change one name-table string so it opens our widget (an equal-length byte swap, explained in `INGAME_MENU.md`, "route B").
3. Patch the cooked widgets' function calls to the game's HUD and file classes (`ingame/patch_hud_calls.ps1`, `ingame/patch_live_calls.ps1`).
4. Pack the result into `!!SkinLive_9999999_P.pak/.ucas/.utoc` with `retoc-rivals-cli`.

The pak holds Unreal Blueprint widget data only. It has no DLLs, scripts or native code, and it talks to the app only through files on disk.

Skin Studio makes no network connections. The only URL in the scripts, `https://skinstudio.local/`, is a WebView2 virtual host that maps to the local `viewer/` folder.

## 5. Package the release zip

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File nexus\make_nexus_zip.ps1 -Version 1.0
```

This stages everything under `work\_nexus\stage` and writes `Skin Studio 1.0.zip` to your Downloads folder. It refuses to build if any `.pak`/`.utoc`/`.ucas` ends up inside the `SkinStudio\` folder, so the game can't mount app files by accident.

## 6. Checking a download

To check that a downloaded file matches the release, run `Get-FileHash <file>` in PowerShell and compare it with this table (SHA-256, Skin Studio 1.0):

| File in the zip | SHA-256 |
| --- | --- |
| `!!SkinLive_9999999_P.pak` | `5ae1ed86deb66c2d7feaa38219554977f7fb554f639dc43c80bbc3672443f9e9` |
| `!!SkinLive_9999999_P.ucas` | `20d2698c06c96af777881da70522dfb83486cc7cdd032f1eb6bb18b1599c30ce` |
| `!!SkinLive_9999999_P.utoc` | `da9c93b48538e930f61066301f4ec446a0cc1e06ce623883c1ba0940451a526b` |
| `SkinStudio/app/blender/Marvel.usmap` | `03ff1bb43236d1a38351cba0e4232e25309444de7dd33e7a30a47ed45747e285` |
| `SkinStudio/app/colortool/bin/Release/net8.0/SkinColorTool.exe` | `f2129fdb4ef132ce60b3ddb63808e3cbd62a56a7630d1384c6abee95303e6306` |
| `SkinStudio/app/colortool/bin/Release/net8.0/SkinColorTool.dll` | `39e73a0f66d14dcd7278356e85e025e14bb4ee17766f864bce2617b553ee4288` |
| `SkinStudio/app/colortool/bin/Release/net8.0/UAssetAPI.dll` | `57d9e0deea6e8fb1cf368cc9f70fbd7ef10d007e5b9931aa83e5db138ada0817` |
| `SkinStudio/app/colortool/bin/Release/net8.0/Newtonsoft.Json.dll` | `22c649f75fce5be7c7ccda8880473b634ef69ecf33f5d1ab8ad892caf47d5a07` |
| `SkinStudio/app/colortool/bin/Release/net8.0/ZstdSharp.dll` | `5d597fb07c93f99bcbbcf1265bfc60de1f1f8fc070a3acc36f0371a86c326b16` |
| `SkinStudio/app/tools/retoc.exe` | `a145f3557ec60b163ed1b78b2f380232d2753fa30350c8013c98e171db3ae7e7` |
| `SkinStudio/app/tools/rrcli/retoc-rivals-cli.exe` | `1193b5ee81d755ca2a98b7d75e3d6cbda83daf071298c03c3c73b6a3632cf2d8` |
| `SkinStudio/app/tools/rrcli/oo2core_9_win64.dll` | `6f5d41a7892ea6b2db420f2458dad2f84a63901c9a93ce9497337b16c195f457` |
| `SkinStudio/app/tools/ddstools/python/python.exe` | `3cce33d75d6fdae4e004d0bdf149320b3147482a9caf370079dcb9c191a1b260` |
| `SkinStudio/app/tools/ddstools/python/python310.dll` | `14b06796f288bc6599e458fb23a944ab0c843e9868058f02a91d4606533505ed` |
| `SkinStudio/app/tools/ddstools/python/libffi-7.dll` | `f60dd9f2fcbd495674dfc1555effb710eb081fc7d4cae5fa58c438ab50405081` |
| `SkinStudio/app/tools/ddstools/python/vcruntime140.dll` | `9d2b40f0395cc5d1b4d5ea17b84970c29971d448c37104676db577586d4ad1b1` |
| `SkinStudio/app/tools/ddstools/python/vcruntime140_1.dll` | `34048abaa070ecc13b318cea31425f4ca3edd133d350318ac65259e6058c8b32` |
| `SkinStudio/app/tools/ddstools/src/directx/texconv.dll` | `2c03bd77867c53b55f37363124148dd4037824ff7280c493fd399687012a8c63` |
| `SkinStudio/app/viewer/lib/Microsoft.Web.WebView2.Core.dll` | `cb8c852fcc4ef55d630b64d171dc11538bb25258041ed22cf31735982a2e09e3` |
| `SkinStudio/app/viewer/lib/Microsoft.Web.WebView2.WinForms.dll` | `e62056bee28ab094071144b47371009a6fbc162f9aea184719f2e86ed515f7f8` |
| `SkinStudio/app/viewer/lib/WebView2Loader.dll` | `271b57e3ec03c436a15d80cafeb9fd1618a43793233d8b05c9446f8de0a51be4` |

A rebuilt `SkinColorTool.exe`/`.dll` can differ in a few bytes from the shipped one (compilers embed a build ID), but it behaves the same. Every other file above is copied, not built, so its hash should match exactly.
