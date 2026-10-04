# ============================================================================
# Assemble SkinStudio\vuistyle.ps1 from Variant UI's chrome.
#
# The look is not re-implemented here - the proven blocks are LIFTED out of
# C:\rs\ThemeStudio\ThemeStudio.ps1 line-for-line, and only the accent colour
# and a handful of app-specific strings are rewritten on the way through. That
# way a fix made over in Variant UI (a painting landmine, a new control type in
# StyleTree) ports here by re-running this script instead of by hand.
#
# Run it from a SHORT path - PS 5.1 cannot execute a .ps1 sitting past ~260
# characters (it reports a bogus "missing terminator").
#
#   powershell -NoProfile -ExecutionPolicy RemoteSigned -File C:\rs\SkinStudio\build-vuistyle.ps1
#
# The three hand-written pieces (palette, type/branding, brand band + status
# bar) live in vuistyle.parts\ next to this script. They are NOT put through
# the pink->sage rename - they are written in sage already, and they talk about
# the pink original on purpose.
# ============================================================================
$ErrorActionPreference = 'Stop'
$src   = 'C:\rs\ThemeStudio\ThemeStudio.ps1'
$parts = Join-Path $PSScriptRoot 'vuistyle.parts'
$out   = Join-Path $PSScriptRoot 'vuistyle.ps1'

$lines = [System.IO.File]::ReadAllLines($src, [System.Text.Encoding]::UTF8)
"read $src  ($($lines.Count) lines)"

# 1-based, inclusive - the exact blocks, with a one-line note on each
$blocks = @(
  @{ From=78;   To=109;  What='HSV helpers (the colour picker square needs HSV, not HSL)' }
  @{ From=164;  To=185;  What='PickScreenColor - the eyedropper' }
  @{ From=343;  To=563;  What='rounded / gradient painting: RoundControl, cards, sinks' }
  @{ From=564;  To=954;  What='VuiSlider + VuiCombo (our own slider and drop-down)' }
  @{ From=976;  To=1056; What='control factories: AddLabel / AddButton / MakePrimary / ...' }
  @{ From=1057; To=1157; What='StyleTree - one pass that dresses every control' }
  @{ From=1159; To=1455; What='VuiColorDialog - the studio colour picker' }
  @{ From=1854; To=1909; What='dark title bar + dark scrollbars' }
)
# sanity: each block must still start where it did when this was written
$anchors = [ordered]@{
  78='# ---- HSV'; 164='function PickScreenColor'; 343='# ---- rounded / gradient painting'
  564='# ---- sliders and drop-downs'; 976='function AddLabel'; 1057='# ---- StyleTree'
  1159='# ---- the colour picker'; 1854='# ---- window chrome'
}
foreach($k in $anchors.Keys){
  if(-not $lines[$k-1].StartsWith($anchors[$k])){
    throw "ThemeStudio.ps1 has moved: line $k is '$($lines[$k-1])', expected '$($anchors[$k])...'. Re-pin the block ranges."
  }
}

# ---- the lifted half --------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
foreach($b in $blocks){
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine(("# vvv lifted from ThemeStudio.ps1 lines {0}-{1}: {2}" -f $b.From,$b.To,$b.What))
  for($i=$b.From; $i -le $b.To; $i++){ [void]$sb.AppendLine($lines[$i-1]) }
}
$lift = $sb.ToString()

# the accent. Order matters: the suffixed keys go first or "Pink" eats their
# prefix. -creplace throughout - PowerShell's -replace is CASE-INSENSITIVE, so
# 'PINK','SAGE' would also swallow "Pink" and "pink" and shout them back.
$lift = $lift -creplace '\$Pal\.PinkLt','$Pal.SageLt'
$lift = $lift -creplace '\$Pal\.PinkDk','$Pal.SageDk'
$lift = $lift -creplace '\$Pal\.PinkWash','$Pal.SageWash'
$lift = $lift -creplace '\$Pal\.Pink','$Pal.Sage'
# prose too, so the comments describe the app they are now in. Audited before
# this was written: every remaining "pink" in these blocks is a comment - no
# identifier, no C# member, no string the user ever sees.
$lift = $lift -creplace 'PINK','SAGE'
$lift = $lift -creplace 'Pink','Sage'
$lift = $lift -creplace 'pink','sage'

# ---- app-specific fixes -----------------------------------------------------
# white on sage is 2.0:1 - unreadable. Near-black on sage is 8.5:1.
$lift = $lift.Replace('$b.BackColor=$Pal.Sage; $b.ForeColor=[System.Drawing.Color]::White',
                      '$b.BackColor=$Pal.Sage; $b.ForeColor=$Pal.Bg')
