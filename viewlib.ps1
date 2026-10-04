# viewlib.ps1 - the 3D preview window (viewer\), dot-sourced by SkinStudio.ps1
# after skinlib.ps1 + meshlib.ps1.
#
#   SS-BuildViewScene  bakes the current design into cache\<skin>\view\ and
#                      writes scene.json (mesh, per-slot texture, BaseTint)
#   Show-3DPreview     opens / refreshes the WebView2 window on that scene
#
# The window is a WebView2 control whose virtual host https://skinstudio.local/
# maps onto C:\rs\SkinStudio - no web server, nothing listens on a port.
# WebView2 DLLs (Microsoft-signed SDK 1.0.2957, redistributable) and three.js
# (MIT) live in viewer\lib and viewer\three.

$SS_ViewRoot = Join-Path $SS_Root 'viewer'
$SS_ViewMax  = 2048          # long-edge cap for preview maps (GPU memory)
Add-Type -Path (Join-Path $SS_ViewRoot 'ViewArt.cs') -ReferencedAssemblies System.Drawing

function SS-ViewDir([string]$skin) { Join-Path (Join-Path $SS_Cache $skin) 'view' }

# colors.json -> @{ leaf = @{ lobby=[bool]; asset; params = @{ name = @(r,g,b) } } },
# with the design's colour edits laid over the vanilla values. Two MI sets share
# leaf names (Materials\ and Materials\Lobby\), so both are kept, keyed
# 'L|<leaf>' and 'M|<leaf>'.
function SS-ViewMatColors([string]$skin, $colorOps) {
    $out = @{}
    $cj = Join-Path (Join-Path $SS_Cache $skin) 'colors.json'
    if (-not (Test-Path $cj)) { return $out }
    # assign first: PS 5.1 emits a JSON array as ONE object, so @(... | ConvertFrom-Json)
    # is a one-element array holding the whole list
    $all = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json
    foreach ($a in $all) {
        $asset = [string]$a.asset
        $leaf = [IO.Path]::GetFileNameWithoutExtension($asset)
        $lobby = $asset -match '/Lobby/'
        $edits = $null
        if ($colorOps) {
            foreach ($k in @($colorOps.Keys)) { if (($k -replace '\\', '/') -eq $asset) { $edits = $colorOps[$k]; break } }
        }
        $p = @{}
        foreach ($c in @($a.colors)) {
            if ([string]$c.kind -eq 'curve') { continue }
            $rgb = @([double]$c.r, [double]$c.g, [double]$c.b)
            if ($edits) {
                $ek = '{0}_{1}' -f $c.export, $c.ordinal
                $e = $null
                if ($edits -is [hashtable]) { if ($edits.ContainsKey($ek)) { $e = $edits[$ek] } }
                elseif ($edits.PSObject.Properties[$ek]) { $e = $edits.$ek }
                if ($e) { $rgb = @([double](SS-OpVal $e 'r' $rgb[0]), [double](SS-OpVal $e 'g' $rgb[1]), [double](SS-OpVal $e 'b' $rgb[2])) }
            }
            if (-not $p.ContainsKey([string]$c.name)) { $p[[string]$c.name] = $rgb }
        }
        $out[('{0}|{1}' -f $(if ($lobby) { 'L' } else { 'M' }), $leaf)] = @{ lobby = $lobby; asset = $asset; params = $p }
    }
    $out
}

# the 8 x 4 x 4 float block ViewArt.DyeComposite wants, from one MI's params
function SS-ViewDyeBlock($params) {
    $f = New-Object float[] 128
    $slots = @('ColorA', 'ColorB', 'ColorGChannel', 'ColorBChannel')
    for ($r = 1; $r -le 7; $r++) {
        for ($s = 0; $s -lt 4; $s++) {
            $n = 'Region {0} - {1}' -f $r, $slots[$s]
            if ($params.ContainsKey($n)) {
                $o = $r * 16 + $s * 4
                $v = $params[$n]
                $f[$o] = [float]$v[0]; $f[$o + 1] = [float]$v[1]; $f[$o + 2] = [float]$v[2]; $f[$o + 3] = 1
            }
        }
    }
    , $f
}

