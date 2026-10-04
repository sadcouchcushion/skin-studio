# galacta.ps1 - swap a freshly built mod into the RUNNING game with Project
# Galacta, no restart. Dot-sourced after skinlib.ps1 by build_skin.ps1 (the
# desktop BUILD MOD) and ingame\panel_server.ps1 (the in-game Build mod button).
#
# Project Galacta (Nexus 12806, by 0xSaturno) mounts every mod after login with
# the game's own NePatchUtility, and its F7 key unmounts / remounts them all
# while the game runs. Its own docs: F7, manage your mods, F7, then change level.
# Decoded from its GAL_ModLoader (1.2.2, 2026-09-26): ToggleMods walks the list
# of pak PATHS it recorded after login - UnmountPak each, then MountPak each at
# its recorded order. So:
#   - while unmounted, a mod's files are free: a rebuilt mod can go in at the
#     SAME path, and the second F7 mounts the NEW files;
#   - a mod file Galacta did not see at login is not on its list, so F7 does
#     not mount it - it loads at the next launch. We report what we observe;
#   - it shows after a level change (enter / leave a match or the Practice
#     Range): the game keeps loaded assets until their level goes away.
#
# The one thing visible from outside is which process holds a file open.
# Measured on the running game 2026-09-26: a mounted IoStore mod keeps its .ucas
# open (the .pak and .utoc are read at mount and closed). SS-FileHolders asks
# Windows for the list (FileProcessIdsUsingFileInformation) through a handle
# with FILE_READ_ATTRIBUTES and every share flag, so it can never make a mount
# fail - an exclusive "is it locked?" open could, if it landed mid-mount.
#
# Installing never leaves a half-replaced mod: the new files are staged outside
# Paks (nothing scans there), the old ones are RENAMED aside - a rename fails
# while the game holds the file, and then nothing has changed - and the new
# ones take their place, .pak last (the .pak is what a mount looks for).
#
# Keep this file ASCII: PS 5.1 reads a BOM-less script as Windows-1252.

$script:GAL = @{ Info = $null; InfoAt = [DateTime]::MinValue; InfoDir = '' }

