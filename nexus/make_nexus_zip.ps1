# make_nexus_zip.ps1 - builds the two release downloads:
#
#   SkinStudio-InGame-<ver>.zip   for Nexus Mods / Vortex: only the in-game
#                                 mod, unzipped straight into ~mods
#       !!SkinLive_9999999_P.pak/.ucas/.utoc   the F8 panel (from ~mods now)
#
#   SkinStudio-App-<ver>.zip      for the GitHub release: the app, unzipped
#                                 anywhere outside the game folder
#       SkinStudio\Start Skin Studio.bat       runs setup.ps1
#       SkinStudio\setup.ps1                   installs app\ to %LOCALAPPDATA%\SkinStudio
#       SkinStudio\app\                        the app + its tools (no cache, designs or builds)
#
#   powershell -File nexus\make_nexus_zip.ps1 -Version 1.0.1
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$Out = (Join-Path $env:USERPROFILE 'Downloads')
)
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'skinlib.ps1')
$work  = Join-Path $root 'work\_nexus'
$modStage = Join-Path $work 'ingame'
$appStage = Join-Path $work 'app'
foreach ($d in $modStage, $appStage, (Join-Path $work 'stage')) {
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
}
$app = Join-Path $appStage 'SkinStudio\app'
New-Item -ItemType Directory -Force -Path $app, $modStage | Out-Null

function Copy-Tree([string]$from, [string]$to, [string[]]$xf = @(), [string[]]$xd = @()) {
    $a = @($from, $to, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XF', '*.bak*', '*.pdb') + $xf
    if ($xd.Count) { $a += @('/XD') + $xd }
    & robocopy.exe @a | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy $from failed ($LASTEXITCODE)" }
}

function Write-Zip([string]$stage, [string]$zip) {
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    # entries written by hand: .NET Framework's CreateFromDirectory stores '\' in
    # entry names, which some unzippers (and mod managers) turn into flat file names
    $za = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath $stage -Recurse -File)) {
            $name = $f.FullName.Substring($stage.Length + 1).Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $name, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $za.Dispose() }
    '{0}  ({1:N1} MB)' -f $zip, ((Get-Item -LiteralPath $zip).Length / 1MB)
}

# --- app download ---
# app code: top-level scripts and data files
$top = @(Get-ChildItem -LiteralPath $root -File | Where-Object {
    $_.Name -notlike '*.bak*' -and $_.Extension -in '.ps1', '.cs', '.json', '.txt', '.bat' -and
    $_.Name -notin 'build-vuistyle.ps1', 'Try In-Game Panel.bat', 'game_paks.txt' })
foreach ($f in $top) { Copy-Item -LiteralPath $f.FullName -Destination $app }
Copy-Tree (Join-Path $root 'ingame')   (Join-Path $app 'ingame')
Copy-Tree (Join-Path $root 'viewer')   (Join-Path $app 'viewer')
Copy-Tree (Join-Path $root 'branding') (Join-Path $app 'branding') @('build-branding.ps1')
Copy-Tree (Join-Path $root 'colortool\bin\Release\net8.0') (Join-Path $app 'colortool\bin\Release\net8.0')
New-Item -ItemType Directory -Force -Path (Join-Path $app 'blender') | Out-Null
foreach ($f in 'Marvel.usmap', 'bridge.py', 'paintid.py', 'fix_fmodel_settings.ps1') { Copy-Item -LiteralPath (Join-Path $root "blender\$f") -Destination (Join-Path $app 'blender') }
# tools: the packer/extractors the app runs (from C:\rs\tools on this PC)
Copy-Tree (Join-Path $SS_Tools 'rrcli')    (Join-Path $app 'tools\rrcli')
Copy-Tree (Join-Path $SS_Tools 'ddstools') (Join-Path $app 'tools\ddstools')
Copy-Item -LiteralPath (Join-Path $SS_Tools 'retoc.exe') -Destination (Join-Path $app 'tools')
Set-Content -LiteralPath (Join-Path $app 'VERSION.txt') -Value $Version -Encoding ASCII

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'setup.ps1') -Destination (Join-Path $appStage 'SkinStudio')
[IO.File]::WriteAllText((Join-Path $appStage 'SkinStudio\Start Skin Studio.bat'),
    "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0setup.ps1`"`r`n")

# the app download must hold nothing mountable, in case someone unzips it into ~mods
$bad = @(Get-ChildItem -LiteralPath $appStage -Recurse -File | Where-Object { $_.Extension -in '.pak', '.utoc', '.ucas' })
if ($bad.Count) { throw ("mountable files in the app download: " + ($bad.FullName -join ', ')) }

# --- in-game mod download: the three files at the zip root, exactly as installed now ---
$mods = Join-Path $SS_Paks '~mods'
foreach ($ext in 'pak', 'ucas', 'utoc') {
    Copy-Item -LiteralPath (Join-Path $mods "!!SkinLive_9999999_P.$ext") -Destination $modStage
}

Write-Zip $modStage (Join-Path $Out ("SkinStudio-InGame-{0}.zip" -f $Version))
Write-Zip $appStage (Join-Path $Out ("SkinStudio-App-{0}.zip" -f $Version))
