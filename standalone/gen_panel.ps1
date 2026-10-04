# gen_panel.ps1 - the standalone Skin Studio panel (F8) (WBP_SkinStudioPanel) and
# its bootstrap (WBP_SkinStudioStandaloneBoot01), as clipboard T3D for UE 5.3.
#
#   .\gen_panel.ps1  -> D:\SkinStudioProbeUE\paste\
#       vars_*.txt        one BPVar per file, pasted into My Blueprint
#       panel_1..7.txt    the panel's graph, by dependency level
#       boot.txt          the bootstrap's graph (after the panel compiles)
#
# Everything the probe proved (2026-09-26) is reused: the SaveGame class with a
# pasted String field, the 1 s looping timer, MID vector params, reset from the
# MID's parent. The data is one string in slot SkinStudioColors:
#     <MI name>|<param>|r,g,b;<MI name>|<param>|r,g,b;...
# keyed by the material instance NAME, so it is per skin by construction.
#
# * Paste in order with a Compile between: a call to one of our own events that
# is not compiled yet loses its exec wires (ESaveOrphanPinMode::SaveAllButExec).
#   1  LoadEdits SaveEdits ApplyParam Say           (call nothing of ours)
#   2  Reapply RefreshPicker RefreshRows             (call level 1)
#   3  SelectRow PickColor ResetOne ResetPart        (levels 1-2)
#   4  SelectPart ResetAll + slider/swatch/row/reset handlers
#   5  Refresh + part buttons + Reset hero button
#   6  Open Close
#   7  Toggle + Close button
#   8  Studio button (opens the app panel)
#   9  Build mod button (colours -> zip in Downloads, via the helper)
#  10  MarkDirty
#  11  LoadDesign
#  12  named designs: SaveDesign, Delete, the list (D0..D47)
#  13  Save + Open in App buttons (call SaveDesign)
param([string]$Out = 'D:\SkinStudioProbeUE\paste')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 't3dlib.ps1')

# * t3dlib holds $GS $KM $KS $KSt $KR $WL $WB $SL $UW $WG $MIC $MID $G ... and
# PowerShell names are case-insensitive: every local here is n/z-prefixed.

# wider node-name ranges than t3dlib's (these pastes are big and share a graph)
function Add-Node([string]$class, [string[]]$props, [int]$x, [int]$y) {
    $short = $class.Substring($class.LastIndexOf('.') + 1)
    $k = [int]$script:G.Count[$short]; $script:G.Count[$short] = $k + 1
    $n = @{ Name = ('{0}_{1}' -f $short, (100000 * $script:G.Tag + $k)); Class = $class; Props = @($props); X = $x; Y = $y
            Guid = (New-Guid32); Pins = [ordered]@{}; Extra = @() }
    [void]$script:G.Nodes.Add($n)
    $n
}

