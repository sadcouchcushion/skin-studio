# Credits

## Skin Studio

**Skin Studio for Marvel Rivals** is made by **Alli / Chicory Design Studio**: the app, the in-game F8 panel (`!!SkinLive`), SkinColorTool, the 3D preview, the Blender bridge, the installer and the Variant / Skin Studio branding.

Source: https://github.com/sadcouchcushion/skin-studio

Marvel Rivals is a trademark of its owners. Skin Studio is an unofficial fan tool and is not affiliated with or endorsed by NetEase, Marvel or Epic Games.

## Included in the download

These files ship unchanged inside the Skin Studio zip. Each stays under its own licence, and their authors own them.

| What | Used for | Author | Licence | Link |
| --- | --- | --- | --- | --- |
| **repak-rivals** (`retoc-rivals-cli` 3.8.0) | Extracting and packing Marvel Rivals `.pak` / `.utoc` / `.ucas` files | natimerry, spuds, Truman Kilen (trumank) | MIT or Apache-2.0 (licence files are in `tools/rrcli/`, which also holds a GPL-3.0 file) | https://www.nexusmods.com/marvelrivals/mods/1717 · https://github.com/natimerry/repak-rivals |
| **retoc** 0.1.5 | Unreal IoStore packing | Truman Kilen (trumank) and Archengius | MIT | https://github.com/trumank/retoc |
| **UE4-DDS-Tools** 0.6.1 | Texture extraction and injection | matyalatte | MIT (licence in `tools/ddstools/src/`) | https://github.com/matyalatte/UE4-DDS-Tools |
| **Texconv-Custom-DLL** (`texconv.dll`, part of UE4-DDS-Tools) | DDS conversion | matyalatte, based on Microsoft's Texconv / DirectXTex | MIT | https://github.com/matyalatte/Texconv-Custom-DLL · https://github.com/microsoft/DirectXTex |
| **Python 3.10.11** embeddable package (part of UE4-DDS-Tools) | Runs UE4-DDS-Tools | Python Software Foundation | PSF License v2 (licence in `tools/ddstools/python/`) | https://www.python.org |
| **UAssetAPI** 1.0.2 | Reading and writing material colours in SkinColorTool | atenfyr | MIT | https://github.com/atenfyr/UAssetAPI |
| **Newtonsoft.Json** | JSON for UAssetAPI | James Newton-King | MIT | https://github.com/JamesNK/Newtonsoft.Json |
| **ZstdSharp** | Zstandard decompression for UAssetAPI | Oleg Stepanischev | MIT | https://github.com/oleg-st/ZstdSharp |
| **Microsoft WebView2 SDK** 1.0.2957.106 | The 3D preview window | Microsoft Corporation | BSD-style (see the notice below) | https://www.nuget.org/packages/Microsoft.Web.WebView2 |
| **three.js** r185 (core, GLTFLoader, OrbitControls, BufferGeometryUtils, SkeletonUtils) | The 3D preview | three.js authors | MIT | https://threejs.org |
| **Black Ops One** font | Skin Studio branding | James Grieshaber and Eben Sorkin (The Black-Ops Project Authors) | SIL Open Font License 1.1 (licence in `branding/`) | https://fonts.google.com/specimen/Black+Ops+One |
| **Oodle** decompressor (`oo2core_9_win64.dll`) | Bundled with repak-rivals to read compressed game files | Epic Games Tools (RAD Game Tools) | Proprietary; shipped as it comes with repak-rivals | https://www.radgametools.com/oodle.htm |
| **Marvel.usmap** | Marvel Rivals type mappings for reading game assets | Generated from the game files and shared by the Marvel Rivals modding community | No licence | — |

## Used, not included

Skin Studio works with these, but they are not in the download. Get them from their authors.

| What | Used for | Author | Licence | Link |
| --- | --- | --- | --- | --- |
| **Unreal Engine 5.3** | Cooking the in-game panel's widget assets | Epic Games | Unreal Engine EULA | https://www.unrealengine.com |
| **Project Galacta** (optional) | Swapping a freshly built mod into the running game (F7) | 0xSaturn | See the mod page | https://www.nexusmods.com/marvelrivals/mods/12806 |
| **Atelier** (optional) | 3D preview meshes and Atelier project round-trips. Skin Studio runs its tools; no Atelier code is copied. | clownfetus | GPL-3.0 | https://github.com/clownfetus/Atelier |
| **CUE4Parse** (inside Atelier and FModel) | Decoding game meshes | FabianFG and contributors | Apache-2.0 | https://github.com/FabianFG/CUE4Parse |
| **FModel** (optional) | Mesh export for the Blender bridge | 4sval and contributors | GPL-3.0 | https://github.com/4sval/FModel |
| **Blender** (optional) | 3D painting | Blender Foundation | GPL | https://www.blender.org |
| **.NET 8 Runtime** | Running SkinColorTool | Microsoft / .NET Foundation | MIT | https://dotnet.microsoft.com |

## Licence notices

**MIT** (retoc, UE4-DDS-Tools, Texconv-Custom-DLL, DirectXTex, UAssetAPI, Newtonsoft.Json, ZstdSharp, three.js, repak-rivals)

> Copyright (c) 2025 Truman Kilen and Archengius (retoc) · Copyright 2024 Truman Kilen, spuds (repak-rivals) · Copyright (c) 2022-2023 matyalatte (UE4-DDS-Tools) · Copyright (c) 2022-2026 matyalatte (Texconv-Custom-DLL) · Copyright (c) Microsoft Corporation (DirectXTex) · Copyright (c) 2020 - 2026 atenfyr (UAssetAPI) · Copyright (c) 2007 James Newton-King (Newtonsoft.Json) · Copyright (c) 2021 Oleg Stepanischev (ZstdSharp) · Copyright 2010-2026 Three.js Authors (three.js)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Microsoft WebView2 SDK**

> Copyright (C) Microsoft Corporation. All rights reserved.
>
> Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
>
> * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
> * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
> * The name of Microsoft Corporation, or the names of its contributors may not be used to endorse or promote products derived from this software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

**Apache-2.0** (repak-rivals, as an alternative to MIT): full text at https://www.apache.org/licenses/LICENSE-2.0 and in `tools/rrcli/LICENSE-APACHE`.

**PSF License v2** (Python 3.10): full text in `tools/ddstools/python/LICENSE.txt`. Copyright (c) 2001-2023 Python Software Foundation; All Rights Reserved.

**SIL Open Font License 1.1** (Black Ops One): Copyright 2022 The Black-Ops Project Authors. Full text in `branding/BlackOpsOne-OFL.txt` and at https://openfontlicense.org.

## Thanks

To the Marvel Rivals modding community, and to everyone whose tools above made Skin Studio possible.