function SS-ViewHash([string]$s) {
    $md5 = [Security.Cryptography.MD5]::Create()
    try { -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $md5.Dispose() }
}

# Bake the design for the viewer and write scene.json. Incremental: a map is
# re-rendered only when its op stack (or the vanilla source) changed, so
# refreshing after one edit costs one texture, not forty.
#   $ops       texture ops for THIS skin (rel -> layer stack), as Get-Ops gives
#   $colorOps  colour edits for THIS skin (asset -> "exp_ord" -> edit)
# Returns the scene.json path relative to the studio root (forward slashes).
function SS-BuildViewScene([string]$skin, $ops, $colorOps, [string]$title, [scriptblock]$Progress) {
    $ck = Join-Path $SS_Cache $skin
    $say = { param($m) if ($Progress) { & $Progress $m | Out-Host } }
    # A chroma (recolour) ships NO mesh - it wears its costume's body with its
    # own materials. So borrow the mesh from a sibling in its chroma group and
    # re-point each slot (MI_1064300_Body -> MI_1064301_Body) below.
    $meshSkin = $skin
    if (@(SS-SkinMeshAssets $skin).Count -eq 0) {
        $sib = SS-ChromaTargets $skin
        foreach ($c in (@($sib.Sure) + @($sib.Maybe))) {
            if (@(SS-SkinMeshAssets $c).Count -gt 0) { $meshSkin = [string]$c; break }
        }
        if ($meshSkin -eq $skin) { throw "skin $skin has no mesh of its own and no costume in its chroma group has one" }
        & $say "3D preview: $skin is a recolour - using the $meshSkin body"
    }
    $glb = @(SS-EnsureMesh $meshSkin -Lobby -Progress $Progress)
    if ($glb.Count -eq 0) { $glb = @(SS-EnsureMesh $meshSkin -Progress $Progress) }
    $glb = $glb[0]
    $isLobby = [IO.Path]::GetFileNameWithoutExtension($glb) -like '*_Lobby'

    $vd = SS-ViewDir $skin
    $td = Join-Path $vd 'tex'
    New-Item -ItemType Directory -Force -Path $td | Out-Null
    $srcF = Join-Path $vd '_src.json'
    $prev = @{}
    if (Test-Path $srcF) { try { $j = Get-Content -LiteralPath $srcF -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $prev[$p.Name] = [string]$p.Value } } catch {} }
    $now = @{}

    # 1) colour maps: design ops applied, the rest vanilla
    $pngRoot = Join-Path $ck 'png\src'
    $rows = [IO.File]::ReadAllLines((Join-Path $ck 'thumbs.map'))
    $relOf = @{}                                  # leaf (no ext) -> rel, every role
    $n = 0; $done = 0
    foreach ($row in $rows) {
        $rel = $row.Split('|')[0]
        $leaf = [IO.Path]::GetFileNameWithoutExtension($rel)
        $relOf[$leaf] = $rel
        if ((SS-TexRole $rel) -ne 'color') { continue }
        $src = Join-Path $pngRoot $rel
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dstName = $leaf + '.png'
        $dst = Join-Path $td $dstName
        $op = $null
        if ($ops -and $ops.ContainsKey($rel)) { $op = $ops[$rel] }
        $srcStamp = (Get-Item -LiteralPath $src).LastWriteTimeUtc.Ticks
        $key = if ($op) { 'op:' + (SS-ViewHash (($op | ConvertTo-Json -Depth 10 -Compress) + '|' + $srcStamp)) } else { 'v:' + $srcStamp }
        $now[$dstName] = $key
        $n++
        if ((Test-Path -LiteralPath $dst) -and $prev[$dstName] -eq $key) { continue }
        if ($op) {
            $bmp = SS-RenderStack $src $op
            $tmp = Join-Path $td ('_full_' + $dstName)
            try { [SkinArt]::SavePngLike($bmp, $tmp, $src) } finally { $bmp.Dispose() }
            [ViewArt]::Shrink($tmp, $dst, $SS_ViewMax)
            [IO.File]::Delete($tmp)
        } else {
            [ViewArt]::Shrink($src, $dst, $SS_ViewMax)
        }
        $done++
        if ($done % 5 -eq 0) { & $say ("3D preview: baking maps... {0}" -f $done) }
    }

    # 2) which map each material draws (the MI packages say; same pick as the
    #    Blender bake: first _D, else _E, that exists)
    $matmap = @{}
    $mt = $null
    try { $mt = Get-Content -LiteralPath (SS-EnsureMatTextures $skin $Progress) -Raw | ConvertFrom-Json } catch {}
    $masks = @{}
    if ($mt) {
        foreach ($p in $mt.PSObject.Properties) {
            $pick = $null
            foreach ($sfx in '_D', '_E') {
                foreach ($t in @($p.Value.textures)) {
                    if ($t -like "*$sfx" -and $now.ContainsKey($t + '.png')) { $pick = $t + '.png'; break }
                }
                if ($pick) { break }
            }
            if ($pick) { $matmap[$p.Name] = $pick }
            $m = @($p.Value.textures | Where-Object { $_ -like '*_ColorID' }) | Select-Object -First 1
            if ($m) { $masks[$p.Name] = [string]$m }
        }
    }

    # 3) colours: BaseTint per slot, and the dye composited into a per-material map
    $mc = SS-ViewMatColors $skin $colorOps
    $want = if ($isLobby) { 'L' } else { 'M' }
    $tints = @{}
    $dyed = 0
    $slotMap = @{}                                 # glb slot -> this skin's MI
    foreach ($slot in (SS-GlbMaterials $glb | Select-Object -Unique)) {
        $mi = $slot
        if ($meshSkin -ne $skin) {
            $mi = $slot.Replace($meshSkin, $skin)
            if (-not $matmap.ContainsKey($mi) -and $matmap.ContainsKey($slot)) { $mi = $slot }
            if ($matmap.ContainsKey($mi)) { $matmap[$slot] = $matmap[$mi] }
            if ($masks.ContainsKey($mi)) { $masks[$slot] = $masks[$mi] }
        }
        $slotMap[$slot] = $mi
        $e = $mc["$want|$mi"]
        if (-not $e) { $e = $mc["$(if ($want -eq 'L') { 'M' } else { 'L' })|$mi"] }
        if (-not $e) { continue }
        if ($e.params.ContainsKey('BaseTint')) {
            $bt = $e.params['BaseTint']
            if ([Math]::Abs($bt[0] - 1) + [Math]::Abs($bt[1] - 1) + [Math]::Abs($bt[2] - 1) -gt 0.003) {
                $tints[$slot] = @([Math]::Min(4, $bt[0]), [Math]::Min(4, $bt[1]), [Math]::Min(4, $bt[2]))
            }
        }
        $mask = $masks[$slot]
        $diffName = $matmap[$slot]
        if (-not $mask -or -not $diffName -or -not $relOf.ContainsKey($mask)) { continue }
        $maskPng = Join-Path $pngRoot $relOf[$mask]
        if (-not (Test-Path -LiteralPath $maskPng)) { continue }
        $block = SS-ViewDyeBlock $e.params
        if (-not ($block | Where-Object { $_ -ne 0 })) { continue }
        # her rule, 2026-09-24: texture edits WIN over the dye. The game (live
        # preview and built mods) now gets a blank mask for a dyed material whose
        # D she edits, with the dye baked into the VANILLA map and her edits laid
        # on top - so draw it the same way here (dyebake.ps1 is the game side)
        $dRelV = $relOf[[IO.Path]::GetFileNameWithoutExtension($diffName)]
        $opD = if ($ops -and $dRelV -and $ops.ContainsKey($dRelV)) { $ops[$dRelV] } else { $null }
        if ($opD) {
            # every material drawing this D shows the SAME baked map in game,
            # made with the D's own material's (match) dye - e.g. the fur shell
            # MI_x_Equip_04 shows MI_x_Equip_01's palette under her edits
            $ownerMi = 'MI_' + ([IO.Path]::GetFileNameWithoutExtension($diffName) -replace '^T_', '' -replace '_D$', '')
            $oe = $mc["M|$ownerMi"]; if (-not $oe) { $oe = $mc["L|$ownerMi"] }
            if ($oe) { $ob = SS-ViewDyeBlock $oe.params; if ($ob | Where-Object { $_ -ne 0 }) { $block = $ob } }
        }
        $outName = $slot + '__dye.png'
        $key = $(if ($opD) { 'dyeop:' } else { 'dye:' }) + (SS-ViewHash (($block -join ',') + '|' + $now[$diffName] + '|' + (Get-Item -LiteralPath $maskPng).LastWriteTimeUtc.Ticks))
        $now[$outName] = $key
        $outPng = Join-Path $td $outName
        if (-not ((Test-Path -LiteralPath $outPng) -and $prev[$outName] -eq $key)) {
            if ($opD) {
                $vanTmp = Join-Path $td ('_van_' + $outName)
                $dyeTmp = Join-Path $td ('_dyed_' + $outName)
                try {
                    [ViewArt]::Shrink((Join-Path $pngRoot $dRelV), $vanTmp, $SS_ViewMax)
                    [void][ViewArt]::DyeComposite($vanTmp, $maskPng, $dyeTmp, $block, $SS_ViewMax)
                    $bOn = SS-RenderStack $dyeTmp $opD
                    try { $bOn.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bOn.Dispose() }
                } finally {
                    foreach ($f in @($vanTmp, $dyeTmp)) { if (Test-Path -LiteralPath $f) { [IO.File]::Delete($f) } }
                }
            } else {
                [void][ViewArt]::DyeComposite((Join-Path $td $diffName), $maskPng, $outPng, $block, $SS_ViewMax)
            }
        }
        $matmap[$slot] = $outName
        $dyed++
    }

    # drop maps that no longer belong (plain files we wrote)
    foreach ($f in (Get-ChildItem -LiteralPath $td -File -Filter *.png -ErrorAction SilentlyContinue)) {
        if (-not $now.ContainsKey($f.Name)) { $f.Delete() }
    }
    [IO.File]::WriteAllText($srcF, ($now | ConvertTo-Json -Depth 3))

    $texVer = @{}
    foreach ($k in $now.Keys) { $texVer[$k] = [string](Get-Item -LiteralPath (Join-Path $td $k)).LastWriteTimeUtc.Ticks }
    $rootLen = $SS_Root.TrimEnd('\').Length + 1
    $scene = [ordered]@{
        skin    = $skin
        title   = $title
        rev     = [DateTime]::UtcNow.Ticks
        glb     = $glb.Substring($rootLen) -replace '\\', '/'
        texBase = ($td.Substring($rootLen) -replace '\\', '/') + '/'
        tex     = $texVer
        matmap  = $matmap
        tints   = $tints
        note    = $(if ($dyed) { "$dyed dyed material(s) shown flat, as the game paints them" } else { '' })
    }
    $sf = Join-Path $vd 'scene.json'
    [IO.File]::WriteAllText($sf, ($scene | ConvertTo-Json -Depth 5))
    & $say ("3D preview: {0} maps ({1} re-baked), {2} dyed, {3} tinted" -f $n, $done, $dyed, $tints.Count)
    $sf.Substring($rootLen) -replace '\\', '/'
}