function SS-EnsureFileUsers {
    if ('SSFileUsers' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SSFileUsers {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [StructLayout(LayoutKind.Sequential)]
    struct IoStatusBlock { public IntPtr Status; public IntPtr Information; }
    [DllImport("ntdll.dll")]
    static extern int NtQueryInformationFile(SafeFileHandle h, out IoStatusBlock iosb, IntPtr buf, uint len, int cls);
    // Process ids holding the file open; null when Windows could not be asked.
    // FILE_READ_ATTRIBUTES (0x80) + share read|write|delete: blocks nobody.
    public static long[] Pids(string path) {
        using (SafeFileHandle h = CreateFileW(path, 0x80, 7, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) return null;
            int size = 4096;
            for (int tries = 0; tries < 6; tries++) {
                IntPtr buf = Marshal.AllocHGlobal(size);
                try {
                    IoStatusBlock io;
                    // 47 = FileProcessIdsUsingFileInformation
                    int st = NtQueryInformationFile(h, out io, buf, (uint)size, 47);
                    if (st == unchecked((int)0xC0000004)) { size *= 4; continue; }
                    if (st != 0) return null;
                    int n = Marshal.ReadInt32(buf);
                    long[] r = new long[n];
                    for (int i = 0; i < n; i++) r[i] = Marshal.ReadIntPtr(buf, IntPtr.Size * (i + 1)).ToInt64();
                    return r;
                } finally { Marshal.FreeHGlobal(buf); }
            }
            return null;
        }
    }
}
'@
}

# Rivals' process ids. $procName names a stand-in process for rig tests
# (RS_PNL_GAMEPROC / RS_SS_GAMEPROC); '' = the real game.
function SS-GamePids([string]$procName) {
    $names = if ($procName) { @($procName) } else { @('Marvel-Win64-Shipping', 'MarvelRivals') }
    [long[]]@(Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object { [long]$_.Id })
}

# Every process holding the file open: an empty list when none or no such
# file, $null when Windows could not say. Assign the result - @(SS-FileHolders
# x) would nest the list inside a one-element array.
function SS-FileHolders([string]$path) {
    # the leading commas keep an EMPTY list a list: unrolled, it arrives as $null
    if (-not [IO.File]::Exists($path)) { return ,([long[]]@()) }
    SS-EnsureFileUsers
    $p = [SSFileUsers]::Pids($path)
    if ($null -eq $p) { return $null }
    ,$p
}

# $true / $false, or $null when it could not be asked
function SS-HeldByGame([string]$path, [long[]]$gamePids) {
    $h = SS-FileHolders $path
    if ($null -eq $h) { return $null }
    foreach ($x in $h) { if ($gamePids -contains $x) { return $true } }
    $false
}

# where to look for Galacta: the game's Paks folder, or a test mods folder
function SS-GalactaPaksDir([string]$modsDir) {
    if ($modsDir -and $modsDir.TrimEnd('\') -ine (Join-Path $SS_Paks '~mods')) { return $modsDir }
    $SS_Paks
}

# Is Project Galacta installed AND enabled? Its container can sit anywhere
# under Paks (loose, ~mods, a Vortex or Repak X folder). A disabled copy is
# renamed (.bak_repak) or not deployed at all (Vortex keeps it in its staging
# folder only), so only a live .pak with its .utoc and .ucas beside it counts.
# Cached for 15 s: it is asked on every build and every panel frame.
function SS-GalactaInfo([string]$paksDir = $SS_Paks, [switch]$Fresh) {
    $c = $script:GAL
    if (-not $Fresh -and $c.Info -and $c.InfoDir -eq $paksDir -and ([DateTime]::Now - $c.InfoAt).TotalSeconds -lt 15) { return $c.Info }
    $info = @{ Installed = $false; Pak = ''; Where = '' }
    try {
        # -Filter '*.pak' also matches 8.3 names like x.pak_old: check the extension
        $hits = @(Get-ChildItem -LiteralPath $paksDir -Recurse -File -Filter '*.pak' -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.pak' -and $_.BaseName -match 'ProjectGalacta' } | Sort-Object FullName)
        foreach ($h in $hits) {
            $base = Join-Path $h.DirectoryName $h.BaseName
            if ([IO.File]::Exists($base + '.utoc') -and [IO.File]::Exists($base + '.ucas')) {
                $info.Installed = $true; $info.Pak = $h.FullName
                $info.Where = $h.FullName.Substring($paksDir.TrimEnd('\').Length).TrimStart('\')
                break
            }
        }
    } catch {}
    $c.Info = $info; $c.InfoAt = [DateTime]::Now; $c.InfoDir = $paksDir
    $info
}

# ---------------------------------------------------------------- installing
# The staging folder: <Content>\SkinStudioSwap for the game (same volume as
# ~mods, so every move is a rename, and outside Paks, so neither the game nor
# Galacta ever scans it); <mods>_swap beside a test folder.
function SS-SwapStageDir([string]$modsDir) {
    $m = $modsDir.TrimEnd('\')
    $paks = Split-Path $m -Parent
    if ((Split-Path $m -Leaf) -ieq '~mods' -and (Split-Path $paks -Leaf) -ieq 'Paks') { return Join-Path (Split-Path $paks -Parent) 'SkinStudioSwap' }
    $m + '_swap'
}

function SS-ModFileNames([string]$mod) {
    # .ucas first (the file a mounted mod holds), .pak last (what a mount looks for)
    @('.ucas', '.utoc', '.pak') | ForEach-Object { '{0}_9999999_P{1}' -f $mod, $_ }
}

# old copies set aside by earlier swaps: whatever the game no longer maps goes
function SS-SwapSweep([string]$stageDir) {
    $old = Join-Path $stageDir 'old'
    if (-not [IO.Directory]::Exists($old)) { return }
    foreach ($d in @([IO.Directory]::GetDirectories($old))) { try { [IO.Directory]::Delete($d, $true) } catch {} }
}

# copy a built triplet (work\<mod>\out) into the staging folder; $false = no build
function SS-SwapStage([string]$mod, [string]$outDir, [string]$stageDir) {
    $names = @(SS-ModFileNames $mod)
    foreach ($n in $names) { if (-not [IO.File]::Exists((Join-Path $outDir $n))) { return $false } }
    $newDir = Join-Path $stageDir ('new\' + $mod)
    [void][IO.Directory]::CreateDirectory($newDir)
    foreach ($n in $names) { [IO.File]::Copy((Join-Path $outDir $n), (Join-Path $newDir $n), $true) }
    $true
}

# Put a staged mod in place at the ~mods root. 'now' | 'busy' (the old copy is
# in use: nothing changed) | 'missing' (nothing staged)
function SS-SwapCommit([string]$mod, [string]$modsDir, [string]$stageDir) {
    $newDir = Join-Path $stageDir ('new\' + $mod)
    $names = @(SS-ModFileNames $mod)
    foreach ($n in $names) { if (-not [IO.File]::Exists((Join-Path $newDir $n))) { return 'missing' } }
    [void][IO.Directory]::CreateDirectory($modsDir)
    $oldDir = Join-Path $stageDir ('old\{0}_{1}' -f $mod, [DateTime]::Now.Ticks)
    $aside = New-Object System.Collections.ArrayList
    try {
        foreach ($n in $names) {
            $dst = Join-Path $modsDir $n
            if (-not [IO.File]::Exists($dst)) { continue }
            [void][IO.Directory]::CreateDirectory($oldDir)
            $was = Join-Path $oldDir $n
            [IO.File]::Move($dst, $was)
            [void]$aside.Add(@($dst, $was))
        }
    } catch {
        for ($i = $aside.Count - 1; $i -ge 0; $i--) { try { [IO.File]::Move($aside[$i][1], $aside[$i][0]) } catch {} }
        try { if ([IO.Directory]::Exists($oldDir)) { [IO.Directory]::Delete($oldDir, $true) } } catch {}
        return 'busy'
    }
    $placed = New-Object System.Collections.ArrayList
    try {
        foreach ($n in $names) {
            $dst = Join-Path $modsDir $n
            [IO.File]::Move((Join-Path $newDir $n), $dst)
            [void]$placed.Add($n)
        }
    } catch {
        # cannot happen short of a full disk; put the old copy back
        foreach ($n in $placed) { try { [IO.File]::Move((Join-Path $modsDir $n), (Join-Path $newDir $n)) } catch {} }
        for ($i = $aside.Count - 1; $i -ge 0; $i--) { try { [IO.File]::Move($aside[$i][1], $aside[$i][0]) } catch {} }
        return 'busy'
    }
    try { [IO.Directory]::Delete($newDir) } catch {}
    # a copy the game still maps stays until SS-SwapSweep can remove it
    try { if ([IO.Directory]::Exists($oldDir)) { [IO.Directory]::Delete($oldDir, $true) } } catch {}
    'now'
}

# stage + commit: the whole install of one built mod
function SS-SwapInstall([string]$mod, [string]$outDir, [string]$modsDir) {
    $stage = SS-SwapStageDir $modsDir
    SS-SwapSweep $stage
    if (-not (SS-SwapStage $mod $outDir $stage)) { return 'missing' }
    SS-SwapCommit $mod $modsDir $stage
}

# ---------------------------------------------------------------- the swap
# Other mods' .ucas files the game holds open right now (at most 12). Whether
# they stay held is how we see Galacta unload (first F7) and reload (second
# F7). Never Galacta's own container (it does not unload itself) or the
# in-game editor's, and only files Windows could answer for.
function SS-GameHeldRefs([string]$modsDir, [string[]]$mods, [long[]]$gamePids) {
    $refs = New-Object System.Collections.ArrayList
    if (@($gamePids).Count -eq 0) { return }
    $root = $modsDir.TrimEnd('\')
    $ours = @($mods | ForEach-Object { ('{0}_9999999_P.ucas' -f $_).ToLowerInvariant() })
    $all = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ucas' -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.ucas' } | Sort-Object FullName)
    foreach ($f in $all) {
        if ($f.Name -match 'ProjectGalacta|^SkinLive|^SkinProbe') { continue }
        if ($f.DirectoryName -ieq $root -and $ours -contains $f.Name.ToLowerInvariant()) { continue }
        if ((SS-HeldByGame $f.FullName $gamePids) -eq $true) { [void]$refs.Add($f.FullName) }
        if ($refs.Count -ge 12) { break }
    }
    # unrolled on purpose: callers wrap it in @() (a ,$list would come back
    # from @() as ONE element holding the whole list)
    $refs.ToArray()
}

# @{ Held; Known } over the reference files
function SS-RefsHeld($refs, [long[]]$gamePids) {
    $r = @{ Held = 0; Known = 0 }
    foreach ($f in @($refs)) {
        $h = SS-HeldByGame $f $gamePids
        if ($null -eq $h) { continue }
        $r.Known++
        if ($h) { $r.Held++ }
    }
    $r
}

function SS-GalSwapLeft($sw) { @($sw.Mods | Where-Object { $sw.Installed -notcontains $_ -and $sw.Missing -notcontains $_ }) }

# ---------------------------------------------------------------- pressing F7
# The in-game mod (bootstrap AutoTick, once a second) watches for this save
# slot, deletes it, and calls Galacta's own ModLoader.ToggleMods by name - the
# very function her F7 runs. So Skin Studio presses F7 for her (her ask,
# 2026-09-26). The flag vanishing is the game's answer; the files the game
# holds say whether it did the right thing. An in-game mod from before this
# never takes the flag: after 5 s it is taken back and she is asked instead.
function SS-GalFlagPath($sw) { Join-Path $sw.AutoDir 'SkinLiveGalToggle.sav' }

function SS-GalAsk($sw, [string]$tag) {
    if (-not $sw.AutoDir -or $sw.AutoOff -or $sw.Ask -or ($sw.Asked -contains $tag)) { return }
    $hl = Join-Path $sw.AutoDir 'HighlightSettings.sav'
    # valid save bytes, as every flag here: the game never meets a broken .sav
    $bytes = if ([IO.File]::Exists($hl)) { [IO.File]::ReadAllBytes($hl) } else { [Text.Encoding]::ASCII.GetBytes('SkinLive') }
    try { [IO.File]::WriteAllBytes((SS-GalFlagPath $sw), $bytes) } catch { $sw.AutoOff = $true; return }
    $sw.Asked += $tag; $sw.Ask = $tag; $sw.AskAt = [DateTime]::Now; $sw.AskGone = [DateTime]::MinValue
}

# take back a request nobody acted on - never leave one lying around for a
# later game session to act on unasked
function SS-GalAskCancel($sw) {
    if (-not $sw.AutoDir) { return }
    $f = SS-GalFlagPath $sw
    if ([IO.File]::Exists($f)) { try { [IO.File]::Delete($f) } catch {} }
    $sw.Ask = ''
}

# the pending request: $changed = the files show it happened
function SS-GalAskCheck($sw, [bool]$changed) {
    if (-not $sw.Ask) { return }
    if ($changed) { $sw.Ask = ''; return }
    $now = [DateTime]::Now
    if ([IO.File]::Exists((SS-GalFlagPath $sw))) {
        # not taken: this game's in-game mod cannot press F7 for her
        if (($now - $sw.AskAt).TotalSeconds -ge 5) { SS-GalAskCancel $sw; $sw.AutoOff = $true }
        return
    }
    if ($sw.AskGone -eq [DateTime]::MinValue) { $sw.AskGone = $now }
    # taken, but no Galacta loader in this level (gal_0), or nothing changed
    if ($sw.GalAnswer -eq '0' -or ($now - $sw.AskGone).TotalSeconds -ge 8) { $sw.AutoOff = $true; $sw.Ask = '' }
}

# One build's trip into the running game. SS-GalSwapNew stages the new files
# and notes what the game holds; SS-GalSwapStep (every ~250 ms) moves it on:
#   unload  waiting for F7: Galacta unmounts every mod and the game lets go
#           of the old files. Each mod goes in the moment its old copy is free
#           (a new mod, with no old copy, goes in at once).
#   reload  installed; waiting for the second F7 (the game opens the mods again)
#   done    Loaded: $true (the game holds our new files), $false (Galacta
#           reloaded the other mods and not ours: one it did not see at login),
#           $null (nothing to compare against). NoGame: Rivals quit on the way
#           and everything went straight in. Stopped: the caller gave up.
# $saveDir: the game's SaveGames folder, where the "press F7" flag goes ('' =
# never press it for her). AutoOff: the game did not answer - she presses it.
function SS-GalSwapNew([string[]]$mods, [string]$modsDir, [string]$gameProc, [string]$saveDir = '') {
    $stage = SS-SwapStageDir $modsDir
    SS-SwapSweep $stage
    $sw = @{
        Mods = @($mods); ModsDir = $modsDir.TrimEnd('\'); Stage = $stage; GameProc = $gameProc
        Phase = 'unload'; Installed = @(); Missing = @(); HadOld = @(); Refs = @()
        UnloadSeen = $false; RefsUp = $null; RefsBackAt = [DateTime]::MinValue
        Loaded = $null; NoGame = $false; Stopped = $false; Started = [DateTime]::Now
        AutoDir = $saveDir; AutoOff = $false; Ask = ''; Asked = @(); AskAt = [DateTime]::MinValue; AskGone = [DateTime]::MinValue; GalAnswer = ''
    }
    # a request left over from a run that died must not fire now
    if ($saveDir -and -not [IO.Directory]::Exists($saveDir)) { $sw.AutoDir = '' }
    SS-GalAskCancel $sw
    foreach ($m in $sw.Mods) {
        if (-not (SS-SwapStage $m (Join-Path $SS_Root ('work\{0}\out' -f $m)) $stage)) { $sw.Missing += $m; continue }
        if ([IO.File]::Exists((Join-Path $sw.ModsDir ('{0}_9999999_P.ucas' -f $m)))) { $sw.HadOld += $m }
    }
    $sw.Refs = @(SS-GameHeldRefs $sw.ModsDir $sw.Mods (SS-GamePids $gameProc))
    $sw
}

function SS-GalSwapStep($sw) {
    if ($sw.Phase -eq 'done') { return }
    $gp = SS-GamePids $sw.GameProc
    if ($gp.Count -eq 0) {
        # Rivals is gone, so nothing is mounted: everything goes in now
        SS-GalAskCancel $sw
        foreach ($m in (SS-GalSwapLeft $sw)) {
            $r = SS-SwapCommit $m $sw.ModsDir $sw.Stage
            if ($r -eq 'now') { $sw.Installed += $m } elseif ($r -eq 'missing') { $sw.Missing += $m }
        }
        if ((SS-GalSwapLeft $sw).Count -eq 0) { $sw.Phase = 'done'; $sw.NoGame = $true }
        return
    }
    $rh = SS-RefsHeld $sw.Refs $gp
    $sw.RefsUp = if ($rh.Known -eq 0) { $null } else { ($rh.Held * 2 -ge $rh.Known) }
    if ($sw.RefsUp -eq $false) { $sw.UnloadSeen = $true }
    if ($sw.Phase -eq 'unload') {
        foreach ($m in (SS-GalSwapLeft $sw)) {
            # still mounted: wait for F7. (Could not ask: try - a rename of a
            # file the game holds just fails, and nothing changes.)
            if ((SS-HeldByGame (Join-Path $sw.ModsDir ('{0}_9999999_P.ucas' -f $m)) $gp) -eq $true) { continue }
            $r = SS-SwapCommit $m $sw.ModsDir $sw.Stage
            if ($r -eq 'now') { $sw.Installed += $m } elseif ($r -eq 'missing') { $sw.Missing += $m }
        }
        if ((SS-GalSwapLeft $sw).Count -eq 0) {
            $sw.Ask = ''                        # the unload it asked for happened
            $sw.Phase = $(if ($sw.Installed.Count) { 'reload' } else { 'done' })
            return
        }
        # the old copy is still mounted: press F7 for her
        if ($sw.Ask) { SS-GalAskCheck $sw ($sw.RefsUp -eq $false) } else { SS-GalAsk $sw 'u' }
        return
    }
    # reload: our new files held again = Galacta mounted them
    foreach ($m in $sw.Installed) {
        if ((SS-HeldByGame (Join-Path $sw.ModsDir ('{0}_9999999_P.ucas' -f $m)) $gp) -eq $true) { $sw.Ask = ''; $sw.Phase = 'done'; $sw.Loaded = $true; return }
    }
    # press F7 for her: the mods are unloaded (by us or by her) -> reload them;
    # still up and never unloaded (a mod new this session) -> unload first
    if ($sw.Ask) {
        SS-GalAskCheck $sw $(if ($sw.Ask -eq 'r') { $sw.RefsUp -eq $true } else { $sw.RefsUp -eq $false })
    } elseif ($sw.RefsUp -eq $false -or ($null -eq $sw.RefsUp -and $sw.Asked -contains 'u')) {
        SS-GalAsk $sw 'r'
    } elseif ($sw.RefsUp -eq $true -and -not $sw.UnloadSeen) {
        SS-GalAsk $sw 'u2'
    }
    if ($sw.UnloadSeen -and $sw.RefsUp -eq $true) {
        # the others are back and ours is not: one frame mounts them all, so
        # give it a moment, then call it
        if ($sw.RefsBackAt -eq [DateTime]::MinValue) { $sw.RefsBackAt = [DateTime]::Now }
        elseif (([DateTime]::Now - $sw.RefsBackAt).TotalSeconds -ge 3) { SS-GalAskCancel $sw; $sw.Phase = 'done'; $sw.Loaded = $false }
    } else { $sw.RefsBackAt = [DateTime]::MinValue }
}

# the automation is live: the game has a mod that can press F7, as far as we know
function SS-GalAuto($sw) { [bool]($sw.AutoDir -and -not $sw.AutoOff) }

# what to tell her, one line, in her words
function SS-GalSwapText($sw) {
    $new = @($sw.Installed | Where-Object { $sw.HadOld -notcontains $_ }).Count -gt 0
    $auto = SS-GalAuto $sw
    switch ($sw.Phase) {
        'unload' {
            if ($auto) { return 'Pressing F7 for you: Project Galacta unloads your mods, and the new build goes in the moment the old one is free.' }
            return 'Press F7 in Rivals: Project Galacta unloads your mods, and the new build goes in the moment the old one is free.'
        }
        'reload' {
            if ($auto) {
                if ($new -and -not $sw.UnloadSeen -and $sw.RefsUp -eq $true) {
                    return 'Installed. It is new this session, and Galacta only reloads the mods it found at login - trying F7 twice for you anyway (unload, reload).'
                }
                return 'Swapped in. Pressing F7 again for you: Galacta reloads your mods.'
            }
            if ($sw.RefsUp -eq $false) { return 'Swapped in. Press F7 again: Galacta reloads your mods.' }
            if ($new -and $sw.RefsUp -eq $true -and -not $sw.UnloadSeen) {
                return 'Installed. It is new this session, and Galacta only reloads the mods it found at login, so it most likely shows at your next launch. To try now: press F7 twice (unload, reload).'
            }
            if ($sw.RefsUp -eq $true -and -not $sw.UnloadSeen) { return 'Installed. Press F7 twice in Rivals: Galacta unloads, then reloads, your mods.' }
            return 'Swapped in. Press F7 again: Galacta reloads your mods.'
        }
        default {
            if ($sw.Stopped) { return 'Stopped waiting for Galacta.' }
            if ($sw.NoGame) { return 'Rivals closed, so it went straight in - it loads at your next launch.' }
            if ($sw.Installed.Count -eq 0) { return 'Nothing was installed - no built files.' }
            if ($sw.Loaded -eq $true) { return 'Loaded. Enter or leave a match or the Practice Range to see it - the game swaps it in on a level change.' }
            if ($sw.Loaded -eq $false) { return 'Galacta reloaded your mods but not this one - it only reloads the mods it found when you logged in. It loads at your next launch.' }
            return 'Installed. Press F7 twice in Rivals (unload, reload), then enter or leave the Practice Range.'
        }
    }
}

# The desktop BUILD MOD's version: the build window walks her through it and
# chimes at each step (she is in the game, not looking at this window). Esc
# stops waiting. Returns the swap.
function SS-GalSwapConsole([string[]]$mods, [string]$modsDir, [string]$gameProc, [scriptblock]$log, [string]$saveDir = '') {
    $gal = SS-GalactaInfo (SS-GalactaPaksDir $modsDir)
    & $log ('Rivals is running with Project Galacta ({0}) - swapping {1} in without a restart:' -f $gal.Where, ($mods -join ', '))
    & $log '  1. Galacta unloads your mods (its F7) - Skin Studio presses it for you through the'
    & $log '     in-game mod; if the game does not answer within a few seconds, it asks you to.'
    & $log '  2. The new files go in the moment the old ones are free (a chime).'
    & $log '  3. Galacta reloads your mods (F7 again - a second chime once the game has it).'
    & $log '  4. Enter or leave a match or the Practice Range: the game shows it after a level change.'
    & $log '  (Esc in this window stops waiting - the mod is then NOT installed.)'
    $sw = SS-GalSwapNew $mods $modsDir $gameProc $saveDir
    if ($sw.Missing.Count) { & $log ('  no built files for: ' + ($sw.Missing -join ', ')) }
    $said = ''; $phase = ''; $autoWas = SS-GalAuto $sw
    while ($true) {
        SS-GalSwapStep $sw
        if ($autoWas -and -not (SS-GalAuto $sw)) {
            & $log '  (the game did not press F7 - its Skin Studio mod predates this, or there is no Galacta loader in this level. Over to you:)'
            $autoWas = $false
        }
        $t = SS-GalSwapText $sw
        if ($t -ne $said) { & $log ('  ' + $t); $said = $t }
        if ($sw.Phase -ne $phase) {
            # (RS_SS_QUIET: rig tests, which must not chime at her mid-game)
            if ($phase -and $sw.Phase -in @('reload', 'done') -and -not $env:RS_SS_QUIET) { try { [System.Media.SystemSounds]::Asterisk.Play() } catch {} }
            $phase = $sw.Phase
        }
        if ($sw.Phase -eq 'done') { break }
        try {
            if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Escape') {
                SS-GalAskCancel $sw
                $sw.Stopped = $true; $sw.Phase = 'done'
                $left = SS-GalSwapLeft $sw
                if ($left.Count) { & $log ('  stopped - NOT installed: {0}. Build again once Rivals is closed, or copy work\<mod>\out\* into ~mods.' -f ($left -join ', ')) }
                else { & $log '  stopped waiting - the new files are in; press F7 twice in Rivals to load them.' }
                break
            }
        } catch {}
        Start-Sleep -Milliseconds 250
    }
    if ($sw.Installed.Count) { & $log ('  installed at the ~mods root: {0}' -f (($sw.Installed | ForEach-Object { $_ + '_9999999_P' }) -join ', ')) }
    $sw
}