$WDir       = '/Game/Marvel/SkinLive/UI/Widgets'
$PanelName  = 'WBP_SkinStudioPanel'
$PanelClass = "$WDir/$PanelName.${PanelName}_C"
$PanelRef   = "WidgetBlueprintGeneratedClass'`"$PanelClass`"'"
$SaveClass  = "$WDir/SkinStudioSave.SkinStudioSave_C"
$ColorSlot  = 'SkinStudioColors'
$LC         = 'struct:/Script/CoreUObject.LinearColor'
$TA         = '/Script/UMG.TextBlock'
$BT         = '/Script/UMG.Button'
$SLD        = '/Script/UMG.Slider'
$KT         = '/Script/Engine.KismetTextLibrary'
$PC_        = '/Script/Engine.PrimitiveComponent'

# rows 0-8: one colour; rows 9-15: dye zones 1-7, side 0 = ColorA (dark), 1 = ColorB (light)
$RowParams = @('BaseTint', 'MC_Shade', 'ExtraSpecularTint', 'RimLightColor', 'BackRimColor', 'EmissiveColor', 'Emissive_Color0', 'IrisBaseColorMulti', 'ScleraTint')
$AllParams = @($RowParams) + @(foreach ($z in 1..7) { "Region $z - ColorA"; "Region $z - ColorB" })
$ParamTable = $AllParams -join '|'

$Inv = [Globalization.CultureInfo]::InvariantCulture
function Lin-Color([string]$hex) {
    $c = foreach ($i in 0, 2, 4) {
        $v = [Convert]::ToInt32($hex.Substring($i, 2), 16) / 255.0
        if ($v -le 0.04045) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) }
    }
    [string]::Format($Inv, '(R={0:F6},G={1:F6},B={2:F6},A=1.000000)', $c[0], $c[1], $c[2])
}
$ColBtn  = Lin-Color '39443A'
$ColCard = Lin-Color '2A332B'
$ColSel  = Lin-Color '5E7A5C'
$Palette = @('FFFFFF', 'E8E1D5', 'C9B8A6', '8C6E57', '4A3A30', '1E1B19',
             'DCE8D5', 'A9C4A0', '6F8F68', '3F5A43', '9BC9C2', '3E7C80',
             'F6D6DE', 'E9A6B8', 'C45C7A', 'F3C9A5', 'F2E2A0', 'CDB8E6',
             'D93B3B', 'F08A24', 'F2C94C', '3FA34D', '2F80ED', '8E44AD')

# ---------------------------------------------------------------- small makers
function Get-Var([string]$v, [int]$x, [int]$y) { GetMember $v $x $y }
function Set-Var($nFrom, [string]$nPin, [string]$v, $nSrc, [string]$nSrcPin, [int]$x, [int]$y) {
    $n = Add-Node '/Script/BlueprintGraph.K2Node_VariableSet' @("VariableReference=(MemberName=`"$v`",bSelfContext=True)") $x $y
    Wire $nFrom $nPin $n 'execute'
    Wire $nSrc $nSrcPin $n $v
    $n
}
function Set-VarLit($nFrom, [string]$nPin, [string]$v, [string]$type, [string]$value, [int]$x, [int]$y) {
    $n = Add-Node '/Script/BlueprintGraph.K2Node_VariableSet' @("VariableReference=(MemberName=`"$v`",bSelfContext=True)") $x $y
    Wire $nFrom $nPin $n 'execute'
    Def $n $v $type $value
    $n
}
# a call on one of the panel's own widgets
function Call-On([string]$wvar, [string]$cls, [string]$fn, [int]$x, [int]$y) {
    $nv = GetMember $wvar $x ($y + 140)
    $nc = Call $cls $fn ($x + 200) $y
    Wire $nv $wvar $nc 'self'
    $nc
}
function Set-Str($n, [string]$pin, $src) {
    if ($src -is [string]) { Def $n $pin 'string' $src } else { Wire $src[0] $src[1] $n $pin }
}
function Set-Col($n, [string]$pin, $src) {
    if ($src -is [string]) { Def $n $pin $LC $src } else { Wire $src[0] $src[1] $n $pin }
}
function Set-TextOf($nFrom, [string]$nPin, [string]$wvar, $src, [int]$x, [int]$y) {
    $ncv = Call $KT 'Conv_StringToText' $x ($y + 240)
    Set-Str $ncv 'InString' $src
    $nc = Call-On $wvar $TA 'SetText' $x $y
    Wire $nFrom $nPin $nc 'execute'; Wire $ncv 'ReturnValue' $nc 'InText'
    $nc
}
function Set-BtnColor($nFrom, [string]$nPin, [string]$wvar, $src, [int]$x, [int]$y) {
    $nc = Call-On $wvar $BT 'SetBackgroundColor' $x $y
    Wire $nFrom $nPin $nc 'execute'; Set-Col $nc 'InBackgroundColor' $src
    $nc
}
function Get-ArrItem($nArr, [string]$nArrPin, $idx, [int]$x, [int]$y) {
    $n = Add-Node '/Script/BlueprintGraph.K2Node_GetArrayItem' @() $x $y
    Wire $nArr $nArrPin $n 'Array'
    if ($idx -is [int]) { Def $n 'Dimension 1' 'int' ([string]$idx) } else { Wire $idx[0] $idx[1] $n 'Dimension 1' }
    $n
}
function Arr-Call([string]$fn, [string]$var, [int]$x, [int]$y) {
    $nv = Get-Var $var $x ($y + 140)
    $nc = CallArray $fn ($x + 200) $y
    Wire $nv $var $nc 'TargetArray'
    $nc
}
function Math2([string]$fn, $a, $b, [int]$x, [int]$y, [string]$ta = 'int') {
    $n = Call $KM $fn $x $y
    if ($a -is [array]) { Wire $a[0] $a[1] $n 'A' } else { Def $n 'A' $ta ([string]$a) }
    if ($b -is [array]) { Wire $b[0] $b[1] $n 'B' } else { Def $n 'B' $ta ([string]$b) }
    $n
}
function Parse-Color($nSrc, [string]$nSrcPin, [int]$x, [int]$y) {
    $npa = Call $KSt 'ParseIntoArray' $x $y; Wire $nSrc $nSrcPin $npa 'SourceString'
    Def $npa 'Delimiter' 'string' ','; Def $npa 'CullEmptyStrings' 'bool' 'true'
    $nmc = Call $KM 'MakeColor' ($x + 700) $y; Def $nmc 'A' 'float' '1.000000'
    $k = 0
    foreach ($ch in @('R', 'G', 'B')) {
        $ngi = Get-ArrItem $npa 'ReturnValue' $k ($x + 250) ($y + 110 * $k)
        $ncd = Call $KSt 'Conv_StringToDouble' ($x + 450) ($y + 110 * $k); Wire $ngi 'Output' $ncd 'InString'
        Wire $ncd 'ReturnValue' $nmc $ch
        $k++
    }
    $nmc
}
# the selected part is a real index into PartMICs
function Sel-Valid([int]$x, [int]$y) {
    $nsp = Get-Var 'SelPart' $x $y
    $nge = Math2 'GreaterEqual_IntInt' @($nsp, 'SelPart') 0 ($x + 200) $y
    $nln = Arr-Call 'Array_Length' 'PartMICs' $x ($y + 120)
    $nlt = Math2 'Less_IntInt' @($nsp, 'SelPart') @($nln, 'ReturnValue') ($x + 400) ($y + 120)
    $nan = Call $KM 'BooleanAND' ($x + 600) $y; Wire $nge 'ReturnValue' $nan 'A'; Wire $nlt 'ReturnValue' $nan 'B'
    $nan
}
function Sel-Mic([int]$x, [int]$y) {
    Get-ArrItem (Get-Var 'PartMICs' $x ($y + 100)) 'PartMICs' @((Get-Var 'SelPart' $x ($y + 200)), 'SelPart') ($x + 200) $y
}
# "<SelMic>|<param>" -> the edit's index (pure; re-evaluates on every use)
function Edit-Index($nParamStr, [int]$x, [int]$y) {
    $nkey = Concat-Chain @(@((Get-Var 'SelMic' $x ($y + 120)), 'SelMic'), '|', $nParamStr) $x $y
    $nfi = Arr-Call 'Array_Find' 'EditKeys' ($x + 700) $y; Wire $nkey 'ReturnValue' $nfi 'ItemToFind'
    @{ Key = $nkey; Find = $nfi }
}
# the colour a row shows: the edit if there is one, else the vanilla value $nVan
function Cur-Color($nParamStr, $nVan, [string]$nVanPin, [int]$x, [int]$y) {
    $ei = Edit-Index $nParamStr $x $y
    $nec = Get-ArrItem (Get-Var 'EditColors' ($x + 900) ($y + 100)) 'EditColors' @($ei.Find, 'ReturnValue') ($x + 1100) $y
    $nhas = Math2 'GreaterEqual_IntInt' @($ei.Find, 'ReturnValue') 0 ($x + 1100) ($y + 120)
    $nsc = Call $KM 'SelectColor' ($x + 1300) $y
    Wire $nec 'Output' $nsc 'A'; Wire $nVan $nVanPin $nsc 'B'; Wire $nhas 'ReturnValue' $nsc 'bPickA'
    $nsc
}
# text inside a Button: Buttons are variables by default, TextBlocks are not
function Set-BtnText($nFrom, [string]$nPin, [string]$btn, $src, [int]$x, [int]$y) {
    $nv = GetMember $btn $x ($y + 140)
    $ngc = Call '/Script/UMG.ContentWidget' 'GetContent' ($x + 150) ($y + 140); Wire $nv $btn $ngc 'self'
    $nct = Cast '/Script/UMG.TextBlock' ($x + 300) $y; Wire $nFrom $nPin $nct 'execute'; Wire $ngc 'ReturnValue' $nct 'Object'
    $ncv = Call $KT 'Conv_StringToText' ($x + 300) ($y + 260)
    Set-Str $ncv 'InString' $src
    $nst = Call $TA 'SetText' ($x + 550) $y; Wire $nct 'then' $nst 'execute'; Wire $nct 'AsText' $nst 'self'; Wire $ncv 'ReturnValue' $nst 'InText'
    $nst
}
# visibility of a (non-variable) row, through its label Button's parent
function Set-VisParentOf($nFrom, [string]$nPin, [string]$child, [string]$want, [int]$x, [int]$y) {
    $nv = GetMember $child $x ($y + 140)
    $ngp = Call $WG 'GetParent' ($x + 150) ($y + 140); Wire $nv $child $ngp 'self'
    $ns = Call $WG 'SetVisibility' ($x + 300) $y; Wire $nFrom $nPin $ns 'execute'; Wire $ngp 'ReturnValue' $ns 'self'
    Def $ns 'InVisibility' $VisEnum $want
    $ns
}
function Bound-Event([string]$wvar, [string]$ownerCls, [string]$delegate, [string]$sig, [int]$x, [int]$y) {
    $k = [int]$script:G.Count['K2Node_ComponentBoundEvent']
    Add-Node '/Script/BlueprintGraph.K2Node_ComponentBoundEvent' @(
        "DelegatePropertyName=`"$delegate`"",
        "DelegateOwnerClass=Class'`"$ownerCls`"'",
        "ComponentPropertyName=`"$wvar`"",
        "EventReference=(MemberParent=Package'`"/Script/UMG`"',MemberName=`"$sig`")",
        'bInternalEvent=True',
        ("CustomFunctionName=`"BndEvt__{0}_{1}_K2Node_ComponentBoundEvent_{2}_{3}`"" -f $PanelName, $wvar, (100 * $script:G.Tag + $k), $sig)) $x $y
}
function On-Click([string]$btn, [int]$x, [int]$y) { Bound-Event $btn $BT 'OnClicked' 'OnButtonClickedEvent__DelegateSignature' $x $y }
function On-Pressed([string]$btn, [int]$x, [int]$y) { Bound-Event $btn $BT 'OnPressed' 'OnButtonPressedEvent__DelegateSignature' $x $y }
function On-Released([string]$btn, [int]$x, [int]$y) { Bound-Event $btn $BT 'OnReleased' 'OnButtonReleasedEvent__DelegateSignature' $x $y }

# every material slot of every skeletal mesh on the pawn's attached actors (the
# walk the working F6 uses). $body gets (exec node, pin, mesh comp node, pin,
# loop node for Index, x, y). Returns the Branch (else = no pawn) and the
# actor loop (Completed = done).
function Walk-Slots($nFrom, [string]$nPin, [scriptblock]$body, [int]$x, [int]$y) {
    $npp = Call $GS 'GetPlayerPawn' $x ($y + 160); Def $npp 'PlayerIndex' 'int' '0'
    $nvp = Call $KS 'IsValid' ($x + 200) ($y + 160); Wire $npp 'ReturnValue' $nvp 'Object'
    $nbp = Branch ($x + 260) $y; Wire $nFrom $nPin $nbp 'execute'; Wire $nvp 'ReturnValue' $nbp 'Condition'
    $nga = Call '/Script/Engine.Actor' 'GetAttachedActors' ($x + 300) ($y + 320); Wire $npp 'ReturnValue' $nga 'self'
    Def $nga 'bResetArray' 'bool' 'true'; Def $nga 'bRecursivelyIncludeAttachedActors' 'bool' 'true'
    $nl1 = ArrayLoop $nga 'OutActors' ($x + 500) $y
    Wire $nbp 'then' $nl1.Loop 'execute'
    $ngc = Call '/Script/Engine.Actor' 'K2_GetComponentsByClass' ($x + 1200) ($y + 320); Wire $nl1.Item 'Output' $ngc 'self'
    Def $ngc 'ComponentClass' 'class:/Script/Engine.ActorComponent' '/Script/Engine.SkeletalMeshComponent'
    $nl2 = ArrayLoop $ngc 'ReturnValue' ($x + 1500) $y
    Wire $nl1.Loop 'LoopBody' $nl2.Loop 'execute'
    $nca = Cast '/Script/Engine.SkeletalMeshComponent' ($x + 2200) $y
    Wire $nl2.Loop 'LoopBody' $nca 'execute'; Wire $nl2.Item 'Output' $nca 'Object'
    $nnm = Call $PC_ 'GetNumMaterials' ($x + 2400) ($y + 200); Wire $nca 'AsSkeletal Mesh Component' $nnm 'self'
    $nsb = Math2 'Subtract_IntInt' @($nnm, 'ReturnValue') 1 ($x + 2600) ($y + 200)
    $nfl = Macro 'ForLoop' '' ($x + 2800) $y; Def $nfl 'FirstIndex' 'int' '0'; Wire $nsb 'ReturnValue' $nfl 'LastIndex'
    Wire $nca 'then' $nfl 'execute'
    $null = & $body $nfl 'LoopBody' $nca 'AsSkeletal Mesh Component' $nfl ($x + 3100) $y
    @{ Branch = $nbp; Done = $nl1.Loop }
}
# the slot's material, and the instance it came from: a MID's parent, or the
# material itself. Returns the valid-branch, the MID cast and the MIC cast
# (its 'then' continues, 'AsMaterial Instance Constant' is the instance).
function Slot-Mic($nEx, [string]$nExPin, $nComp, [string]$nCompPin, $nLoop, [int]$x, [int]$y) {
    $ngm = Call $PC_ 'GetMaterial' $x ($y + 220); Wire $nComp $nCompPin $ngm 'self'; Wire $nLoop 'Index' $ngm 'ElementIndex'
    $niv = Call $KS 'IsValid' ($x + 200) ($y + 220); Wire $ngm 'ReturnValue' $niv 'Object'
    $nbr = Branch ($x + 250) $y; Wire $nEx $nExPin $nbr 'execute'; Wire $niv 'ReturnValue' $nbr 'Condition'
    $ncm = Cast $MID ($x + 450) $y; Wire $nbr 'then' $ncm 'execute'; Wire $ngm 'ReturnValue' $ncm 'Object'
    $nim = Call $KS 'IsValid' ($x + 650) ($y + 220); Wire $ncm 'AsMaterial Instance Dynamic' $nim 'Object'
    $npg = GetVarOf '/Script/Engine.MaterialInstance' 'Parent' ($x + 650) ($y + 340); Wire $ncm 'AsMaterial Instance Dynamic' $npg 'self'
    $nso = Call $KM 'SelectObject' ($x + 850) ($y + 260); Wire $npg 'Parent' $nso 'A'; Wire $ngm 'ReturnValue' $nso 'B'; Wire $nim 'ReturnValue' $nso 'bSelectA'
    $ncc = Cast $MIC ($x + 1100) $y; Wire $nso 'ReturnValue' $ncc 'Object'
    @{ Valid = $nbr; MidCast = $ncm; MicCast = $ncc; Mat = $ngm; IsMid = $nim }
}
# chain helper: $c = @{ N = node; P = pin }, Step wires $c into $n.execute
# \ may be one @{N;P} or an array of them (several exec lines joining)
function Step($c, $n, [string]$outPin = 'then') { foreach ($s in @($c)) { Wire $s.N $s.P $n 'execute' }; @{ N = $n; P = $outPin } }

New-Item -ItemType Directory -Force -Path $Out | Out-Null

# ================================================================ variables
function BPVar-Full([string]$name, [string]$type, [string]$def) {
    $pt = switch ($type) {
        'int'      { '(PinCategory="int")' }
        'bool'     { '(PinCategory="bool")' }
        'name'     { '(PinCategory="name")' }
        'string'   { '(PinCategory="string")' }
        'string[]' { '(PinCategory="string",ContainerType=Array)' }
        'color'    { "(PinCategory=`"struct`",PinSubCategoryObject=`"/Script/CoreUObject.ScriptStruct'/Script/CoreUObject.LinearColor'`")" }
        'color[]'  { "(PinCategory=`"struct`",PinSubCategoryObject=`"/Script/CoreUObject.ScriptStruct'/Script/CoreUObject.LinearColor'`",ContainerType=Array)" }
        'mic[]'    { "(PinCategory=`"object`",PinSubCategoryObject=`"/Script/CoreUObject.Class'/Script/Engine.MaterialInstanceConstant'`",ContainerType=Array)" }
    }
    $d = if ($def) { ",DefaultValue=`"$def`"" } else { '' }
    'BPVar(VarName="{0}",VarGuid=5C1E7A51{1:X8}0000000000000000,VarType={2},FriendlyName="{0}",PropertyFlags=65541,ReplicationCondition=COND_None{3})' -f $name, ([Math]::Abs($name.GetHashCode())), $pt, $d
}
$Vars = [ordered]@{
    PartMICs = @('mic[]', ''); SelPart = @('int', '-1'); SelRow = @('int', '0'); SelSide = @('int', '0')
    SelParam = @('name', 'BaseTint'); SelMic = @('string', ''); EditKeys = @('string[]', ''); EditColors = @('color[]', '')
    Loaded = @('bool', 'false'); Tmp = @('string[]', ''); Idx = @('int', '0'); Count = @('int', '0')
    WheelDown = @('bool', 'false'); LastPick = @('color', ''); RecentColors = @('color[]', '')
    DesignNames = @('string[]', '')
}
$vi = 0
foreach ($k in $Vars.Keys) {
    $vi++
    [IO.File]::WriteAllText((Join-Path $Out ('vars_{0:D2}_{1}.txt' -f $vi, $k)), (BPVar-Full $k $Vars[$k][0] $Vars[$k][1]), (New-Object System.Text.UTF8Encoding($false)))
}
[IO.File]::WriteAllText((Join-Path $Out 'save_var.txt'), (BPVar-Text 'Data' 'string'), (New-Object System.Text.UTF8Encoding($false)))
'vars: {0} + save_var' -f $Vars.Keys.Count

# ================================================================ paste 1
New-Graph 11
# Say(Msg): the status line
$e = CustomEvent 'Say' 0 0 @('Msg=string')
$null = Set-BtnText $e 'then' 'StatusB' @($e, 'Msg') 300 0

# LoadEdits: the save string -> EditKeys / EditColors, once per panel instance
$e = CustomEvent 'LoadEdits' 0 600
$nb = Branch 250 600; Wire $e 'then' $nb 'execute'; Wire (Get-Var 'Loaded' 100 760) 'Loaded' $nb 'Condition'
$nlg = Call $GS 'LoadGameFromSlot' 500 600; Def $nlg 'SlotName' 'string' $ColorSlot; Def $nlg 'UserIndex' 'int' '0'
Wire $nb 'else' $nlg 'execute'
$ncs = CastBP $SaveClass 750 600; Wire $nlg 'then' $ncs 'execute'; Wire $nlg 'ReturnValue' $ncs 'Object'
$nc1 = Arr-Call 'Array_Clear' 'EditKeys' 1000 600; Wire $ncs 'then' $nc1 'execute'
$nc2 = Arr-Call 'Array_Clear' 'EditColors' 1300 600; Wire $nc1 'then' $nc2 'execute'
$nd = GetVarOfBP $SaveClass 'Data' 1300 900; Wire $ncs 'AsSkin Studio Save' $nd 'self'
$npa = Call $KSt 'ParseIntoArray' 1500 900; Wire $nd 'Data' $npa 'SourceString'; Def $npa 'Delimiter' 'string' ';'; Def $npa 'CullEmptyStrings' 'bool' 'true'
$nst = Set-Var $nc2 'then' 'Tmp' $npa 'ReturnValue' 1600 600
$nl = ArrayLoop (Get-Var 'Tmp' 1800 900) 'Tmp' 1900 600
Wire $nst 'then' $nl.Loop 'execute'
$npe = Call $KSt 'ParseIntoArray' 2600 900; Wire $nl.Item 'Output' $npe 'SourceString'; Def $npe 'Delimiter' 'string' '|'; Def $npe 'CullEmptyStrings' 'bool' 'true'
$ng0 = Get-ArrItem $npe 'ReturnValue' 0 2850 900
$ng1 = Get-ArrItem $npe 'ReturnValue' 1 2850 1000
$ng2 = Get-ArrItem $npe 'ReturnValue' 2 2850 1100
$nkey = Concat-Chain @(@($ng0, 'Output'), '|', @($ng1, 'Output')) 3000 900
$ncol = Parse-Color $ng2 'Output' 3000 1100
$na1 = Arr-Call 'Array_Add' 'EditKeys' 3400 600; Wire $nl.Loop 'LoopBody' $na1 'execute'; Wire $nkey 'ReturnValue' $na1 'NewItem'
$na2 = Arr-Call 'Array_Add' 'EditColors' 3700 600; Wire $na1 'then' $na2 'execute'; Wire $ncol 'ReturnValue' $na2 'NewItem'
$nlt = Set-VarLit $nl.Loop 'Completed' 'Loaded' 'bool' 'true' 2300 400
$nlf = Set-VarLit $ncs 'CastFailed' 'Loaded' 'bool' 'true' 1000 400

# SaveEdits: EditKeys / EditColors -> one string -> our SaveGame
$e = CustomEvent 'SaveEdits' 0 1500
$ncl = Arr-Call 'Array_Clear' 'Tmp' 250 1500; Wire $e 'then' $ncl 'execute'
$nl = ArrayLoop (Get-Var 'EditKeys' 400 1800) 'EditKeys' 500 1500
Wire $ncl 'then' $nl.Loop 'execute'
$nci = Get-ArrItem (Get-Var 'EditColors' 1100 1900) 'EditColors' @($nl.Loop, 'Index') 1300 1800
$nbk = Call $KM 'BreakColor' 1500 1800; Wire $nci 'Output' $nbk 'InColor'
$ns = @()
foreach ($ch in @('R', 'G', 'B')) {
    $nds = Call $KSt 'Conv_DoubleToString' 1700 (1800 + 100 * $ns.Count); Wire $nbk $ch $nds 'InDouble'
    $ns += , $nds
}
$nent = Concat-Chain @(@($nl.Item, 'Output'), '|', @($ns[0], 'ReturnValue'), ',', @($ns[1], 'ReturnValue'), ',', @($ns[2], 'ReturnValue')) 1900 1800
$nad = Arr-Call 'Array_Add' 'Tmp' 3200 1500; Wire $nl.Loop 'LoopBody' $nad 'execute'; Wire $nent 'ReturnValue' $nad 'NewItem'
$njs = Call $KSt 'JoinStringArray' 1400 1300; Wire (Get-Var 'Tmp' 1200 1300) 'Tmp' $njs 'SourceArray'; Def $njs 'Separator' 'string' ';'
$nco = Call $GS 'CreateSaveGameObject' 1700 1200; Def $nco 'SaveGameClass' 'class:/Script/Engine.SaveGame' $SaveClass
Wire $nl.Loop 'Completed' $nco 'execute'
$nck = CastBP $SaveClass 1950 1200; Wire $nco 'then' $nck 'execute'; Wire $nco 'ReturnValue' $nck 'Object'
$nsd = SetVarOfBP $SaveClass 'Data' 2200 1200; Wire $nck 'then' $nsd 'execute'; Wire $nck 'AsSkin Studio Save' $nsd 'self'; Wire $njs 'ReturnValue' $nsd 'Data'
$nsg = Call $GS 'SaveGameToSlot' 2450 1200; Wire $nsd 'then' $nsg 'execute'; Wire $nck 'AsSkin Studio Save' $nsg 'SaveGameObject'
Def $nsg 'SlotName' 'string' $ColorSlot; Def $nsg 'UserIndex' 'int' '0'

# ApplyParam(Mic, Param, Color): paint one param on every slot of that instance
$eAp = CustomEvent 'ApplyParam' 0 2400 @('Mic=string', 'Param=name', "Color=$LC")
$apBody = {
    param($nEx, $nExPin, $nComp, $nCompPin, $nLoop, [int]$x, [int]$y)
    $sm = Slot-Mic $nEx $nExPin $nComp $nCompPin $nLoop $x $y
    Wire $sm.MidCast 'then' $sm.MicCast 'execute'; Wire $sm.MidCast 'CastFailed' $sm.MicCast 'execute'
    $non = Call $KS 'GetObjectName' ($x + 1300) ($y + 200); Wire $sm.MicCast 'AsMaterial Instance Constant' $non 'Object'
    $neq = Call $KSt 'EqualEqual_StrStr' ($x + 1500) ($y + 200); Wire $non 'ReturnValue' $neq 'A'; Wire $eAp 'Mic' $neq 'B'
    $nbq = Branch ($x + 1600) $y; Wire $sm.MicCast 'then' $nbq 'execute'; Wire $neq 'ReturnValue' $nbq 'Condition'
    $ncd = Call $PC_ 'CreateDynamicMaterialInstance' ($x + 1850) $y; Wire $nbq 'then' $ncd 'execute'
    Wire $nComp $nCompPin $ncd 'self'; Wire $nLoop 'Index' $ncd 'ElementIndex'
    $nsv = Call $MID 'SetVectorParameterValue' ($x + 2100) $y; Wire $ncd 'then' $nsv 'execute'; Wire $ncd 'ReturnValue' $nsv 'self'
    Wire $eAp 'Param' $nsv 'ParameterName'; Wire $eAp 'Color' $nsv 'Value'
}
$null = Walk-Slots $eAp 'then' $apBody 300 2400

Save-Graph 'panel_1.txt'

# ---------------------------------------------------------------- paste 1b
# (split off: one 1.9 MB paste ran the editor out of memory, 2026-09-28)
New-Graph 30
# RefreshDesigns: the design list (D0..D47) <- SkinStudioDesigns ("a;b;c", written
# by the panel's Save/Delete, and by the app's helper when it is installed)
$DesignSlots = 48
$e = CustomEvent 'RefreshDesigns' 0 5000
$nli = Call $GS 'LoadGameFromSlot' 250 5000; Def $nli 'SlotName' 'string' 'SkinStudioDesigns'; Def $nli 'UserIndex' 'int' '0'
Wire $e 'then' $nli 'execute'
$nci = CastBP $SaveClass 500 5000; Wire $nli 'then' $nci 'execute'; Wire $nli 'ReturnValue' $nci 'Object'
$ndi = GetVarOfBP $SaveClass 'Data' 500 5250; Wire $nci 'AsSkin Studio Save' $ndi 'self'
$npi = Call $KSt 'ParseIntoArray' 700 5250; Wire $ndi 'Data' $npi 'SourceString'; Def $npi 'Delimiter' 'string' ';'; Def $npi 'CullEmptyStrings' 'bool' 'true'
$nsi = Set-Var $nci 'then' 'DesignNames' $npi 'ReturnValue' 800 5000
$nci0 = Arr-Call 'Array_Clear' 'DesignNames' 800 5200; Wire $nci 'CastFailed' $nci0 'execute'
$c = @(@{ N = $nsi; P = 'then' }, @{ N = $nci0; P = 'then' })
for ($i = 0; $i -lt $DesignSlots; $i++) {
    $x0 = 1100 + 900 * $i
    $nln = Arr-Call 'Array_Length' 'DesignNames' $x0 5300
    $nlt = Math2 'Less_IntInt' $i @($nln, 'ReturnValue') ($x0 + 200) 5300
    $nbr = Branch $x0 5000; foreach ($s in @($c)) { Wire $s.N $s.P $nbr 'execute' }; Wire $nlt 'ReturnValue' $nbr 'Condition'
    $nit = Get-ArrItem (Get-Var 'DesignNames' ($x0 + 100) 5500) 'DesignNames' $i ($x0 + 300) 5500
    $ntx = Set-BtnText $nbr 'then' ('D' + $i) @($nit, 'Output') ($x0 + 250) 4800
    $nv1 = Set-Vis $ntx 'then' ('D' + $i) 'Visible' ($x0 + 600) 4800
    $nv0 = Set-Vis $nbr 'else' ('D' + $i) 'Collapsed' ($x0 + 250) 5150
    $c = @(@{ N = $nv1; P = 'then' }, @{ N = $nv0; P = 'then' })
}

# RefreshRecent: the recent-colours strip (Rc0..Rc7) <- RecentColors
$RecentSlots = 8
$e = CustomEvent 'RefreshRecent' 0 7000
$c = @(@{ N = $e; P = 'then' })
for ($i = 0; $i -lt $RecentSlots; $i++) {
    $x0 = 300 + 900 * $i
    $nln = Arr-Call 'Array_Length' 'RecentColors' $x0 7300
    $nlt = Math2 'Less_IntInt' $i @($nln, 'ReturnValue') ($x0 + 200) 7300
    $nbr = Branch $x0 7000; foreach ($s in @($c)) { Wire $s.N $s.P $nbr 'execute' }; Wire $nlt 'ReturnValue' $nbr 'Condition'
    $nit = Get-ArrItem (Get-Var 'RecentColors' ($x0 + 100) 7500) 'RecentColors' $i ($x0 + 300) 7500
    $nbg = Call-On ('Rc' + $i) $BT 'SetBackgroundColor' ($x0 + 250) 6800; Wire $nbr 'then' $nbg 'execute'; Wire $nit 'Output' $nbg 'InBackgroundColor'
    $nv1 = Set-Vis $nbg 'then' ('Rc' + $i) 'Visible' ($x0 + 550) 6800
    $nv0 = Set-Vis $nbr 'else' ('Rc' + $i) 'Hidden' ($x0 + 250) 7150
    $c = @(@{ N = $nv1; P = 'then' }, @{ N = $nv0; P = 'then' })
}
Save-Graph 'panel_1b.txt'

# ================================================================ paste 2
New-Graph 12
# Reapply: the bootstrap's 1 s pulse. Paint every slot that is not ours yet
# (fresh after a respawn / new match) with all its saved edits, then mark it:
# a MID scalar "SSMark" = 1 (a scalar the material lacks just sits in the MID's
# override list), so painted slots cost one cast + one read per second.
$e = CustomEvent 'Reapply' 0 0
$nle = CallSelf 'LoadEdits' 250 0; Wire $e 'then' $nle 'execute'
$reBody = {
    param($nEx, $nExPin, $nComp, $nCompPin, $nLoop, [int]$x, [int]$y)
    $sm = Slot-Mic $nEx $nExPin $nComp $nCompPin $nLoop $x $y
    $ngs = Call $MID 'K2_GetScalarParameterValue' ($x + 700) ($y - 250); Wire $sm.MidCast 'then' $ngs 'execute'
    Wire $sm.MidCast 'AsMaterial Instance Dynamic' $ngs 'self'; Def $ngs 'ParameterName' 'name' 'SSMark'
    $ngt = Math2 'Greater_DoubleDouble' @($ngs, 'ReturnValue') '0.500000' ($x + 900) ($y - 120) 'real'
    $nbm = Branch ($x + 950) ($y - 250); Wire $ngs 'then' $nbm 'execute'; Wire $ngt 'ReturnValue' $nbm 'Condition'
    Wire $nbm 'else' $sm.MicCast 'execute'; Wire $sm.MidCast 'CastFailed' $sm.MicCast 'execute'
    $ncd = Call $PC_ 'CreateDynamicMaterialInstance' ($x + 1350) $y; Wire $sm.MicCast 'then' $ncd 'execute'
    Wire $nComp $nCompPin $ncd 'self'; Wire $nLoop 'Index' $ncd 'ElementIndex'
    $non = Call $KS 'GetObjectName' ($x + 1350) ($y + 250); Wire $sm.MicCast 'AsMaterial Instance Constant' $non 'Object'
    $npre = Concat-Chain @(@($non, 'ReturnValue'), '|') ($x + 1350) ($y + 350)
    $nl = ArrayLoop (Get-Var 'EditKeys' ($x + 1500) ($y + 450)) 'EditKeys' ($x + 1600) $y
    Wire $ncd 'then' $nl.Loop 'execute'
    $nsw = Call $KSt 'StartsWith' ($x + 2300) ($y + 250); Wire $nl.Item 'Output' $nsw 'SourceString'; Wire $npre 'ReturnValue' $nsw 'InPrefix'
    $nbj = Branch ($x + 2350) $y; Wire $nl.Loop 'LoopBody' $nbj 'execute'; Wire $nsw 'ReturnValue' $nbj 'Condition'
    $nln = Call $KSt 'Len' ($x + 2500) ($y + 400); Wire $npre 'ReturnValue' $nln 'S'
    $nrc = Call $KSt 'RightChop' ($x + 2700) ($y + 300); Wire $nl.Item 'Output' $nrc 'SourceString'; Wire $nln 'ReturnValue' $nrc 'Count'
    $nsn = Call $KSt 'Conv_StringToName' ($x + 2900) ($y + 300); Wire $nrc 'ReturnValue' $nsn 'InString'
    $nec = Get-ArrItem (Get-Var 'EditColors' ($x + 2700) ($y + 500)) 'EditColors' @($nl.Loop, 'Index') ($x + 2900) ($y + 450)
    $nsv = Call $MID 'SetVectorParameterValue' ($x + 3100) $y; Wire $nbj 'then' $nsv 'execute'
    Wire $ncd 'ReturnValue' $nsv 'self'; Wire $nsn 'ReturnValue' $nsv 'ParameterName'; Wire $nec 'Output' $nsv 'Value'
    $nss = Call $MID 'SetScalarParameterValue' ($x + 2300) ($y - 200); Wire $nl.Loop 'Completed' $nss 'execute'
    Wire $ncd 'ReturnValue' $nss 'self'; Def $nss 'ParameterName' 'name' 'SSMark'; Def $nss 'Value' 'float' '1.000000'
}
$null = Walk-Slots $nle 'then' $reBody 500 0

# RefreshPicker: sliders + preview <- the selected colour
$e = CustomEvent 'RefreshPicker' 0 1600
$nsv0 = Sel-Valid 0 1800
$nb = Branch 250 1600; Wire $e 'then' $nb 'execute'; Wire $nsv0 'ReturnValue' $nb 'Condition'
$nmi = Sel-Mic 300 2100
$ngv = Call $MIC 'K2_GetVectorParameterValue' 600 1600; Wire $nb 'then' $ngv 'execute'; Wire $nmi 'Output' $ngv 'self'
Wire (Get-Var 'SelParam' 450 1750) 'SelParam' $ngv 'ParameterName'
$nps = Call $KSt 'Conv_NameToString' 600 2300; Wire (Get-Var 'SelParam' 400 2300) 'SelParam' $nps 'InName'
$ncc = Cur-Color @($nps, 'ReturnValue') $ngv 'ReturnValue' 800 2300
# Light = the brightest channel / 2 (0.5 = as the wheel shows it); R/G/B in sRGB
$nbc = Call $KM 'BreakColor' 2300 2300; Wire $ncc 'ReturnValue' $nbc 'InColor'
$nx1 = Call $KM 'FMax' 2500 2500; Wire $nbc 'R' $nx1 'A'; Wire $nbc 'G' $nx1 'B'
$nx2 = Call $KM 'FMax' 2650 2500; Wire $nx1 'ReturnValue' $nx2 'A'; Wire $nbc 'B' $nx2 'B'
$nv2 = Math2 'Divide_DoubleDouble' @($nx2, 'ReturnValue') '2.000000' 2800 2500 'real'
# * 2026-09-29: the sliders are one model - colour = (R,G,B sRGB)^2.2 x Light x2.
#   Keep the Light the slider already has (m = its x2), raising it only when the
#   colour is brighter than m can show; R/G/B = (channel / m)^0.4545. Before,
#   Light was always max/2 and R/G/B ignored it, so the sliders fought.
$ngl = Call-On 'SlV' $SLD 'GetValue' 2300 2700
$nm0 = Math2 'Multiply_DoubleDouble' @($ngl, 'ReturnValue') '2.000000' 2500 2700 'real'
$nmm = Call $KM 'FMax' 2700 2700; Wire $nm0 'ReturnValue' $nmm 'A'; Wire $nx2 'ReturnValue' $nmm 'B'
$nme = Call $KM 'FMax' 2900 2700; Wire $nmm 'ReturnValue' $nme 'A'; Def $nme 'B' 'real' '0.000100'
$c = @{ N = $ngv; P = 'then' }
# R/G/B first: they read the Light slider before it is moved
$xk = 1200
foreach ($ch in @('R', 'G', 'B')) {
    $ndv = Call $KM 'Divide_DoubleDouble' ($xk - 100) 2550; Wire $nbc $ch $ndv 'A'; Wire $nme 'ReturnValue' $ndv 'B'
    $ncl = Call $KM 'FClamp' ($xk - 100) 2700; Wire $ndv 'ReturnValue' $ncl 'Value'; Def $ncl 'Min' 'real' '0.000000'; Def $ncl 'Max' 'real' '1.000000'
    $npw = Call $KM 'MultiplyMultiply_FloatFloat' ($xk - 100) 2850; Wire $ncl 'ReturnValue' $npw 'Base'; Def $npw 'Exp' 'real' '0.454545'
    $nsl = Call-On ('Sl' + $ch) $SLD 'SetValue' $xk 1600; $c = Step $c $nsl; Wire $npw 'ReturnValue' $nsl 'InValue'
    $xk += 300
}
$nlv = Math2 'Divide_DoubleDouble' @($nme, 'ReturnValue') '2.000000' 3100 2700 'real'
$nvc = Call $KM 'FClamp' 3300 2700; Wire $nlv 'ReturnValue' $nvc 'Value'; Def $nvc 'Min' 'real' '0.000000'; Def $nvc 'Max' 'real' '1.000000'
$n3 = Call-On 'SlV' $SLD 'SetValue' $xk 1600; $c = Step $c $n3; Wire $nvc 'ReturnValue' $n3 'InValue'
$n4 = Call-On 'PreviewB' $BT 'SetBackgroundColor' 1800 1600; $c = Step $c $n4; Wire $ncc 'ReturnValue' $n4 'InBackgroundColor'

# RefreshRows: which rows this part has, their swatches, the selected row
$e = CustomEvent 'RefreshRows' 0 3000
$nsv0 = Sel-Valid 0 3200
$nb = Branch 250 3000; Wire $e 'then' $nb 'execute'; Wire $nsv0 'ReturnValue' $nb 'Condition'
$nmi = Sel-Mic 300 3500
$ntx = Call $MIC 'K2_GetTextureParameterValue' 500 3000; Wire $nb 'then' $ntx 'execute'; Wire $nmi 'Output' $ntx 'self'; Def $ntx 'ParameterName' 'name' 'DyeingTexture'
$ntn = Call $KS 'GetObjectName' 700 3300; Wire $ntx 'ReturnValue' $ntn 'Object'
$ndy = Call $KSt 'EndsWith' 900 3300; Wire $ntn 'ReturnValue' $ndy 'SourceString'; Def $ndy 'InSuffix' 'string' '_ColorID'
$c = @{ N = $ntx; P = 'then' }
$x0 = 800
for ($r = 0; $r -lt 16; $r++) {
    $x0 += 2600
    $zone = $r -ge 9
    $pA = if ($zone) { 'Region {0} - ColorA' -f ($r - 8) } else { $RowParams[$r] }
    $pB = 'Region {0} - ColorB' -f ($r - 8)
    $ngA = Call $MIC 'K2_GetVectorParameterValue' $x0 3000; $c = Step $c $ngA; Wire $nmi 'Output' $ngA 'self'; Def $ngA 'ParameterName' 'name' $pA
    if ($zone) {
        $ngB = Call $MIC 'K2_GetVectorParameterValue' ($x0 + 250) 3000; $c = Step $c $ngB; Wire $nmi 'Output' $ngB 'self'; Def $ngB 'ParameterName' 'name' $pB
        $ncond = $ndy
    } else {
        $neq = Call $KM 'EqualEqual_LinearColorLinearColor' $x0 3300; Wire $ngA 'ReturnValue' $neq 'A'; Def $neq 'B' $LC '(R=0.000000,G=0.000000,B=0.000000,A=1.000000)'
        $ncond = Call $KM 'Not_PreBool' ($x0 + 200) 3300; Wire $neq 'ReturnValue' $ncond 'A'
    }
    $nbr = Branch ($x0 + 500) 3000; $null = Step $c $nbr; Wire $ncond 'ReturnValue' $nbr 'Condition'
    $nvs = Set-VisParentOf $nbr 'then' "RB$r" 'Visible' ($x0 + 700) 2900
    $nvh = Set-VisParentOf $nbr 'else' "RB$r" 'Collapsed' ($x0 + 700) 3100
    $ccA = Cur-Color $pA $ngA 'ReturnValue' ($x0 + 500) 3500
    $nsa = Set-BtnColor $nvs 'then' "RA$r" @($ccA, 'ReturnValue') ($x0 + 1000) 3000; Wire $nvh 'then' $nsa 'execute'
    $c = @{ N = $nsa; P = 'then' }
    if ($zone) {
        $ccB = Cur-Color $pB $ngB 'ReturnValue' ($x0 + 500) 3900
        $nsb2 = Set-BtnColor $c.N $c.P "RC$r" @($ccB, 'ReturnValue') ($x0 + 1300) 3000
        $c = @{ N = $nsb2; P = 'then' }
    }
    $nis = Math2 'EqualEqual_IntInt' @((Get-Var 'SelRow' ($x0 + 1400) 3300), 'SelRow') $r ($x0 + 1600) 3300
    $nsc = Call $KM 'SelectColor' ($x0 + 1800) 3300; Def $nsc 'A' $LC $ColSel; Def $nsc 'B' $LC $ColCard; Wire $nis 'ReturnValue' $nsc 'bPickA'
    $nsr = Set-BtnColor $c.N $c.P "RB$r" @($nsc, 'ReturnValue') ($x0 + 1700) 3000
    $c = @{ N = $nsr; P = 'then' }
}

# a colour snapped to 0.001 per channel: the sRGB round trip leaves ~1e-6 noise,
# so the same colour picked twice never matched and filled the strip with copies
function Snap-Color($nSrc, [string]$pin, [int]$x, [int]$y) {
    $nbk = Call $KM 'BreakColor' $x $y; Wire $nSrc $pin $nbk 'InColor'
    $nmc = Call $KM 'MakeColor' ($x + 400) $y; Def $nmc 'A' 'float' '1.000000'
    $k = 0
    foreach ($ch in @('R', 'G', 'B')) {
        $ngs = Call $KM 'GridSnap_Float' ($x + 200) ($y + 100 * $k); Wire $nbk $ch $ngs 'Location'; Def $ngs 'GridSize' 'real' '0.001000'
        Wire $ngs 'ReturnValue' $nmc $ch; $k++
    }
    $nmc
}
# LoadRecent: SkinStudioRecent ("r,g,b;..." linear) -> RecentColors, once per panel
$e = CustomEvent 'LoadRecent' 0 6000
$nlr = Call $GS 'LoadGameFromSlot' 250 6000; Def $nlr 'SlotName' 'string' 'SkinStudioRecent'; Def $nlr 'UserIndex' 'int' '0'; Wire $e 'then' $nlr 'execute'
$ncr = CastBP $SaveClass 500 6000; Wire $nlr 'then' $ncr 'execute'; Wire $nlr 'ReturnValue' $ncr 'Object'
$nrc = Arr-Call 'Array_Clear' 'RecentColors' 750 6000; Wire $ncr 'then' $nrc 'execute'
$ndr = GetVarOfBP $SaveClass 'Data' 750 6250; Wire $ncr 'AsSkin Studio Save' $ndr 'self'
$npr = Call $KSt 'ParseIntoArray' 950 6250; Wire $ndr 'Data' $npr 'SourceString'; Def $npr 'Delimiter' 'string' ';'; Def $npr 'CullEmptyStrings' 'bool' 'true'
$nlp = ArrayLoop $npr 'ReturnValue' 1000 6000
Wire $nrc 'then' $nlp.Loop 'execute'
$npc2 = Parse-Color $nlp.Item 'Output' 1300 6300
$nsn = Snap-Color $npc2 'ReturnValue' 1500 6500
$nar = Arr-Call 'Array_AddUnique' 'RecentColors' 1800 6000; Wire $nlp.Loop 'LoopBody' $nar 'execute'; Wire $nsn 'ReturnValue' $nar 'NewItem'
$nrr0 = CallSelf 'RefreshRecent' 1800 6400; Wire $nlp.Loop 'Completed' $nrr0 'execute'; Wire $ncr 'CastFailed' $nrr0 'execute'

# AddRecent(Color): to the front of the strip (once), 8 at most, saved
$e = CustomEvent 'AddRecent' 0 7000 @("Color=$LC")
$nsn = Snap-Color $e 'Color' 100 7500
$nrm = Arr-Call 'Array_RemoveItem' 'RecentColors' 250 7000; Wire $e 'then' $nrm 'execute'; Wire $nsn 'ReturnValue' $nrm 'Item'
$nin = Arr-Call 'Array_Insert' 'RecentColors' 500 7000; Wire $nrm 'then' $nin 'execute'; Wire $nsn 'ReturnValue' $nin 'NewItem'; Def $nin 'Index' 'int' '0'
# only ever shrink: a Resize up would pad the strip with black
$nlz = Arr-Call 'Array_Length' 'RecentColors' 600 7300
$ngt = Math2 'Greater_IntInt' @($nlz, 'ReturnValue') $RecentSlots 800 7300
$nbz = Branch 700 7000; Wire $nin 'then' $nbz 'execute'; Wire $ngt 'ReturnValue' $nbz 'Condition'
$nrz = Arr-Call 'Array_Resize' 'RecentColors' 850 6900; Wire $nbz 'then' $nrz 'execute'; Def $nrz 'Size' 'int' ([string]$RecentSlots)
# the list as text: r,g,b per colour
$ntc = Arr-Call 'Array_Clear' 'Tmp' 1000 7000; Wire $nrz 'then' $ntc 'execute'; Wire $nbz 'else' $ntc 'execute'
$nl = ArrayLoop (Get-Var 'RecentColors' 1100 7300) 'RecentColors' 1250 7000
Wire $ntc 'then' $nl.Loop 'execute'
$nbk = Call $KM 'BreakColor' 1600 7300; Wire $nl.Item 'Output' $nbk 'InColor'
$ns = @()
foreach ($ch in @('R', 'G', 'B')) {
    $nds = Call $KSt 'Conv_DoubleToString' 1800 (7300 + 100 * $ns.Count); Wire $nbk $ch $nds 'InDouble'
    $ns += , $nds
}
$nent = Concat-Chain @(@($ns[0], 'ReturnValue'), ',', @($ns[1], 'ReturnValue'), ',', @($ns[2], 'ReturnValue')) 2000 7300
$nad = Arr-Call 'Array_Add' 'Tmp' 2300 7000; Wire $nl.Loop 'LoopBody' $nad 'execute'; Wire $nent 'ReturnValue' $nad 'NewItem'
$njs = Call $KSt 'JoinStringArray' 2500 7300; Wire (Get-Var 'Tmp' 2400 7400) 'Tmp' $njs 'SourceArray'; Def $njs 'Separator' 'string' ';'
$nco = Call $GS 'CreateSaveGameObject' 2600 7000; Def $nco 'SaveGameClass' 'class:/Script/Engine.SaveGame' $SaveClass; Wire $nl.Loop 'Completed' $nco 'execute'
$nck = CastBP $SaveClass 2850 7000; Wire $nco 'then' $nck 'execute'; Wire $nco 'ReturnValue' $nck 'Object'
$nsd = SetVarOfBP $SaveClass 'Data' 3100 7000; Wire $nck 'then' $nsd 'execute'; Wire $nck 'AsSkin Studio Save' $nsd 'self'; Wire $njs 'ReturnValue' $nsd 'Data'
$nsg = Call $GS 'SaveGameToSlot' 3350 7000; Wire $nsd 'then' $nsg 'execute'; Wire $nck 'AsSkin Studio Save' $nsg 'SaveGameObject'
Def $nsg 'SlotName' 'string' 'SkinStudioRecent'; Def $nsg 'UserIndex' 'int' '0'
$nrr1 = CallSelf 'RefreshRecent' 3600 7000; Wire $nsg 'then' $nrr1 'execute'
Save-Graph 'panel_2.txt'

# ================================================================ paste 3
New-Graph 13
# SelectRow(Row, Side): which param the picker edits
$e = CustomEvent 'SelectRow' 0 0 @('Row=int', 'Side=int')
$ns1 = Set-Var $e 'then' 'SelRow' $e 'Row' 250 0
$ns2 = Set-Var $ns1 'then' 'SelSide' $e 'Side' 500 0
$nsub = Math2 'Subtract_IntInt' @($e, 'Row') 9 250 300
$nmul = Math2 'Multiply_IntInt' @($nsub, 'ReturnValue') 2 450 300
$nadd = Math2 'Add_IntInt' @($nmul, 'ReturnValue') @($e, 'Side') 650 300
$nad9 = Math2 'Add_IntInt' @($nadd, 'ReturnValue') 9 850 300
$nlt9 = Math2 'Less_IntInt' @($e, 'Row') 9 850 450
$nsi = Call $KM 'SelectInt' 1050 300; Wire $e 'Row' $nsi 'A'; Wire $nad9 'ReturnValue' $nsi 'B'; Wire $nlt9 'ReturnValue' $nsi 'bPickA'
$npt = Call $KSt 'ParseIntoArray' 1050 550; Def $npt 'SourceString' 'string' $ParamTable; Def $npt 'Delimiter' 'string' '|'; Def $npt 'CullEmptyStrings' 'bool' 'true'
$ngi = Get-ArrItem $npt 'ReturnValue' @($nsi, 'ReturnValue') 1300 400
$nsn = Call $KSt 'Conv_StringToName' 1500 400; Wire $ngi 'Output' $nsn 'InString'
$ns3 = Set-Var $ns2 'then' 'SelParam' $nsn 'ReturnValue' 750 0
$nrr = CallSelf 'RefreshRows' 1000 0; Wire $ns3 'then' $nrr 'execute'
$nrp = CallSelf 'RefreshPicker' 1250 0; Wire $nrr 'then' $nrp 'execute'

# PickColor(Color): store the edit, paint it, update the swatches
$e = CustomEvent 'PickColor' 0 1000 @("Color=$LC")
$nsv0 = Sel-Valid 0 1200
$nlpk = Set-Var $e 'then' 'LastPick' $e 'Color' 150 800
$nb = Branch 250 1000; Wire $nlpk 'then' $nb 'execute'; Wire $nsv0 'ReturnValue' $nb 'Condition'
$nps = Call $KSt 'Conv_NameToString' 300 1500; Wire (Get-Var 'SelParam' 100 1500) 'SelParam' $nps 'InName'
$ei = Edit-Index @($nps, 'ReturnValue') 300 1650
$nhas = Math2 'GreaterEqual_IntInt' @($ei.Find, 'ReturnValue') 0 1200 1650
$nbf = Branch 500 1000; Wire $nb 'then' $nbf 'execute'; Wire $nhas 'ReturnValue' $nbf 'Condition'
$nset = Arr-Call 'Array_Set' 'EditColors' 750 900; Wire $nbf 'then' $nset 'execute'
Wire $ei.Find 'ReturnValue' $nset 'Index'; Wire $e 'Color' $nset 'Item'; Def $nset 'bSizeToFit' 'bool' 'false'
$nak = Arr-Call 'Array_Add' 'EditKeys' 750 1150; Wire $nbf 'else' $nak 'execute'; Wire $ei.Key 'ReturnValue' $nak 'NewItem'
$nac = Arr-Call 'Array_Add' 'EditColors' 1050 1150; Wire $nak 'then' $nac 'execute'; Wire $e 'Color' $nac 'NewItem'
$nap = CallSelf 'ApplyParam' 1400 1000; Wire $nset 'then' $nap 'execute'; Wire $nac 'then' $nap 'execute'
Wire (Get-Var 'SelMic' 1250 1250) 'SelMic' $nap 'Mic'; Wire (Get-Var 'SelParam' 1250 1350) 'SelParam' $nap 'Param'; Wire $e 'Color' $nap 'Color'
$npv = Call-On 'PreviewB' $BT 'SetBackgroundColor' 1650 1000; Wire $nap 'then' $npv 'execute'; Wire $e 'Color' $npv 'InBackgroundColor'
$nrr = CallSelf 'RefreshRows' 1950 1000; Wire $npv 'then' $nrr 'execute'

# ResetOne: drop the selected edit, paint the vanilla value back
$e = CustomEvent 'ResetOne' 0 2200
$nsv0 = Sel-Valid 0 2400
$nb = Branch 250 2200; Wire $e 'then' $nb 'execute'; Wire $nsv0 'ReturnValue' $nb 'Condition'
$nps = Call $KSt 'Conv_NameToString' 300 2700; Wire (Get-Var 'SelParam' 100 2700) 'SelParam' $nps 'InName'
$ei = Edit-Index @($nps, 'ReturnValue') 300 2850
# * cache the index: after the first Remove the pure Find would re-evaluate to -1
$nsi = Set-Var $nb 'then' 'Idx' $ei.Find 'ReturnValue' 500 2200
$nhas = Math2 'GreaterEqual_IntInt' @((Get-Var 'Idx' 600 2500), 'Idx') 0 800 2500
$nbf = Branch 750 2200; Wire $nsi 'then' $nbf 'execute'; Wire $nhas 'ReturnValue' $nbf 'Condition'
$nr1 = Arr-Call 'Array_Remove' 'EditKeys' 1000 2100; Wire $nbf 'then' $nr1 'execute'; Wire (Get-Var 'Idx' 900 2300) 'Idx' $nr1 'IndexToRemove'
$nr2 = Arr-Call 'Array_Remove' 'EditColors' 1300 2100; Wire $nr1 'then' $nr2 'execute'; Wire (Get-Var 'Idx' 1200 2300) 'Idx' $nr2 'IndexToRemove'
$nmi = Sel-Mic 1400 2600
$ngv = Call $MIC 'K2_GetVectorParameterValue' 1600 2200; Wire $nr2 'then' $ngv 'execute'; Wire $nbf 'else' $ngv 'execute'
Wire $nmi 'Output' $ngv 'self'; Wire (Get-Var 'SelParam' 1500 2400) 'SelParam' $ngv 'ParameterName'
$nap = CallSelf 'ApplyParam' 1900 2200; Wire $ngv 'then' $nap 'execute'
Wire (Get-Var 'SelMic' 1750 2400) 'SelMic' $nap 'Mic'; Wire (Get-Var 'SelParam' 1750 2500) 'SelParam' $nap 'Param'; Wire $ngv 'ReturnValue' $nap 'Color'
$c = @{ N = $nap; P = 'then' }
foreach ($ev in @('RefreshRows', 'RefreshPicker', 'SaveEdits')) { $c = Step $c (CallSelf $ev (2200 + 250 * $c.Count) 2200) }
$nsay = CallSelf 'Say' 3000 2200; $c = Step $c $nsay; Def $nsay 'Msg' 'string' 'Colour reset to the original.'

# ResetPart: drop every edit of the selected part, paint all its params back
$e = CustomEvent 'ResetPart' 0 3400
$nsv0 = Sel-Valid 0 3600
$nb = Branch 250 3400; Wire $e 'then' $nb 'execute'; Wire $nsv0 'ReturnValue' $nb 'Condition'
$nlen = Arr-Call 'Array_Length' 'EditKeys' 300 3700
$nsc = Set-Var $nb 'then' 'Count' $nlen 'ReturnValue' 500 3400
$nlast = Math2 'Subtract_IntInt' @((Get-Var 'Count' 600 3700), 'Count') 1 800 3700
$nfl = Macro 'ForLoop' '' 800 3400; Def $nfl 'FirstIndex' 'int' '0'; Wire $nlast 'ReturnValue' $nfl 'LastIndex'; Wire $nsc 'then' $nfl 'execute'
# walk backwards: j = Count-1-Index, so a removal never moves an index still to come
$nj = Math2 'Subtract_IntInt' @($nlast, 'ReturnValue') @($nfl, 'Index') 1000 3800
$nkj = Get-ArrItem (Get-Var 'EditKeys' 1100 3950) 'EditKeys' @($nj, 'ReturnValue') 1300 3850
$npre = Concat-Chain @(@((Get-Var 'SelMic' 1300 4000), 'SelMic'), '|') 1300 4050
$nsw = Call $KSt 'StartsWith' 1700 3850; Wire $nkj 'Output' $nsw 'SourceString'; Wire $npre 'ReturnValue' $nsw 'InPrefix'
$nbj = Branch 1100 3400; Wire $nfl 'LoopBody' $nbj 'execute'; Wire $nsw 'ReturnValue' $nbj 'Condition'
$nr1 = Arr-Call 'Array_Remove' 'EditKeys' 1400 3300; Wire $nbj 'then' $nr1 'execute'; Wire $nj 'ReturnValue' $nr1 'IndexToRemove'
$nr2 = Arr-Call 'Array_Remove' 'EditColors' 1700 3300; Wire $nr1 'then' $nr2 'execute'; Wire $nj 'ReturnValue' $nr2 'IndexToRemove'
$nmi = Sel-Mic 2000 3800
$c = @{ N = $nfl; P = 'Completed' }
$xp = 2000
foreach ($p in $AllParams) {
    $ngv = Call $MIC 'K2_GetVectorParameterValue' $xp 3400; $c = Step $c $ngv; Wire $nmi 'Output' $ngv 'self'; Def $ngv 'ParameterName' 'name' $p
    $nap = CallSelf 'ApplyParam' ($xp + 250) 3400; $c = Step $c $nap
    Wire (Get-Var 'SelMic' ($xp + 100) 3600) 'SelMic' $nap 'Mic'; Def $nap 'Param' 'name' $p; Wire $ngv 'ReturnValue' $nap 'Color'
    $xp += 500
}
foreach ($ev in @('RefreshRows', 'RefreshPicker', 'SaveEdits')) { $c = Step $c (CallSelf $ev $xp 3400); $xp += 250 }
$nsay = CallSelf 'Say' $xp 3400; $c = Step $c $nsay; Def $nsay 'Msg' 'string' 'Part reset to the original.'
# CommitColor: a pick is final (slider let go, swatch, wheel let go): save + recent
$e = CustomEvent 'CommitColor' 0 6000
$ncs1 = CallSelf 'SaveEdits' 250 6000; Wire $e 'then' $ncs1 'execute'
$ncr1 = CallSelf 'AddRecent' 500 6000; Wire $ncs1 'then' $ncr1 'execute'; Wire (Get-Var 'LastPick' 400 6200) 'LastPick' $ncr1 'Color'
Save-Graph 'panel_3.txt'

# ================================================================ paste 4
New-Graph 14
# SelectPart(Index)
$e = CustomEvent 'SelectPart' 0 0 @('Index=int')
$ns1 = Set-Var $e 'then' 'SelPart' $e 'Index' 250 0
$ngi = Get-ArrItem (Get-Var 'PartMICs' 250 250) 'PartMICs' @($e, 'Index') 450 250
$non = Call $KS 'GetObjectName' 650 250; Wire $ngi 'Output' $non 'Object'
$ns2 = Set-Var $ns1 'then' 'SelMic' $non 'ReturnValue' 500 0
$c = @{ N = $ns2; P = 'then' }
for ($k = 0; $k -lt 16; $k++) {
    $nis = Math2 'EqualEqual_IntInt' @($e, 'Index') $k (800 + 300 * $k) 300
    $nsc = Call $KM 'SelectColor' (900 + 300 * $k) 400; Def $nsc 'A' $LC $ColSel; Def $nsc 'B' $LC $ColBtn; Wire $nis 'ReturnValue' $nsc 'bPickA'
    $nbc = Set-BtnColor $c.N $c.P "P$k" @($nsc, 'ReturnValue') (800 + 300 * $k) 0
    $c = @{ N = $nbc; P = 'then' }
}
$nsr = CallSelf 'SelectRow' 6000 0; $c = Step $c $nsr; Def $nsr 'Row' 'int' '0'; Def $nsr 'Side' 'int' '0'

# ResetAll: every part of this hero
$e = CustomEvent 'ResetAll' 0 800
$nlen = Arr-Call 'Array_Length' 'PartMICs' 100 1000
$nlast = Math2 'Subtract_IntInt' @($nlen, 'ReturnValue') 1 300 1000
$nfl = Macro 'ForLoop' '' 500 800; Def $nfl 'FirstIndex' 'int' '0'; Wire $nlast 'ReturnValue' $nfl 'LastIndex'; Wire $e 'then' $nfl 'execute'
$ns1 = Set-Var $nfl 'LoopBody' 'SelPart' $nfl 'Index' 800 800
$ngi = Get-ArrItem (Get-Var 'PartMICs' 800 1100) 'PartMICs' @($nfl, 'Index') 1000 1100
$non = Call $KS 'GetObjectName' 1200 1100; Wire $ngi 'Output' $non 'Object'
$ns2 = Set-Var $ns1 'then' 'SelMic' $non 'ReturnValue' 1050 800
$nrp = CallSelf 'ResetPart' 1300 800; Wire $ns2 'then' $nrp 'execute'
$ns3 = Set-VarLit $nfl 'Completed' 'SelPart' 'int' '0' 800 600
$ng0 = Get-ArrItem (Get-Var 'PartMICs' 900 450) 'PartMICs' 0 1100 450
$no0 = Call $KS 'GetObjectName' 1300 450; Wire $ng0 'Output' $no0 'Object'
$ns4 = Set-Var $ns3 'then' 'SelMic' $no0 'ReturnValue' 1050 600
$c = @{ N = $ns4; P = 'then' }
foreach ($ev in @('RefreshRows', 'RefreshPicker')) { $c = Step $c (CallSelf $ev (1300 + 250 * $c.Count) 600) }
$nsay = CallSelf 'Say' 1900 600; $c = Step $c $nsay; Def $nsay 'Msg' 'string' 'Every part is back to the original.'

# the picker (2026-09-28, her ask: a colour wheel, RGB sliders, recent colours).
# The game's Tint is a LINEAR multiply; the wheel and the R/G/B sliders are
# sRGB (what the eye and the wheel image show), so every pick goes through
# x^2.2 per channel. Light scales the result: 0.5 on the slider = the colour
# as the wheel shows it (x1), the top end doubles it.
function Pow-Of($nSrc, [string]$nPin, [string]$exp, [int]$x, [int]$y) {
    $n = Call $KM 'MultiplyMultiply_FloatFloat' $x $y; Wire $nSrc $nPin $n 'Base'; Def $n 'Exp' 'real' $exp
    $n
}
# sRGB r,g,b (0..1) x light -> a linear colour node
function Lin-From-Srgb($nR, [string]$pR, $nG, [string]$pG, $nB, [string]$pB, $nL, [string]$pL, [int]$x, [int]$y) {
    $nmc = Call $KM 'MakeColor' ($x + 450) $y; Def $nmc 'A' 'float' '1.000000'
    $k = 0
    foreach ($pair in @(@($nR, $pR, 'R'), @($nG, $pG, 'G'), @($nB, $pB, 'B'))) {
        $np = Pow-Of $pair[0] $pair[1] '2.200000' $x ($y + 120 * $k)
        if ($nL) {
            $nm = Call $KM 'Multiply_DoubleDouble' ($x + 220) ($y + 120 * $k); Wire $np 'ReturnValue' $nm 'A'; Wire $nL $pL $nm 'B'
            Wire $nm 'ReturnValue' $nmc $pair[2]
        } else { Wire $np 'ReturnValue' $nmc $pair[2] }
        $k++
    }
    $nmc
}
# Light slider 0..1 -> multiplier 0..2
function Light-Mult([int]$x, [int]$y) {
    $ngv = Call-On 'SlV' $SLD 'GetValue' $x $y
    Math2 'Multiply_DoubleDouble' @($ngv, 'ReturnValue') '2.000000' ($x + 250) $y 'real'
}
# sliders let go / swatch / recent: remember the colour and save
function Commit-After($nFrom, [string]$nPin, [int]$x, [int]$y) {
    $n = CallSelf 'CommitColor' $x $y; Wire $nFrom $nPin $n 'execute'; $n
}
# R / G / B: any move -> PickColor
$y0 = 1600
foreach ($sv in @('SlR', 'SlG', 'SlB')) {
    $ne = Bound-Event $sv $SLD 'OnValueChanged' 'OnFloatValueChangedEvent__DelegateSignature' 0 $y0
    OutPin $ne 'Value' 'float'
    $gr = Call-On 'SlR' $SLD 'GetValue' 200 ($y0 + 150)
    $gg = Call-On 'SlG' $SLD 'GetValue' 200 ($y0 + 300)
    $gb = Call-On 'SlB' $SLD 'GetValue' 200 ($y0 + 450)
    $nlm = Light-Mult 200 ($y0 + 600)
    $nlc = Lin-From-Srgb $gr 'ReturnValue' $gg 'ReturnValue' $gb 'ReturnValue' $nlm 'ReturnValue' 500 ($y0 + 150)
    $npc = CallSelf 'PickColor' 1100 $y0; Wire $ne 'then' $npc 'execute'; Wire $nlc 'ReturnValue' $npc 'Color'
    $nce = Bound-Event $sv $SLD 'OnMouseCaptureEnd' 'OnMouseCaptureEndEvent__DelegateSignature' 1400 $y0
    $null = Commit-After $nce 'then' 1700 $y0
    $y0 += 700
}
# Light: the same R/G/B slider colour, new light (one model with the R/G/B sliders)
$ne = Bound-Event 'SlV' $SLD 'OnValueChanged' 'OnFloatValueChangedEvent__DelegateSignature' 0 $y0
OutPin $ne 'Value' 'float'
$gr = Call-On 'SlR' $SLD 'GetValue' 800 ($y0 + 200)
$gg = Call-On 'SlG' $SLD 'GetValue' 800 ($y0 + 300)
$gb = Call-On 'SlB' $SLD 'GetValue' 800 ($y0 + 400)
$nlm = Light-Mult 1100 ($y0 + 550)
$nlc = Lin-From-Srgb $gr 'ReturnValue' $gg 'ReturnValue' $gb 'ReturnValue' $nlm 'ReturnValue' 1400 ($y0 + 200)
$npc = CallSelf 'PickColor' 2100 $y0; Wire $ne 'then' $npc 'execute'; Wire $nlc 'ReturnValue' $npc 'Color'
$nce = Bound-Event 'SlV' $SLD 'OnMouseCaptureEnd' 'OnMouseCaptureEndEvent__DelegateSignature' 2400 $y0
$null = Commit-After $nce 'then' 2700 $y0
$y0 += 800
# the wheel: held down = follow the mouse every frame (Tick), let go = commit
$ne = On-Pressed 'WheelB' 0 $y0
$null = Set-VarLit $ne 'then' 'WheelDown' 'bool' 'true' 300 $y0
$ne = On-Released 'WheelB' 0 ($y0 + 250)
$nwf = Set-VarLit $ne 'then' 'WheelDown' 'bool' 'false' 300 ($y0 + 250)
$null = Commit-After $nwf 'then' 550 ($y0 + 250)
$y0 += 600
$nt = OverrideEvent $UW 'Tick' 0 $y0
$nbw = Branch 250 $y0; Wire $nt 'then' $nbw 'execute'; Wire (Get-Var 'WheelDown' 100 ($y0 + 150)) 'WheelDown' $nbw 'Condition'
$nmp = Call $WL 'GetMousePositionOnPlatform' 500 $y0; Wire $nbw 'then' $nmp 'execute'
$nwv = GetMember 'WheelB' 500 ($y0 + 250)
$ngeo = Call $WG 'GetCachedGeometry' 650 ($y0 + 250); Wire $nwv 'WheelB' $ngeo 'self'
$nal = Call '/Script/UMG.SlateBlueprintLibrary' 'AbsoluteToLocal' 900 ($y0 + 150); Wire $ngeo 'ReturnValue' $nal 'Geometry'; Wire $nmp 'ReturnValue' $nal 'AbsoluteCoordinate'
$nls = Call '/Script/UMG.SlateBlueprintLibrary' 'GetLocalSize' 900 ($y0 + 350); Wire $ngeo 'ReturnValue' $nls 'Geometry'
$nb1 = Call $KM 'BreakVector2D' 1100 ($y0 + 150); Wire $nal 'ReturnValue' $nb1 'InVec'
$nb2 = Call $KM 'BreakVector2D' 1100 ($y0 + 350); Wire $nls 'ReturnValue' $nb2 'InVec'
# u, v in -1..1 from the centre
$uv = @{}
foreach ($ax in @('X', 'Y')) {
    $nsz = Call $KM 'FMax' 1300 ($y0 + 350 + 60 * $uv.Count); Wire $nb2 $ax $nsz 'A'; Def $nsz 'B' 'real' '1.000000'
    $nd = Call $KM 'Divide_DoubleDouble' 1450 ($y0 + 150 + 120 * $uv.Count); Wire $nb1 $ax $nd 'A'; Wire $nsz 'ReturnValue' $nd 'B'
    $nm = Math2 'Multiply_DoubleDouble' @($nd, 'ReturnValue') '2.000000' 1650 ($y0 + 150 + 120 * $uv.Count) 'real'
    $uv[$ax] = Math2 'Subtract_DoubleDouble' @($nm, 'ReturnValue') '1.000000' 1850 ($y0 + 150 + 120 * $uv.Count) 'real'
}
$nmv = Call $KM 'MakeVector2D' 2050 ($y0 + 350); Wire $uv['X'] 'ReturnValue' $nmv 'X'; Wire $uv['Y'] 'ReturnValue' $nmv 'Y'
$nr = Call $KM 'VSize2D' 2250 ($y0 + 350); Wire $nmv 'ReturnValue' $nr 'A'
$nsat = Call $KM 'FMin' 2450 ($y0 + 350); Wire $nr 'ReturnValue' $nsat 'A'; Def $nsat 'B' 'real' '1.000000'
$nang = Call $KM 'DegAtan2' 2050 ($y0 + 150); Wire $uv['Y'] 'ReturnValue' $nang 'Y'; Wire $uv['X'] 'ReturnValue' $nang 'X'
$nneg = Math2 'Less_DoubleDouble' @($nang, 'ReturnValue') '0.000000' 2250 ($y0 + 50) 'real'
$nadd = Math2 'Add_DoubleDouble' @($nang, 'ReturnValue') '360.000000' 2250 ($y0 + 150) 'real'
$nhue = Call $KM 'SelectFloat' 2450 ($y0 + 150); Wire $nadd 'ReturnValue' $nhue 'A'; Wire $nang 'ReturnValue' $nhue 'B'; Wire $nneg 'ReturnValue' $nhue 'bPickA'
# the wheel shows HSV at full value in sRGB; Light scales it
$nhc = Call $KM 'HSVToRGB' 2650 ($y0 + 150); Wire $nhue 'ReturnValue' $nhc 'H'; Wire $nsat 'ReturnValue' $nhc 'S'; Def $nhc 'V' 'float' '1.000000'; Def $nhc 'A' 'float' '1.000000'
$nbk = Call $KM 'BreakColor' 2850 ($y0 + 150); Wire $nhc 'ReturnValue' $nbk 'InColor'
$nlm = Light-Mult 2850 ($y0 + 450)
$nlc = Lin-From-Srgb $nbk 'R' $nbk 'G' $nbk 'B' $nlm 'ReturnValue' 3100 ($y0 + 150)
$npc = CallSelf 'PickColor' 3800 $y0; Wire $nmp 'then' $npc 'execute'; Wire $nlc 'ReturnValue' $npc 'Color'
# the sliders follow the wheel (before, they kept the old colour and the next slider move jumped back to it)
$nrp = CallSelf 'RefreshPicker' 4050 $y0; Wire $npc 'then' $nrp 'execute'
$y0 += 800
# recent colours: pick it again (it moves to the front)
for ($i = 0; $i -lt $RecentSlots; $i++) {
    $ne = On-Click ('Rc' + $i) 0 $y0
    $nit = Get-ArrItem (Get-Var 'RecentColors' 100 ($y0 + 150)) 'RecentColors' $i 300 ($y0 + 150)
    $npc = CallSelf 'PickColor' 300 $y0; Wire $ne 'then' $npc 'execute'; Wire $nit 'Output' $npc 'Color'
    $nrp = CallSelf 'RefreshPicker' 550 $y0; Wire $npc 'then' $nrp 'execute'
    $null = Commit-After $nrp 'then' 800 $y0
    $y0 += 250
}
# (the 24-colour palette went 2026-09-28, her call: the wheel, sliders and recent strip replace it)
# rows: the label or the first swatch picks side 0, a zone's second swatch side 1
for ($r = 0; $r -lt 16; $r++) {
    $sides = @(@("RB$r", 0), @("RA$r", 0))
    if ($r -ge 9) { $sides += , @("RC$r", 1) }
    foreach ($s in $sides) {
        $ne = On-Click $s[0] 1400 $y0
        $nsr = CallSelf 'SelectRow' 1700 $y0; Wire $ne 'then' $nsr 'execute'; Def $nsr 'Row' 'int' ([string]$r); Def $nsr 'Side' 'int' ([string]$s[1])
        $y0 += 200
    }
}
$ne = On-Click 'BtnResetOne' 2400 4000; $nx = CallSelf 'ResetOne' 2700 4000; Wire $ne 'then' $nx 'execute'
$ne = On-Click 'BtnResetPart' 2400 4200; $nx = CallSelf 'ResetPart' 2700 4200; Wire $ne 'then' $nx 'execute'
Save-Graph 'panel_4.txt'

# ================================================================ paste 5
New-Graph 15
# Refresh: the hero's parts -> the part buttons
$e = CustomEvent 'Refresh' 0 0
$ncl = Arr-Call 'Array_Clear' 'PartMICs' 250 0; Wire $e 'then' $ncl 'execute'
$rfBody = {
    param($nEx, $nExPin, $nComp, $nCompPin, $nLoop, [int]$x, [int]$y)
    $sm = Slot-Mic $nEx $nExPin $nComp $nCompPin $nLoop $x $y
    Wire $sm.MidCast 'then' $sm.MicCast 'execute'; Wire $sm.MidCast 'CastFailed' $sm.MicCast 'execute'
    $nau = Arr-Call 'Array_AddUnique' 'PartMICs' ($x + 1400) $y; Wire $sm.MicCast 'then' $nau 'execute'
    Wire $sm.MicCast 'AsMaterial Instance Constant' $nau 'NewItem'
}
$w = Walk-Slots $ncl 'then' $rfBody 500 0
$nlen = Arr-Call 'Array_Length' 'PartMICs' 400 1200
$c = $null
$xk = 800
for ($k = 0; $k -lt 16; $k++) {
    $nlt = Math2 'Less_IntInt' $k @($nlen, 'ReturnValue') ($xk) 1300
    $nbk = Branch ($xk + 100) 1000
    if ($k -eq 0) { Wire $w.Done 'Completed' $nbk 'execute'; Wire $w.Branch 'else' $nbk 'execute' } else { $null = Step $c $nbk }
    Wire $nlt 'ReturnValue' $nbk 'Condition'
    $nvs = Set-Vis $nbk 'then' "P$k" 'Visible' ($xk + 300) 900
    # label: MI_<skin>_<Part_Name> -> "Part Name"
    $ngi = Get-ArrItem (Get-Var 'PartMICs' ($xk) 1500) 'PartMICs' $k ($xk + 200) 1500
    $non = Call $KS 'GetObjectName' ($xk + 400) 1500; Wire $ngi 'Output' $non 'Object'
    $ntk = Call $KSt 'ParseIntoArray' ($xk + 600) 1500; Wire $non 'ReturnValue' $ntk 'SourceString'; Def $ntk 'Delimiter' 'string' '_'; Def $ntk 'CullEmptyStrings' 'bool' 'true'
    $nt1 = Get-ArrItem $ntk 'ReturnValue' 1 ($xk + 800) 1500
    $nl1 = Call $KSt 'Len' ($xk + 1000) 1500; Wire $nt1 'Output' $nl1 'S'
    $ncut = Math2 'Add_IntInt' @($nl1, 'ReturnValue') 4 ($xk + 1200) 1500
    $nrc = Call $KSt 'RightChop' ($xk + 1400) 1500; Wire $non 'ReturnValue' $nrc 'SourceString'; Wire $ncut 'ReturnValue' $nrc 'Count'
    $nrp = Call $KSt 'Replace' ($xk + 1600) 1500; Wire $nrc 'ReturnValue' $nrp 'SourceString'; Def $nrp 'From' 'string' '_'; Def $nrp 'To' 'string' ' '
    $nst = Set-BtnText $nvs 'then' "P$k" @($nrp, 'ReturnValue') ($xk + 600) 900
    $nvh = Set-Vis $nbk 'else' "P$k" 'Collapsed' ($xk + 300) 1100
    $c = @(@{ N = $nst; P = 'then' }, @{ N = $nvh; P = 'then' })
    $xk += 1900
}
$nhas = Math2 'Greater_IntInt' @($nlen, 'ReturnValue') 0 ($xk) 1300
$nbh = Branch ($xk + 100) 1000; $null = Step $c $nbh; Wire $nhas 'ReturnValue' $nbh 'Condition'
$nsp = CallSelf 'SelectPart' ($xk + 350) 900; Wire $nbh 'then' $nsp 'execute'; Def $nsp 'Index' 'int' '0'
$ns1 = CallSelf 'Say' ($xk + 600) 900; Wire $nsp 'then' $ns1 'execute'; Def $ns1 'Msg' 'string' 'Pick a part, then a colour. Saved colours come back every match.'
$ns2 = CallSelf 'Say' ($xk + 350) 1100; Wire $nbh 'else' $ns2 'execute'; Def $ns2 'Msg' 'string' 'No hero found - open this in a match or the practice range.'
# part buttons
for ($k = 0; $k -lt 16; $k++) {
    $ne = On-Click "P$k" 0 (2400 + 200 * $k)
    $nsp = CallSelf 'SelectPart' 300 (2400 + 200 * $k); Wire $ne 'then' $nsp 'execute'; Def $nsp 'Index' 'int' ([string]$k)
}
$ne = On-Click 'BtnResetAll' 700 2400; $nx = CallSelf 'ResetAll' 1000 2400; Wire $ne 'then' $nx 'execute'
Save-Graph 'panel_5.txt'

# ================================================================ paste 6
New-Graph 16
# Open: only in a match (the lobby hero is not reachable, and a menu screen
# must not lose its cursor)
$e = CustomEvent 'Open' 0 0
$npp = Call $GS 'GetPlayerPawn' 0 160; Def $npp 'PlayerIndex' 'int' '0'
$niv = Call $KS 'IsValid' 200 160; Wire $npp 'ReturnValue' $niv 'Object'
$nb0 = Branch 250 0; Wire $e 'then' $nb0 'execute'; Wire $niv 'ReturnValue' $nb0 'Condition'
$c = @{ N = $nb0; P = 'then' }
$c = Step $c (CallSelf 'LoadEdits' 500 0)
$c = Step $c (CallSelf 'RefreshDesigns' 600 150)
$c = Step $c (CallSelf 'LoadRecent' 650 250)
$c = Step $c (CallSelf 'Refresh' 750 0)
$nvr = Set-Vis $c.N $c.P 'PanelRoot' 'SelfHitTestInvisible' 1000 0; $c = @{ N = $nvr; P = 'then' }
# 1080p pixels: (viewport height / 1080) / Rivals' UMG DPI scale
$nvs = Call $WL 'GetViewportSize' 1000 300
$nbv = Call $KM 'BreakVector2D' 1200 300; Wire $nvs 'ReturnValue' $nbv 'InVec'
$nd1 = Math2 'Divide_DoubleDouble' @($nbv, 'Y') '1080.000000' 1400 300 'real'
$nds = Call $WL 'GetViewportScale' 1400 450
$nd2 = Math2 'Divide_DoubleDouble' @($nd1, 'ReturnValue') @($nds, 'ReturnValue') 1600 300 'real'
# the ScaleBox is PanelRoot's only child (Boxes are not Blueprint variables)
$nrt = GetMember 'PanelRoot' 1100 150
$nca = Call '/Script/UMG.PanelWidget' 'GetChildAt' 1250 150; Wire $nrt 'PanelRoot' $nca 'self'; Def $nca 'Index' 'int' '0'
$ncs = Cast '/Script/UMG.ScaleBox' 1300 0; $c = Step $c $ncs; Wire $nca 'ReturnValue' $ncs 'Object'
$nus = Call '/Script/UMG.ScaleBox' 'SetUserSpecifiedScale' 1550 0; $c = Step $c $nus; Wire $ncs 'AsScale Box' $nus 'self'; Wire $nd2 'ReturnValue' $nus 'InUserSpecifiedScale'
$npc = Call $GS 'GetPlayerController' 1600 700; Def $npc 'PlayerIndex' 'int' '0'
$hg = Hud-Guard $npc 1700 -300; $null = Step $c $hg.Branch
$need = Call '/Script/Engine.Actor' 'RemoveTickPrerequisiteActor' 2500 -400
Wire $hg.Branch 'then' $need 'execute'; Wire $hg.Hud 'ReturnValue' $need 'self'
$nim = Call $WB 'SetInputMode_GameAndUIEx' 2500 0; Wire $hg.Branch 'else' $nim 'execute'; Wire $npc 'ReturnValue' $nim 'PlayerController'
Def $nim 'InMouseLockMode' 'byte:/Script/Engine.EMouseLockMode' 'DoNotLock'; Def $nim 'bHideCursorDuringCapture' 'bool' 'false'; Def $nim 'bFlushInput' 'bool' 'false'
$ncur = SetVarOf '/Script/Engine.PlayerController' 'bShowMouseCursor' 2800 0
Wire $nim 'then' $ncur 'execute'; Wire $need 'then' $ncur 'execute'; Wire $npc 'ReturnValue' $ncur 'self'; Def $ncur 'bShowMouseCursor' 'bool' 'true'

# Close: hide, save, give the mouse back - only while open (the HUD counts
# Need/Stop pairs, and a Stop without its Need would break the game's menus)
$e = CustomEvent 'Close' 0 1400
$nvi = Call-On 'PanelRoot' $WG 'IsVisible' 100 1550
$nbc = Branch 300 1400; Wire $e 'then' $nbc 'execute'; Wire $nvi 'ReturnValue' $nbc 'Condition'
$nvc = Set-Vis $nbc 'then' 'PanelRoot' 'Collapsed' 500 1400
$nsv = CallSelf 'SaveEdits' 800 1400; Wire $nvc 'then' $nsv 'execute'
$npc = Call $GS 'GetPlayerController' 1000 1800; Def $npc 'PlayerIndex' 'int' '0'
$hg = Hud-Guard $npc 1100 1400; Wire $nsv 'then' $hg.Branch 'execute'
$stop = Call '/Script/Engine.Actor' 'ForceNetUpdate' 1900 1300
Wire $hg.Branch 'then' $stop 'execute'; Wire $hg.Hud 'ReturnValue' $stop 'self'
$ngm = Call $WB 'SetInputMode_GameOnly' 1900 1500; Wire $hg.Branch 'else' $ngm 'execute'; Wire $npc 'ReturnValue' $ngm 'PlayerController'
$ncur = SetVarOf '/Script/Engine.PlayerController' 'bShowMouseCursor' 2150 1500
Wire $ngm 'then' $ncur 'execute'; Wire $npc 'ReturnValue' $ncur 'self'; Def $ncur 'bShowMouseCursor' 'bool' 'false'
Save-Graph 'panel_6.txt'

# ================================================================ paste 7
New-Graph 17
$e = CustomEvent 'Toggle' 0 0
$nvi = Call-On 'PanelRoot' $WG 'IsVisible' 100 150
$nb = Branch 300 0; Wire $e 'then' $nb 'execute'; Wire $nvi 'ReturnValue' $nb 'Condition'
$ncl = CallSelf 'Close' 550 -60; Wire $nb 'then' $ncl 'execute'
$nop = CallSelf 'Open' 550 80; Wire $nb 'else' $nop 'execute'
$ne = On-Click 'BtnClose' 0 400; $nx = CallSelf 'Close' 300 400; Wire $ne 'then' $nx 'execute'
Save-Graph 'panel_7.txt'

# ================================================================ paste 8
# Studio: hand over to the app's panel (textures, designs, Build mod). Only
# while the app listens (SkinLiveOn, written by its watcher, removed when it
# stops). The app panel lives in this container too; it is found or made by
# class PATH and opened BY NAME (Set Timer by Function Name), so nothing of it
# has to exist in this Unreal project.
New-Graph 19
$ne = On-Click 'BtnStudio' 0 0
$nso = Call $GS 'DoesSaveGameExist' 250 160; Def $nso 'SlotName' 'string' 'SkinLiveOn'; Def $nso 'UserIndex' 'int' '0'
Wire $ne 'then' $nso 'execute'
$nsb = Branch 500 0; Wire $nso 'then' $nsb 'execute'; Wire $nso 'ReturnValue' $nsb 'Condition'
$nsy = CallSelf 'Say' 750 300; Wire $nsb 'else' $nsy 'execute'
Def $nsy 'Msg' 'string' 'Open the Skin Studio app on your PC for textures and Build mod.'
$nsc = CallSelf 'Close' 750 0; Wire $nsb 'then' $nsc 'execute'
$nep = Call $KS 'MakeSoftClassPath' 800 -250; Def $nep 'PathString' 'string' '/Game/Marvel/SkinLive/UI/Widgets/WBP_SkinLiveEditor.WBP_SkinLiveEditor_C'
$ner = Call $KS 'Conv_SoftClassPathToSoftClassRef' 1050 -250; Wire $nep 'ReturnValue' $ner 'SoftClassPath'
$nel = Call $KS 'LoadClassAsset_Blocking' 1000 0; Wire $nsc 'then' $nel 'execute'; Wire $ner 'ReturnValue' $nel 'AssetClass'
$nec = Add-Node '/Script/BlueprintGraph.K2Node_ClassDynamicCast' @("TargetType=Class'`"/Script/UMG.UserWidget`"'") 1250 0
Wire $nel 'then' $nec 'execute'; Wire $nel 'ReturnValue' $nec 'Class'
$nsf = CallSelf 'Say' 1500 300; Wire $nec 'CastFailed' $nsf 'execute'; Def $nsf 'Msg' 'string' 'The app panel is not in this build.'
$nfw = Call $WB 'GetAllWidgetsOfClass' 1500 0; Wire $nec 'then' $nfw 'execute'; Wire $nec 'AsUser Widget' $nfw 'WidgetClass'; Def $nfw 'TopLevelOnly' 'bool' 'false'
$nen = CallArray 'Array_Length' 1700 160; Wire $nfw 'FoundWidgets' $nen 'TargetArray'
$neg = Call $KM 'Greater_IntInt' 1900 160; Wire $nen 'ReturnValue' $neg 'A'; Def $neg 'B' 'int' '0'
$neb = Branch 1800 0; Wire $nfw 'then' $neb 'execute'; Wire $neg 'ReturnValue' $neb 'Condition'
$nei = Get-ArrItem $nfw 'FoundWidgets' 0 1900 -200
$net = Call $KS 'K2_SetTimer' 2150 -100; Wire $neb 'then' $net 'execute'; Wire $nei 'Output' $net 'Object'
Def $net 'FunctionName' 'string' 'Open'; Def $net 'Time' 'float' '0.050000'; Def $net 'bLooping' 'bool' 'false'
$neq = Call $GS 'GetPlayerController' 1950 350; Def $neq 'PlayerIndex' 'int' '0'
$nek = Add-Node '/Script/UMGEditor.K2Node_CreateWidget' @() 2100 150
Wire $neb 'else' $nek 'execute'; Wire $nec 'AsUser Widget' $nek 'Class'; Wire $neq 'ReturnValue' $nek 'OwningPlayer'
$nea = Call $UW 'AddToViewport' 2400 150; Wire $nek 'then' $nea 'execute'; Wire $nek 'ReturnValue' $nea 'self'; Def $nea 'ZOrder' 'int' '50'
$ne2 = Call $KS 'K2_SetTimer' 2650 150; Wire $nea 'then' $ne2 'execute'; Wire $nek 'ReturnValue' $ne2 'Object'
Def $ne2 'FunctionName' 'string' 'Open'; Def $ne2 'Time' 'float' '0.050000'; Def $ne2 'bLooping' 'bool' 'false'
Save-Graph 'panel_8.txt'

# ================================================================ paste 9
# Build mod: the colours made here -> a real mod, zip in Downloads, without
# leaving the game. Packing needs the PC: the helper (ingame\helper.ps1, which
# writes SkinStudioHelper.sav while Rivals runs) sees SSBuild_<MI name>.sav and
# runs standalone\build_colours.ps1 for that skin.
New-Graph 20
$ne = On-Click 'BtnBuild' 0 0
$nbh = Call $GS 'DoesSaveGameExist' 250 160; Def $nbh 'SlotName' 'string' 'SkinStudioHelper'; Def $nbh 'UserIndex' 'int' '0'
Wire $ne 'then' $nbh 'execute'
$nbb = Branch 500 0; Wire $nbh 'then' $nbb 'execute'; Wire $nbh 'ReturnValue' $nbb 'Condition'
$nb1 = CallSelf 'Say' 750 300; Wire $nbb 'else' $nb1 'execute'
Def $nb1 'Msg' 'string' 'Build mod needs the Skin Studio app installed on this PC.'
$nbs = CallSelf 'SaveEdits' 750 0; Wire $nbb 'then' $nbs 'execute'
$nbi = Get-ArrItem (Get-Var 'PartMICs' 800 200) 'PartMICs' 0 1000 200
$nbv = Call $KS 'IsValid' 1200 200; Wire $nbi 'Output' $nbv 'Object'
$nbc = Branch 1000 0; Wire $nbs 'then' $nbc 'execute'; Wire $nbv 'ReturnValue' $nbc 'Condition'
$nb2 = CallSelf 'Say' 1250 300; Wire $nbc 'else' $nb2 'execute'; Def $nb2 'Msg' 'string' 'Open this in a match first.'
$nbn = Call $KS 'GetObjectName' 1250 150; Wire $nbi 'Output' $nbn 'Object'
$nbk = Call $KSt 'Concat_StrStr' 1450 150; Def $nbk 'A' 'string' 'SSBuild_'; Wire $nbn 'ReturnValue' $nbk 'B'
$nbl = Call $GS 'LoadGameFromSlot' 1300 0; Def $nbl 'SlotName' 'string' 'HighlightSettings'; Def $nbl 'UserIndex' 'int' '0'
Wire $nbc 'then' $nbl 'execute'
$nbw = Call $GS 'SaveGameToSlot' 1550 0; Wire $nbl 'then' $nbw 'execute'; Wire $nbl 'ReturnValue' $nbw 'SaveGameObject'
Wire $nbk 'ReturnValue' $nbw 'SlotName'; Def $nbw 'UserIndex' 'int' '0'
$nb3 = CallSelf 'Say' 1800 0; Wire $nbw 'then' $nb3 'execute'
Def $nb3 'Msg' 'string' 'Building your colours into a mod. The zip lands in Downloads in about a minute.'
Save-Graph 'panel_9.txt'

# ================================================================ paste 10
# MarkDirty clears every MID's SSMark, so the next 1 s pulse repaints them all
# (LoadDesign uses it: a loaded design's colours go on at once).
New-Graph 21
$e = CustomEvent 'MarkDirty' 0 0
$mdBody = {
    param($nEx, $nExPin, $nComp, $nCompPin, $nLoop, [int]$x, [int]$y)
    $sm = Slot-Mic $nEx $nExPin $nComp $nCompPin $nLoop $x $y
    $nss = Call $MID 'SetScalarParameterValue' ($x + 700) $y; Wire $sm.MidCast 'then' $nss 'execute'
    Wire $sm.MidCast 'AsMaterial Instance Dynamic' $nss 'self'; Def $nss 'ParameterName' 'name' 'SSMark'; Def $nss 'Value' 'float' '0.000000'
}
$null = Walk-Slots $e 'then' $mdBody 300 0
Save-Graph 'panel_10.txt'

# ================================================================ paste 11
# LoadDesign(Name): SSD_<Name> becomes the colour save: the hero goes back to
# vanilla first (ResetAll), then the design's colours go on (LoadEdits +
# MarkDirty repaint). SSLoad_<Name>.sav asks the app's helper, if there is one,
# to paint the design's textures too.
New-Graph 23
$e = CustomEvent 'LoadDesign' 0 0 @('Name=string')
$nkd = Concat-Chain @('SSD_', @($e, 'Name')) 200 250
$nld = Call $GS 'LoadGameFromSlot' 300 0; Wire $nkd 'ReturnValue' $nld 'SlotName'; Def $nld 'UserIndex' 'int' '0'; Wire $e 'then' $nld 'execute'
$ncd = CastBP $SaveClass 550 0; Wire $nld 'then' $ncd 'execute'; Wire $nld 'ReturnValue' $ncd 'Object'
$nsf = CallSelf 'Say' 800 300; Wire $ncd 'CastFailed' $nsf 'execute'; Def $nsf 'Msg' 'string' 'That design is not here any more.'
$nra = CallSelf 'ResetAll' 800 0; Wire $ncd 'then' $nra 'execute'
$nsv = Call $GS 'SaveGameToSlot' 1050 0; Wire $nra 'then' $nsv 'execute'; Wire $ncd 'AsSkin Studio Save' $nsv 'SaveGameObject'
Def $nsv 'SlotName' 'string' $ColorSlot; Def $nsv 'UserIndex' 'int' '0'
$nlf = Set-VarLit $nsv 'then' 'Loaded' 'bool' 'false' 1300 0
$nle = CallSelf 'LoadEdits' 1550 0; Wire $nlf 'then' $nle 'execute'
$nmd = CallSelf 'MarkDirty' 1800 0; Wire $nle 'then' $nmd 'execute'
$nrf = CallSelf 'Refresh' 2050 0; Wire $nmd 'then' $nrf 'execute'
$nhl = Call $GS 'LoadGameFromSlot' 2300 0; Def $nhl 'SlotName' 'string' 'HighlightSettings'; Def $nhl 'UserIndex' 'int' '0'; Wire $nrf 'then' $nhl 'execute'
$nkl = Concat-Chain @('SSLoad_', @($e, 'Name')) 2400 250
$nrq = Call $GS 'SaveGameToSlot' 2550 0; Wire $nhl 'then' $nrq 'execute'; Wire $nhl 'ReturnValue' $nrq 'SaveGameObject'
Wire $nkl 'ReturnValue' $nrq 'SlotName'; Def $nrq 'UserIndex' 'int' '0'
$nms = Concat-Chain @('Loaded ', @($e, 'Name'), '.') 2700 250
$nsy = CallSelf 'Say' 2800 0; Wire $nrq 'then' $nsy 'execute'; Wire $nms 'ReturnValue' $nsy 'Msg'
Save-Graph 'panel_11.txt'

# ================================================================ paste 12
# Save / Delete / the list. The name box is the first child of the Save
# button's row (text boxes are not Blueprint variables when made from Python).
New-Graph 24
function Name-Text([int]$x, [int]$y) {
    $nbv = GetMember 'BtnSaveD' $x ($y + 150)
    $ngp = Call $WG 'GetParent' ($x + 150) ($y + 150); Wire $nbv 'BtnSaveD' $ngp 'self'
    $nca = Call '/Script/UMG.PanelWidget' 'GetChildAt' ($x + 300) ($y + 150); Wire $ngp 'ReturnValue' $nca 'self'; Def $nca 'Index' 'int' '0'
    $ncb = Cast '/Script/UMG.EditableTextBox' ($x + 500) $y; Wire $nca 'ReturnValue' $ncb 'Object'
    $ngt = Call '/Script/UMG.EditableTextBox' 'GetText' ($x + 750) ($y + 150); Wire $ncb 'AsText Box' $ngt 'self'
    $nts = Call $KT 'Conv_TextToString' ($x + 950) ($y + 150); Wire $ngt 'ReturnValue' $nts 'InText'
    $ntr = Call $KSt 'Trim' ($x + 1150) ($y + 150); Wire $nts 'ReturnValue' $ntr 'SourceString'
    @{ Cast = $ncb; Str = $ntr }
}
# the list slot: SkinStudioDesigns with $Name removed, and put first when $add
function Index-Update($nFrom, [string]$nPin, $nName, [string]$nNamePin, [bool]$add, [int]$x, [int]$y) {
    $nli = Call $GS 'LoadGameFromSlot' $x $y; Def $nli 'SlotName' 'string' 'SkinStudioDesigns'; Def $nli 'UserIndex' 'int' '0'; Wire $nFrom $nPin $nli 'execute'
    $nci = CastBP $SaveClass ($x + 250) $y; Wire $nli 'then' $nci 'execute'; Wire $nli 'ReturnValue' $nci 'Object'
    # no list yet: a fresh save object
    $nco = Call $GS 'CreateSaveGameObject' ($x + 500) ($y + 300); Def $nco 'SaveGameClass' 'class:/Script/Engine.SaveGame' $SaveClass; Wire $nci 'CastFailed' $nco 'execute'
    $ncn = CastBP $SaveClass ($x + 750) ($y + 300); Wire $nco 'then' $ncn 'execute'; Wire $nco 'ReturnValue' $ncn 'Object'
    $nsel = Call $KM 'SelectObject' ($x + 1000) ($y + 500); Wire $nci 'AsSkin Studio Save' $nsel 'A'; Wire $ncn 'AsSkin Studio Save' $nsel 'B'
    $niv = Call $KS 'IsValid' ($x + 800) ($y + 600); Wire $nci 'AsSkin Studio Save' $niv 'Object'; Wire $niv 'ReturnValue' $nsel 'bSelectA'
    $nobj = CastBP $SaveClass ($x + 1250) $y; Wire $nci 'then' $nobj 'execute'; Wire $ncn 'then' $nobj 'execute'; Wire $nsel 'ReturnValue' $nobj 'Object'
    $nd = GetVarOfBP $SaveClass 'Data' ($x + 1250) ($y + 250); Wire $nobj 'AsSkin Studio Save' $nd 'self'
    $npa = Call $KSt 'ParseIntoArray' ($x + 1450) ($y + 250); Wire $nd 'Data' $npa 'SourceString'; Def $npa 'Delimiter' 'string' ';'; Def $npa 'CullEmptyStrings' 'bool' 'true'
    $nst = Set-Var $nobj 'then' 'Tmp' $npa 'ReturnValue' ($x + 1500) $y
    $nrm = Arr-Call 'Array_RemoveItem' 'Tmp' ($x + 1750) $y; Wire $nst 'then' $nrm 'execute'; Wire $nName $nNamePin $nrm 'Item'
    $last = $nrm
    if ($add) {
        $nin = Arr-Call 'Array_Insert' 'Tmp' ($x + 2000) $y; Wire $nrm 'then' $nin 'execute'; Wire $nName $nNamePin $nin 'NewItem'; Def $nin 'Index' 'int' '0'
        $last = $nin
    }
    $njs = Call $KSt 'JoinStringArray' ($x + 2250) ($y + 250); Wire (Get-Var 'Tmp' ($x + 2100) ($y + 250)) 'Tmp' $njs 'SourceArray'; Def $njs 'Separator' 'string' ';'
    $nsd = SetVarOfBP $SaveClass 'Data' ($x + 2300) $y; Wire $last 'then' $nsd 'execute'; Wire $nobj 'AsSkin Studio Save' $nsd 'self'; Wire $njs 'ReturnValue' $nsd 'Data'
    $nsg = Call $GS 'SaveGameToSlot' ($x + 2550) $y; Wire $nsd 'then' $nsg 'execute'; Wire $nobj 'AsSkin Studio Save' $nsg 'SaveGameObject'
    Def $nsg 'SlotName' 'string' 'SkinStudioDesigns'; Def $nsg 'UserIndex' 'int' '0'
    $nsg
}
# SaveDesign(Name, OpenApp): the colour save becomes SSD_<Name>, SSHero_ names
# the hero on screen (the app files the design under that skin), the list is
# updated; OpenApp also asks the helper to open it in Skin Studio (SSOpenApp_).
$e = CustomEvent 'SaveDesign' 0 0 @('Name=string', 'OpenApp=bool')
$nse = CallSelf 'SaveEdits' 250 0; Wire $e 'then' $nse 'execute'
$nlc = Call $GS 'LoadGameFromSlot' 500 0; Def $nlc 'SlotName' 'string' $ColorSlot; Def $nlc 'UserIndex' 'int' '0'; Wire $nse 'then' $nlc 'execute'
$ncc = CastBP $SaveClass 750 0; Wire $nlc 'then' $ncc 'execute'; Wire $nlc 'ReturnValue' $ncc 'Object'
$ns1 = CallSelf 'Say' 1000 400; Wire $ncc 'CastFailed' $ns1 'execute'; Def $ns1 'Msg' 'string' 'Make a colour change first, then save it.'
$nkd = Concat-Chain @('SSD_', @($e, 'Name')) 900 250
$nsd = Call $GS 'SaveGameToSlot' 1000 0; Wire $ncc 'then' $nsd 'execute'; Wire $ncc 'AsSkin Studio Save' $nsd 'SaveGameObject'
Wire $nkd 'ReturnValue' $nsd 'SlotName'; Def $nsd 'UserIndex' 'int' '0'
$nh0 = Get-ArrItem (Get-Var 'PartMICs' 1100 -500) 'PartMICs' 0 1300 -500
$nh1 = Call $KS 'GetObjectName' 1500 -500; Wire $nh0 'Output' $nh1 'Object'
$nh2 = Concat-Chain @('SSHero_', @($e, 'Name'), '__', @($nh1, 'ReturnValue')) 1500 -350
$nh3 = Call $GS 'LoadGameFromSlot' 1250 -200; Def $nh3 'SlotName' 'string' 'HighlightSettings'; Def $nh3 'UserIndex' 'int' '0'; Wire $nsd 'then' $nh3 'execute'
$nh4 = Call $GS 'SaveGameToSlot' 1500 -200; Wire $nh3 'then' $nh4 'execute'; Wire $nh3 'ReturnValue' $nh4 'SaveGameObject'
Wire $nh2 'ReturnValue' $nh4 'SlotName'; Def $nh4 'UserIndex' 'int' '0'
$niu = Index-Update $nh4 'then' $e 'Name' $true 1750 0
$nrd = CallSelf 'RefreshDesigns' 4600 0; Wire $niu 'then' $nrd 'execute'
$nbo = Branch 4850 0; Wire $nrd 'then' $nbo 'execute'; Wire $e 'OpenApp' $nbo 'Condition'
$nms = Concat-Chain @('Saved ', @($e, 'Name'), '.') 4900 350
$ns2 = CallSelf 'Say' 5100 300; Wire $nbo 'else' $ns2 'execute'; Wire $nms 'ReturnValue' $ns2 'Msg'
$no1 = Call $GS 'LoadGameFromSlot' 5100 0; Def $no1 'SlotName' 'string' 'HighlightSettings'; Def $no1 'UserIndex' 'int' '0'; Wire $nbo 'then' $no1 'execute'
$nok = Concat-Chain @('SSOpenApp_', @($e, 'Name')) 5200 -250
$no2 = Call $GS 'SaveGameToSlot' 5350 0; Wire $no1 'then' $no2 'execute'; Wire $no1 'ReturnValue' $no2 'SaveGameObject'
Wire $nok 'ReturnValue' $no2 'SlotName'; Def $no2 'UserIndex' 'int' '0'
$nom = Concat-Chain @('Saved ', @($e, 'Name'), ' - opening it in Skin Studio on your PC.') 5500 -250
$no3 = CallSelf 'Say' 5600 0; Wire $no2 'then' $no3 'execute'; Wire $nom 'ReturnValue' $no3 'Msg'
$ne = On-Click 'BtnDelD' 0 1500
$nt = Name-Text 200 1700
Wire $ne 'then' $nt.Cast 'execute'
$nln = Call $KSt 'Len' 1400 1850; Wire $nt.Str 'ReturnValue' $nln 'S'
$ngz = Math2 'Greater_IntInt' @($nln, 'ReturnValue') 0 1550 1850
$nbn = Branch 1500 1500; Wire $nt.Cast 'then' $nbn 'execute'; Wire $ngz 'ReturnValue' $nbn 'Condition'
$ns0 = CallSelf 'Say' 1750 1900; Wire $nbn 'else' $ns0 'execute'; Def $ns0 'Msg' 'string' 'Pick or type the design to delete first.'
$nkd = Concat-Chain @('SSD_', @($nt.Str, 'ReturnValue')) 1700 1750
$ndg = Call $GS 'DeleteGameInSlot' 1800 1500; Wire $nbn 'then' $ndg 'execute'; Wire $nkd 'ReturnValue' $ndg 'SlotName'; Def $ndg 'UserIndex' 'int' '0'
$niu = Index-Update $ndg 'then' $nt.Str 'ReturnValue' $false 2050 1500
$nrd = CallSelf 'RefreshDesigns' 4700 1500; Wire $niu 'then' $nrd 'execute'
$nms = Concat-Chain @('Deleted ', @($nt.Str, 'ReturnValue'), '.') 4800 1750
$ns2 = CallSelf 'Say' 4950 1500; Wire $nrd 'then' $ns2 'execute'; Wire $nms 'ReturnValue' $ns2 'Msg'
# the list: a name goes into the box and is loaded
for ($i = 0; $i -lt $DesignSlots; $i++) {
    $y0 = 3000 + 300 * $i
    $ne = On-Click ('D' + $i) 0 $y0
    $nit = Get-ArrItem (Get-Var 'DesignNames' 150 ($y0 + 150)) 'DesignNames' $i 350 ($y0 + 150)
    $nbv = GetMember 'BtnSaveD' 250 ($y0 + 250)
    $ngp = Call $WG 'GetParent' 400 ($y0 + 250); Wire $nbv 'BtnSaveD' $ngp 'self'
    $nca = Call '/Script/UMG.PanelWidget' 'GetChildAt' 550 ($y0 + 250); Wire $ngp 'ReturnValue' $nca 'self'; Def $nca 'Index' 'int' '0'
    $ncb = Cast '/Script/UMG.EditableTextBox' 700 $y0; Wire $ne 'then' $ncb 'execute'; Wire $nca 'ReturnValue' $ncb 'Object'
    $ntt = Call $KT 'Conv_StringToText' 800 ($y0 + 200); Wire $nit 'Output' $ntt 'InString'
    $nst = Call '/Script/UMG.EditableTextBox' 'SetText' 950 $y0; Wire $ncb 'then' $nst 'execute'; Wire $ncb 'AsText Box' $nst 'self'; Wire $ntt 'ReturnValue' $nst 'InText'
    $nld = CallSelf 'LoadDesign' 1200 $y0; Wire $nst 'then' $nld 'execute'; Wire $ncb 'CastFailed' $nld 'execute'; Wire $nit 'Output' $nld 'Name'
}
Save-Graph 'panel_12.txt'

# ================================================================ paste 13
# Save and Open in App: both call SaveDesign (compiled in paste 12)
New-Graph 25
$ne = On-Click 'BtnSaveD' 0 0
$nt = Name-Text 200 200
Wire $ne 'then' $nt.Cast 'execute'
$nln = Call $KSt 'Len' 1400 350; Wire $nt.Str 'ReturnValue' $nln 'S'
$ngz = Math2 'Greater_IntInt' @($nln, 'ReturnValue') 0 1550 350
$nbn = Branch 1500 0; Wire $nt.Cast 'then' $nbn 'execute'; Wire $ngz 'ReturnValue' $nbn 'Condition'
$ns0 = CallSelf 'Say' 1750 400; Wire $nbn 'else' $ns0 'execute'; Def $ns0 'Msg' 'string' 'Type a name for the design first.'
$nsv = CallSelf 'SaveDesign' 1750 0; Wire $nbn 'then' $nsv 'execute'; Wire $nt.Str 'ReturnValue' $nsv 'Name'; Def $nsv 'OpenApp' 'bool' 'false'
# Open in App: only with the app installed (its helper answers)
$ne = On-Click 'BtnOpenApp' 0 1200
$nhx = Call $GS 'DoesSaveGameExist' 250 1400; Def $nhx 'SlotName' 'string' 'SkinStudioHelper'; Def $nhx 'UserIndex' 'int' '0'; Wire $ne 'then' $nhx 'execute'
$nhb = Branch 500 1200; Wire $nhx 'then' $nhb 'execute'; Wire $nhx 'ReturnValue' $nhb 'Condition'
$nh9 = CallSelf 'Say' 750 1550; Wire $nhb 'else' $nh9 'execute'; Def $nh9 'Msg' 'string' 'Open in App needs the Skin Studio app installed on this PC.'
$nt = Name-Text 700 1400
Wire $nhb 'then' $nt.Cast 'execute'
$nln = Call $KSt 'Len' 1900 1550; Wire $nt.Str 'ReturnValue' $nln 'S'
$ngz = Math2 'Greater_IntInt' @($nln, 'ReturnValue') 0 2050 1550
$nbn = Branch 2000 1200; Wire $nt.Cast 'then' $nbn 'execute'; Wire $ngz 'ReturnValue' $nbn 'Condition'
$ns0 = CallSelf 'Say' 2250 1550; Wire $nbn 'else' $ns0 'execute'; Def $ns0 'Msg' 'string' 'Type a name for the design first - it opens in the app under that name.'
$nsv = CallSelf 'SaveDesign' 2250 1200; Wire $nbn 'then' $nsv 'execute'; Wire $nt.Str 'ReturnValue' $nsv 'Name'; Def $nsv 'OpenApp' 'bool' 'true'
Save-Graph 'panel_13.txt'

# ================================================================ bootstrap
New-Graph 18
function Panel-Call($nFrom, [string]$nPin, [string]$fn, [int]$x, [int]$y) {
    # find the live panel or make one (added to the viewport, root collapsed), then call $fn
    $ngw = Call $WB 'GetAllWidgetsOfClass' $x $y; Wire $nFrom $nPin $ngw 'execute'
    Def $ngw 'WidgetClass' 'class:/Script/UMG.UserWidget' $PanelClass; Def $ngw 'TopLevelOnly' 'bool' 'false'
    $ngi = Get-ArrItem $ngw 'FoundWidgets' 0 ($x + 250) ($y + 160)
    $niv = Call $KS 'IsValid' ($x + 450) ($y + 160); Wire $ngi 'Output' $niv 'Object'
    $nb = Branch ($x + 300) $y; Wire $ngw 'then' $nb 'execute'; Wire $niv 'ReturnValue' $nb 'Condition'
    $n1 = Add-Node '/Script/BlueprintGraph.K2Node_CallFunction' @("FunctionReference=(MemberParent=$PanelRef,MemberName=`"$fn`")") ($x + 800) ($y - 80)
    Wire $nb 'then' $n1 'execute'; Wire $ngi 'Output' $n1 'self'
    $npc = Call $GS 'GetPlayerController' ($x + 450) ($y + 300); Def $npc 'PlayerIndex' 'int' '0'
    $ncw = Add-Node '/Script/UMGEditor.K2Node_CreateWidget' @() ($x + 550) ($y + 120)
    Wire $nb 'else' $ncw 'execute'; Def $ncw 'Class' 'class:/Script/UMG.UserWidget' $PanelClass; Wire $npc 'ReturnValue' $ncw 'OwningPlayer'
    $nav = Call $UW 'AddToViewport' ($x + 800) ($y + 120); Wire $ncw 'then' $nav 'execute'; Wire $ncw 'ReturnValue' $nav 'self'; Def $nav 'ZOrder' 'int' '60'
    $n2 = Add-Node '/Script/BlueprintGraph.K2Node_CallFunction' @("FunctionReference=(MemberParent=$PanelRef,MemberName=`"$fn`")") ($x + 1050) ($y + 120)
    Wire $nav 'then' $n2 'execute'; Wire $ncw 'ReturnValue' $n2 'self'
}
# a 1 s pulse from the moment the class loads: in a match, re-paint whatever
# came back vanilla (respawn, new match). Timers live on the GameInstance
# (World.cpp: UWorld::GetTimerManager), so this one outlives map travel.
$noi = OverrideEvent $UW 'OnInitialized' 0 0
$npu = CustomEvent 'Pulse' 0 400 @()
$ntm = Call $KS 'K2_SetTimerDelegate' 300 0; Wire $noi 'then' $ntm 'execute'
Wire $npu 'OutputDelegate' $ntm 'Delegate'; Def $ntm 'Time' 'float' '1.000000'; Def $ntm 'bLooping' 'bool' 'true'
# breadcrumb SkinStudioInit.sav: the class ran (the game's own HighlightSettings
# object, borrowed, as the probe did - no class pin has to resolve)
$ncl = Call $GS 'LoadGameFromSlot' 250 -300; Def $ncl 'SlotName' 'string' 'HighlightSettings'; Def $ncl 'UserIndex' 'int' '0'
Wire $ntm 'then' $ncl 'execute'
$ncs = Call $GS 'SaveGameToSlot' 500 -300; Def $ncs 'SlotName' 'string' 'SkinStudioInit'; Def $ncs 'UserIndex' 'int' '0'
Wire $ncl 'then' $ncs 'execute'; Wire $ncl 'ReturnValue' $ncs 'SaveGameObject'
# Project Galacta, installed alongside. Both mods override WBP_UIDPanel and only
# one override loads: ours, because the container is named "!!SkinStudio" and
# the engine mounts paks in reverse name order (the first name wins a tie).
# Galacta's own panel only hosts WBP_Galacta as a collapsed child, so host it
# here instead - the proven block from ingame\gen_graphs.ps1. No Galacta = the
# class does not load, the cast fails, nothing happens.
$ngp = Call $KS 'MakeSoftClassPath' 700 -560; Def $ngp 'PathString' 'string' '/Game/Marvel/ProjectGalacta/UI/WBP_Galacta.WBP_Galacta_C'
$ngr = Call $KS 'Conv_SoftClassPathToSoftClassRef' 950 -560; Wire $ngp 'ReturnValue' $ngr 'SoftClassPath'
$nsq = ExecSeq 600 -420; Wire $ncs 'then' $nsq 'execute'
$ngl = Call $KS 'LoadClassAsset_Blocking' 750 -300; Wire $nsq 'then_0' $ngl 'execute'; Wire $ngr 'ReturnValue' $ngl 'AssetClass'
$ngc = Add-Node '/Script/BlueprintGraph.K2Node_ClassDynamicCast' @("TargetType=Class'`"/Script/UMG.UserWidget`"'") 1000 -300
Wire $ngl 'then' $ngc 'execute'; Wire $ngl 'ReturnValue' $ngc 'Class'
# only one: the UID panel (and this bootstrap with it) is rebuilt on some
# screen changes, and a second Galacta widget would answer every key twice
$ngw = Call $WB 'GetAllWidgetsOfClass' 1250 -300; Wire $ngc 'then' $ngw 'execute'; Wire $ngc 'AsUser Widget' $ngw 'WidgetClass'; Def $ngw 'TopLevelOnly' 'bool' 'false'
$ngn = CallArray 'Array_Length' 1450 -140; Wire $ngw 'FoundWidgets' $ngn 'TargetArray'
$nge = Call $KM 'EqualEqual_IntInt' 1650 -140; Wire $ngn 'ReturnValue' $nge 'A'; Def $nge 'B' 'int' '0'
$ngb = Branch 1500 -300; Wire $ngw 'then' $ngb 'execute'; Wire $nge 'ReturnValue' $ngb 'Condition'
$ngq = Call $GS 'GetPlayerController' 1700 0; Def $ngq 'PlayerIndex' 'int' '0'
$ngk = Add-Node '/Script/UMGEditor.K2Node_CreateWidget' @() 1750 -300
Wire $ngb 'then' $ngk 'execute'; Wire $ngc 'AsUser Widget' $ngk 'Class'; Wire $ngq 'ReturnValue' $ngk 'OwningPlayer'
# collapsed, as its own panel keeps it: it draws nothing until its menus open
$ngv = Call $WG 'SetVisibility' 2050 -300; Wire $ngk 'then' $ngv 'execute'; Wire $ngk 'ReturnValue' $ngv 'self'; Def $ngv 'InVisibility' $VisEnum 'Collapsed'
$nga = Call $UW 'AddToViewport' 2300 -300; Wire $ngv 'then' $nga 'execute'; Wire $ngk 'ReturnValue' $nga 'self'; Def $nga 'ZOrder' 'int' '0'
# The app half, shipped in this same container: SkinLive's bootstrap built with
# gen_graphs.ps1 -Hosted (no F8 - ours owns it). It brings F6, AutoTick (Galacta
# F7 after a Build mod + auto-apply of app designs, both only while the app
# listens) and the splash. Hosted after Galacta, so it finds Galacta already up.
$nhp = Call $KS 'MakeSoftClassPath' 700 -1000; Def $nhp 'PathString' 'string' '/Game/Marvel/SkinLive/UI/Widgets/WBP_SkinLivePreviewBootstrap01.WBP_SkinLivePreviewBootstrap01_C'
$nhr = Call $KS 'Conv_SoftClassPathToSoftClassRef' 950 -1000; Wire $nhp 'ReturnValue' $nhr 'SoftClassPath'
$nhl = Call $KS 'LoadClassAsset_Blocking' 750 -800; Wire $nsq 'then_1' $nhl 'execute'; Wire $nhr 'ReturnValue' $nhl 'AssetClass'
$nhc = Add-Node '/Script/BlueprintGraph.K2Node_ClassDynamicCast' @("TargetType=Class'`"/Script/UMG.UserWidget`"'") 1000 -800
Wire $nhl 'then' $nhc 'execute'; Wire $nhl 'ReturnValue' $nhc 'Class'
$nhw = Call $WB 'GetAllWidgetsOfClass' 1250 -800; Wire $nhc 'then' $nhw 'execute'; Wire $nhc 'AsUser Widget' $nhw 'WidgetClass'; Def $nhw 'TopLevelOnly' 'bool' 'false'
$nhn = CallArray 'Array_Length' 1450 -640; Wire $nhw 'FoundWidgets' $nhn 'TargetArray'
$nhe = Call $KM 'EqualEqual_IntInt' 1650 -640; Wire $nhn 'ReturnValue' $nhe 'A'; Def $nhe 'B' 'int' '0'
$nhb = Branch 1500 -800; Wire $nhw 'then' $nhb 'execute'; Wire $nhe 'ReturnValue' $nhb 'Condition'
$nhq = Call $GS 'GetPlayerController' 1700 -500; Def $nhq 'PlayerIndex' 'int' '0'
$nhk = Add-Node '/Script/UMGEditor.K2Node_CreateWidget' @() 1750 -800
Wire $nhb 'then' $nhk 'execute'; Wire $nhc 'AsUser Widget' $nhk 'Class'; Wire $nhq 'ReturnValue' $nhk 'OwningPlayer'
$nhv = Call $WG 'SetVisibility' 2050 -800; Wire $nhk 'then' $nhv 'execute'; Wire $nhk 'ReturnValue' $nhv 'self'; Def $nhv 'InVisibility' $VisEnum 'Collapsed'
$nha = Call $UW 'AddToViewport' 2300 -800; Wire $nhv 'then' $nha 'execute'; Wire $nhk 'ReturnValue' $nha 'self'; Def $nha 'ZOrder' 'int' '0'
# The Variant wordmark at login. The hosted bootstrap's own Splash call did not
# show it in the first merged build (2026-09-27), so ask for it from here too,
# half a second later (by name, on the app panel found or made by class path).
# Crumb SSLvl_<level>.sav records which level we started on.
$nlv = Call $GS 'GetCurrentLevelName' 700 -1400; Wire $nsq 'then_2' $nlv 'execute'; Def $nlv 'bRemovePrefixString' 'bool' 'true'
$nlc = Call $KSt 'Concat_StrStr' 950 -1250; Def $nlc 'A' 'string' 'SSLvl_'; Wire $nlv 'ReturnValue' $nlc 'B'
$nl1 = Call $GS 'LoadGameFromSlot' 950 -1400; Def $nl1 'SlotName' 'string' 'HighlightSettings'; Def $nl1 'UserIndex' 'int' '0'
Wire $nlv 'then' $nl1 'execute'
$nl2 = Call $GS 'SaveGameToSlot' 1200 -1400; Wire $nl1 'then' $nl2 'execute'; Wire $nl1 'ReturnValue' $nl2 'SaveGameObject'
Wire $nlc 'ReturnValue' $nl2 'SlotName'; Def $nl2 'UserIndex' 'int' '0'
$nlk = Call $KSt 'Contains' 1400 -1250; Wire $nlv 'ReturnValue' $nlk 'SearchIn'; Def $nlk 'Substring' 'string' 'ClientEntry'
$nlb = Branch 1450 -1400; Wire $nl2 'then' $nlb 'execute'; Wire $nlk 'ReturnValue' $nlb 'Condition'
$nxp = Call $KS 'MakeSoftClassPath' 1450 -1650; Def $nxp 'PathString' 'string' '/Game/Marvel/SkinLive/UI/Widgets/WBP_SkinLiveEditor.WBP_SkinLiveEditor_C'
$nxr = Call $KS 'Conv_SoftClassPathToSoftClassRef' 1700 -1650; Wire $nxp 'ReturnValue' $nxr 'SoftClassPath'
$nxl = Call $KS 'LoadClassAsset_Blocking' 1700 -1400; Wire $nlb 'then' $nxl 'execute'; Wire $nxr 'ReturnValue' $nxl 'AssetClass'
$nxc = Add-Node '/Script/BlueprintGraph.K2Node_ClassDynamicCast' @("TargetType=Class'`"/Script/UMG.UserWidget`"'") 1950 -1400
Wire $nxl 'then' $nxc 'execute'; Wire $nxl 'ReturnValue' $nxc 'Class'
$nxw = Call $WB 'GetAllWidgetsOfClass' 2200 -1400; Wire $nxc 'then' $nxw 'execute'; Wire $nxc 'AsUser Widget' $nxw 'WidgetClass'; Def $nxw 'TopLevelOnly' 'bool' 'false'
$nxn = CallArray 'Array_Length' 2400 -1240; Wire $nxw 'FoundWidgets' $nxn 'TargetArray'
$nxg = Call $KM 'Greater_IntInt' 2600 -1240; Wire $nxn 'ReturnValue' $nxg 'A'; Def $nxg 'B' 'int' '0'
$nxb = Branch 2500 -1400; Wire $nxw 'then' $nxb 'execute'; Wire $nxg 'ReturnValue' $nxb 'Condition'
$nxi = Get-ArrItem $nxw 'FoundWidgets' 0 2600 -1600
$nxt = Call $KS 'K2_SetTimer' 2850 -1500; Wire $nxb 'then' $nxt 'execute'; Wire $nxi 'Output' $nxt 'Object'
Def $nxt 'FunctionName' 'string' 'Splash'; Def $nxt 'Time' 'float' '0.500000'; Def $nxt 'bLooping' 'bool' 'false'
$nxq = Call $GS 'GetPlayerController' 2650 -1050; Def $nxq 'PlayerIndex' 'int' '0'
$nxk = Add-Node '/Script/UMGEditor.K2Node_CreateWidget' @() 2800 -1250
Wire $nxb 'else' $nxk 'execute'; Wire $nxc 'AsUser Widget' $nxk 'Class'; Wire $nxq 'ReturnValue' $nxk 'OwningPlayer'
$nxa = Call $UW 'AddToViewport' 3100 -1250; Wire $nxk 'then' $nxa 'execute'; Wire $nxk 'ReturnValue' $nxa 'self'; Def $nxa 'ZOrder' 'int' '50'
$nx2 = Call $KS 'K2_SetTimer' 3350 -1250; Wire $nxa 'then' $nx2 'execute'; Wire $nxk 'ReturnValue' $nx2 'Object'
Def $nx2 'FunctionName' 'string' 'Splash'; Def $nx2 'Time' 'float' '0.500000'; Def $nx2 'bLooping' 'bool' 'false'
$npp = Call $GS 'GetPlayerPawn' 200 560; Def $npp 'PlayerIndex' 'int' '0'
$niv = Call $KS 'IsValid' 400 560; Wire $npp 'ReturnValue' $niv 'Object'
$nbp = Branch 300 400; Wire $npu 'then' $nbp 'execute'; Wire $niv 'ReturnValue' $nbp 'Condition'
Panel-Call $nbp 'then' 'Reapply' 600 400
# F8: the panel (Project Galacta binds F7; the SkinLive app panel moved to F8 too)
$nf7 = InputKey 'F8' $true 0 1000
Panel-Call $nf7 'Pressed' 'Toggle' 600 1000
Save-Graph 'boot.txt'