# ---- the window -------------------------------------------------------------
$script:SS_ViewForm = $null
$script:SS_ViewWeb = $null
$script:SS_ViewPending = $null      # scene url waiting for the page to be ready
$script:SS_ViewReady = $false

function SS-ViewLoadTypes {
    if ('Microsoft.Web.WebView2.WinForms.WebView2' -as [type]) { return }
    $lib = Join-Path $SS_ViewRoot 'lib'
    # WebView2Loader.dll is found next to Core.dll; put that folder on PATH too
    # in case the loader probes the process directory instead
    if ($env:PATH -notlike "*$lib*") { $env:PATH = "$lib;$env:PATH" }
    Add-Type -Path (Join-Path $lib 'Microsoft.Web.WebView2.Core.dll')
    Add-Type -Path (Join-Path $lib 'Microsoft.Web.WebView2.WinForms.dll')
}

function SS-ViewSend([string]$sceneUrl) {
    $msg = '{"cmd":"load","scene":"' + $sceneUrl + '"}'
    if ($script:SS_ViewReady -and $script:SS_ViewWeb -and $script:SS_ViewWeb.CoreWebView2) {
        $script:SS_ViewWeb.CoreWebView2.PostWebMessageAsString($msg)
    } else {
        $script:SS_ViewPending = $sceneUrl
    }
}