$lift = $lift.Replace('$b.FlatAppearance.MouseOverBackColor=[System.Drawing.Color]::FromArgb(220,124,184)',
                      '$b.FlatAppearance.MouseOverBackColor=$Pal.SageHi')
# A disabled button goes GREY here rather than a dimmed copy of its own colour.
# Dimming works for Variant UI's pink, which lands somewhere dark; dimming a
# LIGHT sage lands on a mid-tone that still reads as "press me", and the faint
# grey label on top of it is nearly invisible. Greys keep their old behaviour -
# the saturation test is what tells an accent fill from a panel fill.
$lift = $lift.Replace('  if(-not $s.Enabled){ $fill=PalDim $s.BackColor 0.72 }',
                      '  if(-not $s.Enabled){ $fill=if($s.BackColor.GetSaturation() -gt 0.12){ $Pal.Panel2 } else { PalDim $s.BackColor 0.72 } }')
# VuiColorDialog owns its modal to Variant UI's $form by name. Over here the
# main window is $frm, and a module cannot know what the app called it - so it
# goes through the owner the app registers with Set-VuiOwner.
$lift = $lift.Replace('$res=$f.ShowDialog($form)',
                      '$res=$f.ShowDialog($script:VuiOwnerForm)')
# DressDialog borrowed the main form's font by name; this module owns one
$lift = $lift.Replace('try { $f.Font=$form.Font } catch {}',
                      'try { $f.Font=$script:VuiBaseFont } catch {}')
# the loud button is called something else over here, and there are no tabs,
# no engine toggles and no template lists in this studio
$lift = $lift.Replace("the sage GENERATE`r`n# button and the amber warning button do that",
                      "the sage BUILD MOD`r`n# button does that")
$lift = $lift.Replace('quiet grey buttons so the sage ones (GENERATE, starters) read as the actions',
                      'quiet grey buttons so the sage ones (BUILD MOD, OPEN SKIN) read as the actions')
$lift = $lift.Replace('quiet navy buttons so the sage ones (GENERATE, starters) read as the actions',
                      'quiet grey buttons so the sage ones (BUILD MOD, OPEN SKIN) read as the actions')
$lift = $lift.Replace('applies the navy/sage','applies the grey/sage')
$lift = $lift.Replace('runtime (engine toggles, template lists)','runtime (the layer stack, the dialogs)')
$lift = $lift.Replace('same as the active tab and the section chevrons.',
                      'same as the browse mode you are in and the button that commits.')
$lift = $lift.Replace('the sage ones (GENERATE, starters)','the sage ones (BUILD MOD, OPEN SKIN)')
$lift = $lift.Replace('the studio is thousands of lines','the studio is a thousand-odd lines')

# nothing lifted may still say pink
$stray = ([regex]'(?i)pink').Matches($lift).Count
if($stray -gt 0){ throw "$stray occurrences of 'pink' survived the rename" }
# and nothing may still name GENERATE, which does not exist in this app
if($lift -match 'GENERATE'){ throw "a lifted comment still refers to GENERATE" }

# ---- the hand-written half, either side -------------------------------------
$t = ([System.IO.File]::ReadAllText((Join-Path $parts 'palette.ps1'),[System.Text.Encoding]::UTF8)) +
     ([System.IO.File]::ReadAllText((Join-Path $parts 'type.ps1'),[System.Text.Encoding]::UTF8)) +
     $lift +
     ([System.IO.File]::ReadAllText((Join-Path $parts 'brandband.ps1'),[System.Text.Encoding]::UTF8))

# every $Pal key the assembled module reaches for must exist in the palette part
$defined = @{}
foreach($m in ([regex]'(?m)^\s{2}(\w+)\s*=\s*\[System\.Drawing\.Color\]').Matches($t)){ $defined[$m.Groups[1].Value] = $true }
$missing = @()
foreach($m in ([regex]'\$Pal\.(\w+)').Matches($t)){
  $k = $m.Groups[1].Value
  if(-not $defined.ContainsKey($k) -and $missing -notcontains $k){ $missing += $k }
}
if($missing.Count){ throw ("palette has no key(s): {0}" -f ($missing -join ', ')) }

