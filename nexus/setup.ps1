# setup.ps1 - runs from the unzipped app download (SkinStudio-App-<ver>.zip).
# Copies the app (app\) to %LOCALAPPDATA%\SkinStudio, tells it where the game
# is, makes a Start menu shortcut and starts Skin Studio. The app's cache,
# work files and built paks then live in AppData: anything with a .pak/.utoc
# inside ~mods gets mounted by the game, so the app must not run from there.
# Re-running it after a new download updates the app and keeps designs/cache.
param([switch]$NoLaunch)
$ErrorActionPreference = 'Stop'

function Say([string]$m) { Write-Host $m }

$src = Join-Path $PSScriptRoot 'app'
$dst = Join-Path $env:LOCALAPPDATA 'SkinStudio'
if (-not (Test-Path -LiteralPath (Join-Path $src 'SkinStudio.ps1'))) { throw "app folder missing next to setup.ps1 ($src)" }

# the Paks folder = the parent of the ~mods folder this download sits in
# (Vortex may nest it one folder deeper, so walk up)
$paks = $null
$d = Get-Item -LiteralPath $PSScriptRoot
while ($d) {
    if ($d.Name -ieq '~mods') { $paks = $d.Parent.FullName; break }
    $d = $d.Parent
}
if ($paks -and -not (Test-Path -LiteralPath (Join-Path $paks 'pakchunkCharacter-Windows.utoc'))) { $paks = $null }

$newVer = (Get-Content -LiteralPath (Join-Path $src 'VERSION.txt') -Raw).Trim()
$oldVer = if (Test-Path -LiteralPath (Join-Path $dst 'VERSION.txt')) { (Get-Content -LiteralPath (Join-Path $dst 'VERSION.txt') -Raw).Trim() } else { '' }

if ($newVer -ne $oldVer) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like ('*' + $dst + '*') })
    # the in-game helper (ingame\helper.ps1, no window) stays up after the app
    # closes; with the game closed it is only waiting, so stop it and say so
    $gameUp = [bool](Get-Process -Name 'Marvel-Win64-Shipping', 'MarvelRivals' -ErrorAction SilentlyContinue)
    $helpers = @($running | Where-Object { $_.CommandLine -like '*\ingame\helper.ps1*' })
    if ($helpers.Count -and -not $gameUp) {
        foreach ($h in $helpers) { Stop-Process -Id $h.ProcessId -Force -ErrorAction SilentlyContinue }
        Say ('Stopped the Skin Studio in-game helper from the old install ({0} process).' -f $helpers.Count)
        $running = @($running | Where-Object { $_.CommandLine -notlike '*\ingame\helper.ps1*' })
    }
    if ($running.Count) {
        Say 'Skin Studio (or its in-game helper) is running from the old install:'
        foreach ($r in $running) { Say ('  process {0}: {1}' -f $r.ProcessId, $r.CommandLine) }
        Say 'Close Skin Studio and Marvel Rivals, then run Start Skin Studio again.'
        exit 1
    }
    Say ("Installing Skin Studio {0} to {1} ..." -f $newVer, $dst)
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    # /E copies everything in app\; files the app made later (designs, cache,
    # work, output) are not in app\ and are left alone
    & robocopy.exe $src $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copy failed (robocopy exit $LASTEXITCODE)" }
    # files older versions installed that the app no longer ships (Unreal build
    # tools, ddstools front-ends, the zipped Python library): /E leaves them, so
    # remove them by name
    $retired = @('build_live_mod.ps1', 'check_paste.ps1', 'compare_class.ps1', 'gen_graphs.ps1', 'panel_sim.ps1',
            'paste_probe.ps1', 'patch_hud_calls.ps1', 'patch_live_calls.ps1', 'ue_drive.ps1', 'zenparse.ps1' | ForEach-Object { "ingame\$_" }) +
        @('_0_check_version.bat', '_1_export_as_tga.bat', '_2_set_asset_path.bat', '_3_inject.bat', '_copy.bat', '_parse.bat', 'README.url', 'python\python310.zip' |
            ForEach-Object { "tools\ddstools\$_" })
    foreach ($r in $retired) {
        $p = Join-Path $dst $r
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
    foreach ($sub in 'designs', 'images', 'output', 'work', 'cache') { New-Item -ItemType Directory -Force -Path (Join-Path $dst $sub) | Out-Null }
}

# Files unzipped from a download carry Windows' "came from the internet" mark,
# and the app starts its own scripts with -ExecutionPolicy RemoteSigned, which
# refuses marked scripts. Clear the mark on the installed copy only (what this
# script just put in %LOCALAPPDATA%\SkinStudio), so the app never needs Bypass.
Get-ChildItem -LiteralPath $dst -Recurse -File -Include *.ps1, *.bat, *.cs, *.exe, *.dll, *.pyd |
    Unblock-File -ErrorAction SilentlyContinue

if ($paks) {
    [IO.File]::WriteAllText((Join-Path $dst 'game_paks.txt'), $paks)
    Say ("Game found: {0}" -f $paks)
} elseif (-not (Test-Path -LiteralPath (Join-Path $dst 'game_paks.txt'))) {
    Say 'Skin Studio will find Marvel Rivals in your Steam or Epic library when it opens.'
}

$lnkDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$lnk = Join-Path $lnkDir 'Skin Studio.lnk'
if (-not (Test-Path -LiteralPath $lnk)) {
    try {
        New-Item -ItemType Directory -Force -Path $lnkDir | Out-Null
        $ws = New-Object -ComObject WScript.Shell
        $s = $ws.CreateShortcut($lnk)
        $s.TargetPath = Join-Path $dst 'Run Skin Studio.bat'
        $s.WorkingDirectory = $dst
        $s.IconLocation = Join-Path $dst 'branding\skin-studio.ico'
        $s.WindowStyle = 7
        $s.Save()
        Say 'Added "Skin Studio" to the Start menu.'
    } catch { Say ('Could not add a Start menu shortcut: ' + $_.Exception.Message) }
}

if (-not $NoLaunch) { Start-Process -FilePath (Join-Path $dst 'Run Skin Studio.bat') -WorkingDirectory $dst -WindowStyle Minimized }