# Open (or bring forward) the preview window and show $sceneUrl in it.
# $Owner keeps it above the studio; -Headless is for the smoke test.
function Show-3DPreview([string]$sceneUrl, $Owner, [string]$Title = 'Skin Studio 3D', [switch]$Headless) {
    SS-ViewLoadTypes
    if ($script:SS_ViewForm -and -not $script:SS_ViewForm.IsDisposed) {
        $script:SS_ViewForm.Text = $Title
        SS-ViewSend $sceneUrl
        if (-not $Headless) { $script:SS_ViewForm.Activate() }
        return $script:SS_ViewForm
    }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.Size = New-Object System.Drawing.Size(720, 900)
    $f.StartPosition = 'Manual'
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $f.Location = New-Object System.Drawing.Point([Math]::Max(0, $wa.Right - 740), [Math]::Max(0, $wa.Top + 40))
    $f.BackColor = [System.Drawing.Color]::FromArgb(29, 33, 30)
    if ($Headless) { $f.ShowInTaskbar = $false; $f.StartPosition = 'Manual'; $f.Location = New-Object System.Drawing.Point(-4000, -4000) }
    $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $wv.Dock = 'Fill'
    $wv.DefaultBackgroundColor = [System.Drawing.Color]::FromArgb(29, 33, 30)
    $cp = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    # the default user-data folder is next to powershell.exe (Program Files) -
    # unwritable, and WebView2 then fails to start with no useful message
    $cp.UserDataFolder = Join-Path $SS_Root 'work\webview2'
    $wv.CreationProperties = $cp
    $f.Controls.Add($wv)
    $script:SS_ViewForm = $f
    $script:SS_ViewWeb = $wv
    $script:SS_ViewReady = $false
    $script:SS_ViewPending = $sceneUrl
    $wv.Add_CoreWebView2InitializationCompleted({
        param($s, $e)
        if (-not $e.IsSuccess) {
            [void][System.Windows.Forms.MessageBox]::Show('The 3D preview could not start WebView2: ' + $e.InitializationException.Message, 'Skin Studio 3D')
            return
        }
        $c = $s.CoreWebView2
        $c.SetVirtualHostNameToFolderMapping('skinstudio.local', $SS_Root, [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow)
        $c.Settings.AreDevToolsEnabled = $true
        $c.Settings.IsStatusBarEnabled = $false
        $c.Settings.AreDefaultContextMenusEnabled = $false
        $c.Add_WebMessageReceived({
            param($s2, $e2)
            $m = $null
            try { $m = $e2.TryGetWebMessageAsString() | ConvertFrom-Json } catch {}
            if (-not $m) { return }
            if ($m.ev -eq 'ready') {
                $script:SS_ViewReady = $true
                if ($script:SS_ViewPending) { $p = $script:SS_ViewPending; $script:SS_ViewPending = $null; SS-ViewSend $p }
            } elseif ($m.ev -eq 'loaded') {
                $script:SS_ViewLast = $m
            } elseif ($m.ev -eq 'error') {
                $script:SS_ViewLast = $m
            }
        })
        $c.Navigate('https://skinstudio.local/viewer/index.html')
    })
    $f.Add_FormClosed({ $script:SS_ViewForm = $null; $script:SS_ViewWeb = $null; $script:SS_ViewReady = $false })
    if ($Owner) { $f.Owner = $Owner }
    $f.Show()
    [void]$wv.EnsureCoreWebView2Async($null)
    $f
}