# ---- no dangling references -------------------------------------------------
# The failure mode of lifting line RANGES is a reference that reached outside its
# range into a Theme Studio global. That is how the colour picker shipped broken
# the first time: it uses $tt (Variant UI's shared ToolTip) and owns its modal to
# $form, both declared just above the range. Neither is a parse error - you find
# out when a user clicks the button.
#
# So every command and variable the assembled module uses has to resolve, in its
# OWN scope. Scope matters: bind parameters globally and AddStatusBar($form,...)
# makes an unrelated function's $form look satisfied.
$mErrs = $null
$mAst = [System.Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$mErrs)
if ($mErrs -and $mErrs.Count) { $mErrs | ForEach-Object { "PARSE: $($_.Extent.StartLineNumber): $($_.Message)" }; throw 'assembled module does not parse' }
function AllOf($root, $type) { $root.FindAll({ param($n) $n -is $type }, $true) }
function Norm([string]$n) { ($n -replace '^(script|global|local|private):', '').ToLower() }
function InsideAFunction($node) {
    $p = $node.Parent
    while ($p) {
        if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $true }
        $p = $p.Parent
    }
    return $false
}
$mFuncs = AllOf $mAst ([System.Management.Automation.Language.FunctionDefinitionAst])
$mDefined = @{}; foreach ($f in $mFuncs) { $mDefined[$f.Name] = $true }
$bad = @()
foreach ($c in (AllOf $mAst ([System.Management.Automation.Language.CommandAst]))) {
    $n = $c.GetCommandName()
    if (-not $n -or $mDefined.ContainsKey($n)) { continue }
    if (Get-Command -Name $n -ErrorAction SilentlyContinue) { continue }
    $bad += ('line {0}: command {1}' -f $c.Extent.StartLineNumber, $n)
}
$auto = @('_','this','args','matches','true','false','null','psitem','error','input',
          'psscriptroot','pscmdlet','myinvocation','host','pwd','home','profile',
          'lastexitcode','pid','psversiontable','ofs','stacktrace','foreach','switch',
          'executioncontext','psboundparameters','shellid','consolefilename','nestedpromptlevel')
$mGlobals = @{}
foreach ($a in (AllOf $mAst ([System.Management.Automation.Language.AssignmentStatementAst]))) {
    if ((InsideAFunction $a) -and ($a.Left.Extent.Text -notmatch '^\$script:')) { continue }
    foreach ($v in (AllOf $a.Left ([System.Management.Automation.Language.VariableExpressionAst]))) {
        $mGlobals[(Norm $v.VariablePath.UserPath)] = $true
    }
}
function CheckScope($root, $label) {
    $bound = @{}
    foreach ($a in $auto) { $bound[$a] = $true }
    foreach ($k in $mGlobals.Keys) { $bound[$k] = $true }
    foreach ($p in (AllOf $root ([System.Management.Automation.Language.ParameterAst]))) { $bound[(Norm $p.Name.VariablePath.UserPath)] = $true }
    foreach ($a in (AllOf $root ([System.Management.Automation.Language.AssignmentStatementAst]))) {
        foreach ($v in (AllOf $a.Left ([System.Management.Automation.Language.VariableExpressionAst]))) { $bound[(Norm $v.VariablePath.UserPath)] = $true }
    }
    foreach ($fe in (AllOf $root ([System.Management.Automation.Language.ForEachStatementAst]))) { $bound[(Norm $fe.Variable.VariablePath.UserPath)] = $true }
    foreach ($v in (AllOf $root ([System.Management.Automation.Language.VariableExpressionAst]))) {
        $n = Norm $v.VariablePath.UserPath
        if ($bound.ContainsKey($n)) { continue }
        $script:bad += ('line {0}: ${1} in {2}' -f $v.Extent.StartLineNumber, $v.VariablePath.UserPath, $label)
    }
}
foreach ($f in $mFuncs) { CheckScope $f $f.Name }
foreach ($st in $mAst.EndBlock.Statements) {
    if ($st -is [System.Management.Automation.Language.FunctionDefinitionAst]) { continue }
    CheckScope $st '<script level>'
}
if ($bad.Count) {
    $bad | Sort-Object -Unique | ForEach-Object { "  UNRESOLVED: $_" }
    throw "$($bad.Count) unresolved reference(s) in the assembled module - a lifted block reached outside its range"
}
"no dangling references."

# UTF-8 WITH BOM: PS 5.1 reads a BOM-less file as ANSI, and the degree signs and
# arrows in the lifted blocks come back as mojibake
[System.IO.File]::WriteAllText($out,$t,(New-Object System.Text.UTF8Encoding($true)))
"wrote $out  ($((Get-Content -LiteralPath $out).Count) lines)"

# parse-check what we just built
$errs=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($out,[ref]$null,[ref]$errs)
if($errs -and $errs.Count){ $errs | ForEach-Object { "PARSE: $($_.Extent.StartLineNumber): $($_.Message)" }; throw "vuistyle.ps1 does not parse" }
"parses clean."
