# Antivirus false positives

Skin Studio is plain PowerShell, C# and JavaScript plus a few open-source modding tools. Some antivirus engines still flag it, because it has the shape that their generic rules look for. This page lists what can trip a scanner, what the release does about it, and how to report a false positive.

## What can trip a scanner

| What | Why scanners notice it | What the release does |
| --- | --- | --- |
| `powershell -ExecutionPolicy Bypass` in a `.bat` | Common in malware droppers. | Only `Start Skin Studio.bat` uses it, in a visible window that says what it is doing, because `setup.ps1` is still marked as downloaded when it runs. Setup clears that mark on the installed copy only, and every other script the app starts runs as `RemoteSigned` (since 1.0.3). |
| Background PowerShell with no window | Same reason. | The in-game helper and the live-preview watcher run without a window so they don't take focus from the game. They write logs to `%LOCALAPPDATA%\SkinStudio\work\ingame`, end when the game closes, and are started only by the app. Nothing is added to Windows sign-in, the registry Run keys or Task Scheduler. |
| `Add-Type` compiling C# at run time | Used by some script malware. | The C# is the readable `SkinArt.cs`, `ingame/SkinPanel.cs` and `viewer/ViewArt.cs` in this repository (image and window code). |
| Unsigned `.exe` files | Unsigned programs with few downloads get "generic" or machine-learning detections (names like `Wacatac`, `Generic.ML`, `Malicious (score…)`). | `retoc.exe` and `retoc-rivals-cli.exe` are open-source Rust tools, copied unchanged (see BUILDING.md for sources and hashes). `SkinColorTool.exe` is built from `colortool/` and, since 1.0.3, carries product, company, version and icon details. |
| `oo2core_9_win64.dll` | The Oodle decompressor that Unreal games ship; rarely seen outside games. | Unchanged, needed to read the game's files. |
| A zip inside the zip (`python310.zip`, the embedded Python's standard library) | Nexus quarantines nested archives automatically. | Since 1.0.3 it ships unpacked as `tools/ddstools/python/Lib`, and the build refuses to make a download with an archive inside. |
| Extra `.bat`, `.url` and `.pyc` files from ddstools | Script and shortcut files inside archives raise heuristic scores. | Left out of the download since 1.0.3; the app runs ddstools' `main.py` directly. |

`SkinStudio/SHA256SUMS.txt` in the app zip has the hash of every file, so a detection can be matched to one file.

## Reporting a false positive

Report the specific file a scanner names, not the whole zip, when the scanner says which file it is.

1. **Microsoft Defender**: https://www.microsoft.com/wdsi/filesubmission. Sign in, choose *Software developer*, product *Microsoft Defender Antivirus (Windows 10/11)*, upload the file (or the zip), pick *Incorrectly detected as malware/malicious*, and put the detection name in the box. Say it is an open-source Marvel Rivals modding tool and link the GitHub repository. Answers usually come within a few days, and Defender's definitions are updated if they agree.
2. **Other engines on VirusTotal**: open the file's VirusTotal page, note which engines flag it, and use each vendor's false-positive form. VirusTotal keeps the list of vendor contacts at https://docs.virustotal.com/docs/false-positive-contacts. Avast and AVG share one form: https://www.avast.com/false-positive-file-form.php.
3. **Nexus Mods**: reply to the moderation message with the VirusTotal links, the GitHub repository, BUILDING.md (how each file is built and where the tools come from) and `SHA256SUMS.txt`.
4. **Players**: point them at this page. Ask them not to turn off their antivirus; if Defender quarantined a file, they can restore it from Windows Security > Protection history once they are happy it is a false positive.

Code signing (an Authenticode certificate) is the one change that makes these detections much rarer, because reputation then follows the publisher instead of each new file. It costs money each year and is not done yet.
