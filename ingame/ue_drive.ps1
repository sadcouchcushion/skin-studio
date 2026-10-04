# ue_drive.ps1 - drive the Unreal editor window from the shell.
#
# Her machine has no Start-menu entry for Unreal and UnrealEditor.exe carries no
# version info, so the computer-use tools cannot be granted it (they resolve
# apps by name). This does the same job with Win32: focus the window, move and
# click the mouse, send keys, and grab the screen to check the result.
#
#   ue_drive.ps1 -Do shot  -Out C:\...\shot.png      what is on screen now
#   ue_drive.ps1 -Do focus                            bring the editor forward
#   ue_drive.ps1 -Do click -X 900 -Y 500 [-Double]
#   ue_drive.ps1 -Do drag  -X 100 -Y 200 -X2 800 -Y2 400
#   ue_drive.ps1 -Do keys  -Text "^a"                 SendKeys syntax
#   ue_drive.ps1 -Do type  -Text 'py "D:/x.py"'       literal text, then Enter with -Enter
#   ue_drive.ps1 -Do paste -File D:\SkinLiveUE\paste\editor_1.txt
#
# Every action returns the foreground window's title, so a step that silently
# went to the wrong window is visible in the output instead of being guessed at.
param(
    [ValidateSet('shot', 'focus', 'click', 'rclick', 'drag', 'keys', 'type', 'paste', 'title', 'move', 'setclip')]
    [string]$Do = 'shot',
    [int]$X, [int]$Y, [int]$X2, [int]$Y2,
    [string]$Text, [string]$File,
    [string]$Out = "$env:TEMP\rs\shots\ue.png",
    [switch]$Double, [switch]$Enter, [switch]$NoFocus,
    [int]$Settle = 250,
    # which Unreal window to act on: asset editors are separate top-level windows
    [string]$WinMatch = 'WBP_SkinLive|Unreal Editor'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

if (-not ('UeWin' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class UeWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
    public const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004, RIGHTDOWN = 0x0008, RIGHTUP = 0x0010;
    public static void RClick(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(80);
        mouse_event(RIGHTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(RIGHTUP, 0, 0, 0, IntPtr.Zero);
    }
    public static string Title(IntPtr h) {
        var sb = new StringBuilder(512);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString();
    }
    public static string Foreground() { return Title(GetForegroundWindow()); }
    public static void Click(int x, int y, bool dbl) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(60);
        mouse_event(LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(40);
        mouse_event(LEFTUP, 0, 0, 0, IntPtr.Zero);
        if (dbl) {
            System.Threading.Thread.Sleep(60);
            mouse_event(LEFTDOWN, 0, 0, 0, IntPtr.Zero);
            System.Threading.Thread.Sleep(40);
            mouse_event(LEFTUP, 0, 0, 0, IntPtr.Zero);
        }
    }
    // SendKeys reaches text boxes but not Slate's graph canvas; raw SendInput
    // scan codes do. vks: virtual key codes, mods: "ctrl","shift","alt".
    [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {
        public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Explicit)] public struct INPUT {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public KEYBDINPUT ki;
    }
    [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern short VkKeyScan(char ch);
    static INPUT Key(ushort vk, bool up) {
        var i = new INPUT();
        i.type = 1;
        i.ki = new KEYBDINPUT { wVk = vk, wScan = 0, dwFlags = up ? 2u : 0u, time = 0, dwExtraInfo = IntPtr.Zero };
        return i;
    }
    public static void Chord(ushort[] mods, ushort vk) {
        var list = new System.Collections.Generic.List<INPUT>();
        foreach (var m in mods) list.Add(Key(m, false));
        list.Add(Key(vk, false));
        list.Add(Key(vk, true));
        for (int i = mods.Length - 1; i >= 0; i--) list.Add(Key(mods[i], true));
        var arr = list.ToArray();
        SendInput((uint)arr.Length, arr, Marshal.SizeOf(typeof(INPUT)));
    }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    public static System.Collections.Generic.List<string> WindowsOf(uint want) {
        var outp = new System.Collections.Generic.List<string>();
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid == want) outp.Add(string.Format("{0}|{1}|{2}", h.ToInt64(), IsWindowVisible(h), Title(h)));
            return true;
        }, IntPtr.Zero);
        return outp;
    }
    public static void Drag(int x1, int y1, int x2, int y2) {
        SetCursorPos(x1, y1);
        System.Threading.Thread.Sleep(80);
        mouse_event(LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(120);
        // a few steps, or Slate reads it as a click and never starts the drag
        for (int i = 1; i <= 12; i++) {
            SetCursorPos(x1 + (x2 - x1) * i / 12, y1 + (y2 - y1) * i / 12);
            System.Threading.Thread.Sleep(35);
        }
        System.Threading.Thread.Sleep(150);
        mouse_event(LEFTUP, 0, 0, 0, IntPtr.Zero);
    }
}
'@
}

# ★ An asset editor is its OWN top-level window, and the main "SkinLive -
# Unreal Editor" window can be hidden behind it - Process.MainWindowHandle then
# reports 0 and every helper here thinks Unreal is not running. Enumerate the
# process's visible windows and pick by title instead.
function Get-UeWindow {
    $procs = @(Get-Process -Name UnrealEditor -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { throw 'the Unreal editor is not running' }
    $cands = @()
    foreach ($p in $procs) {
        foreach ($row in [UeWin]::WindowsOf([uint32]$p.Id)) {
            $f = $row -split '\|', 3
            if ($f[1] -ne 'True') { continue }        # visible only
            if (-not $f[2]) { continue }              # titled only
            $cands += [pscustomobject]@{ Handle = [IntPtr][int64]$f[0]; Title = $f[2] }
        }
    }
    if ($cands.Count -eq 0) { throw 'the Unreal editor has no visible window' }
    $hit = @($cands | Where-Object { $_.Title -match $WinMatch })
    if ($hit.Count -gt 0) { return $hit[0] }
    $cands[0]
}

# ★ Windows refuses SetForegroundWindow from a background process, so a click
# aimed at Unreal can land in whatever window is actually in front - it went
# into the Claude window once. Press Alt first (that makes this process the one
# changing the foreground), retry, and then VERIFY: every action below refuses
# to run unless Unreal really is frontmost.
function Set-UeFocus {
    $w = Get-UeWindow
    $h = $w.Handle
    for ($i = 0; $i -lt 6; $i++) {
        if ([UeWin]::GetForegroundWindow() -eq $h) { return $true }
        if ([UeWin]::IsIconic($h)) { [void][UeWin]::ShowWindow($h, 9) }   # SW_RESTORE
        [UeWin]::Chord([uint16[]]@(), [uint16]0x12)                       # tap Alt
        [void][UeWin]::BringWindowToTop($h)
        [void][UeWin]::SetForegroundWindow($h)
        [void][UeWin]::ShowWindow($h, 5)                                  # SW_SHOW
        Start-Sleep -Milliseconds 350
    }
    [UeWin]::GetForegroundWindow() -eq $h
}

function Assert-Ue {
    $w = Get-UeWindow
    if ([UeWin]::GetForegroundWindow() -ne $w.Handle) {
        throw ("Unreal is not frontmost (in front: '{0}') - refusing to click or type" -f [UeWin]::Foreground())
    }
}

function Save-Shot([string]$path) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $scr.Width, $scr.Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($scr.X, $scr.Y, 0, 0, $bmp.Size)
    $gfx.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $path
}

if ($Do -ne 'shot' -and $Do -ne 'title') {
    if (-not $NoFocus) { $null = Set-UeFocus }
    Assert-Ue                     # never act on someone else's window
}

switch ($Do) {
    'title' { [UeWin]::Foreground() }
    'focus' { [UeWin]::Foreground() }
    'shot'  { Save-Shot $Out; "foreground: " + [UeWin]::Foreground() }
    'move'  { [void][UeWin]::SetCursorPos($X, $Y); "at $X,$Y" }
    'click' { [UeWin]::Click($X, $Y, [bool]$Double); Start-Sleep -Milliseconds $Settle; "clicked $X,$Y  fg: " + [UeWin]::Foreground() }
    'rclick' { [UeWin]::RClick($X, $Y); Start-Sleep -Milliseconds $Settle; "right-clicked $X,$Y  fg: " + [UeWin]::Foreground() }
    'setclip' {
        $raw2 = [IO.File]::ReadAllText($File)
        Set-Clipboard -Value $raw2
        Start-Sleep -Milliseconds 250
        "clipboard holds {0:N0} bytes" -f (Get-Clipboard -Raw).Length
    }
    'drag'  { [UeWin]::Drag($X, $Y, $X2, $Y2); Start-Sleep -Milliseconds $Settle; "dragged $X,$Y -> $X2,$Y2  fg: " + [UeWin]::Foreground() }
    'keys'  {
        # $Text like "ctrl+a", "delete", "ctrl+v", "f7"
        $parts = @($Text.ToLower() -split '\+')
        $vkMap = @{ 'a' = 0x41; 'v' = 0x56; 'c' = 0x43; 's' = 0x53; 'z' = 0x5A; 'delete' = 0x2E; 'del' = 0x2E
                    'enter' = 0x0D; 'escape' = 0x1B; 'esc' = 0x1B; 'tab' = 0x09; 'f7' = 0x76; 'f6' = 0x75 }
        $modMap = @{ 'ctrl' = 0x11; 'shift' = 0x10; 'alt' = 0x12 }
        $mods = @()
        $vk = 0
        foreach ($p in $parts) {
            if ($modMap.ContainsKey($p)) { $mods += [uint16]$modMap[$p] }
            elseif ($vkMap.ContainsKey($p)) { $vk = [uint16]$vkMap[$p] }
            else { throw "unknown key '$p'" }
        }
        if ($vk -eq 0) { throw "no key in '$Text'" }
        # ★ SendInput chords were silently doing nothing here (the INPUT struct
        # is 40 bytes on x64, not the 32 this marshals to, so the call fails and
        # returns 0). SendKeys does reach this app, so build its syntax instead.
        $sk = ''
        foreach ($m in $parts) {
            switch ($m) { 'ctrl' { $sk += '^' } 'shift' { $sk += '+' } 'alt' { $sk += '%' } }
        }
        $named = @{ 'delete' = '{DELETE}'; 'del' = '{DELETE}'; 'enter' = '{ENTER}'; 'escape' = '{ESC}'
                    'esc' = '{ESC}'; 'tab' = '{TAB}'; 'f4' = '{F4}'; 'f6' = '{F6}'; 'f7' = '{F7}'; 'home' = '{HOME}' }
        $last = $parts[-1]
        $sk += $(if ($named.ContainsKey($last)) { $named[$last] } else { $last })
        [System.Windows.Forms.SendKeys]::SendWait($sk)
        Start-Sleep -Milliseconds $Settle
        "sent {0} ({1})  fg: {2}" -f $Text, $sk, [UeWin]::Foreground()
    }
    'type'  {
        # escape the SendKeys metacharacters so a path types literally
        $esc = $Text -replace '([+^%~(){}\[\]])', '{$1}'
        [System.Windows.Forms.SendKeys]::SendWait($esc)
        if ($Enter) { Start-Sleep -Milliseconds 150; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}') }
        Start-Sleep -Milliseconds $Settle
        "typed {0} char(s)  fg: {1}" -f $Text.Length, [UeWin]::Foreground()
    }
    'paste' {
        if (-not (Test-Path -LiteralPath $File)) { throw "no such file: $File" }
        $raw = [IO.File]::ReadAllText($File)
        Set-Clipboard -Value $raw
        Start-Sleep -Milliseconds 250
        $back = Get-Clipboard -Raw
        if (($back -replace "`r", '') -ne ($raw -replace "`r", '')) {
            throw 'the clipboard did not take the paste text (something else owns it?)'
        }
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 900
        "pasted {0:N0} bytes  fg: {1}" -f $raw.Length, [UeWin]::Foreground()
    }
}
