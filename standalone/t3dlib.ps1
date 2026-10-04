# t3dlib.ps1 - the Blueprint clipboard-T3D graph builder, COPIED from
# ingame\gen_graphs.ps1 (lines 32-295, 2026-09-26) so the standalone mod's
# generators do not depend on a file the in-game editor work keeps changing.
# Dot-source it; set $Out before Save-Graph. See gen_graphs.ps1's header for
# why every rule in here exists (pin names, 'execute', wildcard loops, paste
# order).
$EditorClass = '/Game/Marvel/SkinLive/UI/Widgets/WBP_SkinLiveEditor.WBP_SkinLiveEditor_C'
$EditorClassRef = "WidgetBlueprintGeneratedClass'`"$EditorClass`"'"
$script:G = $null
function New-Graph([int]$tag) {
    $script:G = @{ Tag = $tag; Nodes = New-Object System.Collections.ArrayList; Seq = 0; Count = @{} }
}
function New-Guid32 {
    $script:G.Seq++
    '5C1E{0:X4}{1:X8}0000000000000000' -f $script:G.Tag, $script:G.Seq
}

# ---- types: exec bool int real float string name obj:<path> class:<path>
#             struct:<path> byte:<enum path> wild   (+ '[]' suffix for arrays)
function Pin-Type([string]$t) {
    $arr = $t.EndsWith('[]'); if ($arr) { $t = $t.Substring(0, $t.Length - 2) }
    $cat = $t; $sub = ''; $obj = 'None'
    if ($t -match '^(obj|class|struct|byte):(.+)$') {
        $kind = $Matches[1]; $path = $Matches[2]
        switch ($kind) {
            # â˜… UE 5.3 writes a pin's type object as "/Script/CoreUObject.Class'<path>'".
            # The UE4 form Class'"<path>"' does not resolve here: the pin comes back
            # untyped, so casts report "the type of Object is undetermined" and every
            # pin carrying a default is orphaned.
            'obj'    { $cat = 'object'; $obj = "`"/Script/CoreUObject.Class'$path'`"" }
            'class'  { $cat = 'class';  $obj = "`"/Script/CoreUObject.Class'$path'`"" }
            'struct' { $cat = 'struct'; $obj = "`"/Script/CoreUObject.ScriptStruct'$path'`"" }
            'byte'   { $cat = 'byte';   $obj = "`"/Script/CoreUObject.Enum'$path'`"" }
        }
    } elseif ($t -eq 'real') { $cat = 'real'; $sub = 'double' }
    elseif ($t -eq 'float') { $cat = 'real'; $sub = 'float' }
    elseif ($t -eq 'wild') { $cat = 'wildcard' }
    @{ Cat = $cat; Sub = $sub; Obj = $obj; Container = $(if ($arr) { 'Array' } else { 'None' }) }
}

function Add-Node([string]$class, [string[]]$props, [int]$x, [int]$y) {
    $short = $class.Substring($class.LastIndexOf('.') + 1)
    $k = [int]$script:G.Count[$short]; $script:G.Count[$short] = $k + 1
    $n = @{ Name = ('{0}_{1}' -f $short, (1000 * $script:G.Tag + 100 + $k)); Class = $class; Props = @($props); X = $x; Y = $y
            Guid = (New-Guid32); Pins = [ordered]@{}; Extra = @() }
    [void]$script:G.Nodes.Add($n)
    $n
}

function Get-Pin($n, [string]$name, [bool]$out, [string]$type) {
    if ($n.Pins.Contains($name)) { return $n.Pins[$name] }
    $execNames = @('execute', 'then', 'else', 'Exec', 'LoopBody', 'Completed', 'CastFailed', 'Pressed', 'Released')
    if (-not $type) { $type = if ($execNames -contains $name -or $name -match '^then_\d+$') { 'exec' } else { 'wild' } }
    $p = @{ Name = $name; Out = $out; Type = (Pin-Type $type); Default = $null; DefObj = $null
            Links = New-Object System.Collections.ArrayList; Id = (New-Guid32) }
    $n.Pins[$name] = $p
    $p
}

# a wire: output pin of $a -> input pin of $b
function Wire($a, [string]$pa, $b, [string]$pb) {
    $x = Get-Pin $a $pa $true ''
    $y = Get-Pin $b $pb $false ''
    [void]$x.Links.Add(('{0} {1}' -f $b.Name, $y.Id))
    [void]$y.Links.Add(('{0} {1}' -f $a.Name, $x.Id))
}

# an input pin with a literal default
function Def($n, [string]$pin, [string]$type, [string]$value) {
    $p = Get-Pin $n $pin $false $type
    $p.Type = Pin-Type $type
    if ($type -like 'class:*' -or $type -like 'obj:*') { $p.DefObj = $value } else { $p.Default = $value }
}

# declare an output pin's type (for event parameters)
function OutPin($n, [string]$pin, [string]$type) { $p = Get-Pin $n $pin $true $type; $p.Type = Pin-Type $type }

# â˜… A macro instance's INPUT exec pin is called 'execute', not 'Exec' (only its
# outputs are LoopBody / Completed). Wiring to 'Exec' drops the link silently -
# exec pins are never kept as orphans - so the loop is never entered, the whole
# chain below it is pruned as unreachable, and it all still compiles clean.
# ---- node makers
function Call([string]$owner, [string]$fn, [int]$x, [int]$y) {
    # â˜… guards the case-insensitivity trap: a local like $gs IS the constant $GS,
    # so a node object can silently land here and emit MemberParent=Hashtable,
    # which UE drops on paste without a word
    if (-not ($owner.StartsWith('/') -or $owner.StartsWith('Class') -or $owner.Contains('Blueprint'))) {
        throw "Call: '$fn' has a bad owner '$owner' - a variable was clobbered"
    }
    $parent = if ($owner -like '/*') { "Class'`"$owner`"'" } else { $owner }
    Add-Node '/Script/BlueprintGraph.K2Node_CallFunction' @("FunctionReference=(MemberParent=$parent,MemberName=`"$fn`")") $x $y
}
function CallSelf([string]$fn, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_CallFunction' @("FunctionReference=(MemberName=`"$fn`",bSelfContext=True)") $x $y
}
function CallEditor([string]$fn, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_CallFunction' @("FunctionReference=(MemberParent=$EditorClassRef,MemberName=`"$fn`")") $x $y
}
function CustomEvent([string]$name, [int]$x, [int]$y, [string[]]$params) {
    $n = Add-Node '/Script/BlueprintGraph.K2Node_CustomEvent' @("CustomFunctionName=`"$name`"") $x $y
    $d = Get-Pin $n 'OutputDelegate' $true 'wild'
    $d.Type = @{ Cat = 'delegate'; Sub = ''; Obj = 'None'; Container = 'None'; Member = "(MemberName=`"$name`")" }
    $d.Hidden = $true
    [void](Get-Pin $n 'then' $true 'exec')
    foreach ($spec in $params) {
        $pn, $pt = $spec -split '=', 2
        OutPin $n $pn $pt
        $t = Pin-Type $pt
        $obj = if ($t.Obj -ne 'None') { ',PinSubCategoryObject=' + $t.Obj } else { '' }
        $sub = if ($t.Sub) { ',PinSubCategory="' + $t.Sub + '"' } else { '' }
        $n.Extra += ('CustomProperties UserDefinedPin (PinName="{0}",PinType=(PinCategory="{1}"{2}{3}),DesiredPinDirection=EGPD_Output)' -f $pn, $t.Cat, $sub, $obj)
    }
    $n
}
function Branch([int]$x, [int]$y) { Add-Node '/Script/BlueprintGraph.K2Node_IfThenElse' @() $x $y }
function CallArray([string]$fn, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_CallArrayFunction' @("FunctionReference=(MemberParent=Class'`"/Script/Engine.KismetArrayLibrary`"',MemberName=`"$fn`")") $x $y
}
# â˜… A pasted For Each Loop stays WILDCARD: ResolvedWildcardType is only ever set
# from a live connection change, and nothing re-applies it on paste, so the
# element pin has no type and any cast off it fails to compile. Array_Length and
# Get (a copy) DO re-type themselves on paste (both call PropagateArrayTypeInfo /
# PropagatePinType from PostReconstructNode), and a For Loop is plain ints - so
# build the loop from those three instead.
function ArrayLoop($arrNode, [string]$arrPin, [int]$x, [int]$y) {
    $len = CallArray 'Array_Length' $x ($y + 200)
    Wire $arrNode $arrPin $len 'TargetArray'
    $sub = Call '/Script/Engine.KismetMathLibrary' 'Subtract_IntInt' ($x + 200) ($y + 200)
    Wire $len 'ReturnValue' $sub 'A'; Def $sub 'B' 'int' '1'
    $loop = Macro 'ForLoop' '' ($x + 400) $y
    Def $loop 'FirstIndex' 'int' '0'; Wire $sub 'ReturnValue' $loop 'LastIndex'
    $item = Add-Node '/Script/BlueprintGraph.K2Node_GetArrayItem' @() ($x + 620) ($y + 200)
    Wire $arrNode $arrPin $item 'Array'
    Wire $loop 'Index' $item 'Dimension 1'
    @{ Loop = $loop; Item = $item }
}
function ExecSeq([int]$x, [int]$y) { Add-Node '/Script/BlueprintGraph.K2Node_ExecutionSequence' @() $x $y }
function Cast([string]$cls, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_DynamicCast' @("TargetType=Class'`"$cls`"'") $x $y
}
function GetMember([string]$var, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_VariableGet' @("VariableReference=(MemberName=`"$var`",bSelfContext=True)") $x $y
}
function GetVarOf([string]$cls, [string]$var, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_VariableGet' @("VariableReference=(MemberParent=Class'`"$cls`"',MemberName=`"$var`")") $x $y
}
function SetVarOf([string]$cls, [string]$var, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_VariableSet' @("VariableReference=(MemberParent=Class'`"$cls`"',MemberName=`"$var`")") $x $y
}
function Macro([string]$which, [string]$wildObj, [int]$x, [int]$y) {
    $p = @("MacroGraphReference=(MacroGraph=EdGraph'`"/Engine/EditorBlueprintResources/StandardMacros.StandardMacros:$which`"',GraphBlueprint=Blueprint'`"/Engine/EditorBlueprintResources/StandardMacros.StandardMacros`"',GraphGuid=00000000000000000000000000000000)")
    if ($wildObj) { $p += 'ResolvedWildcardType=(PinCategory="object",PinSubCategoryObject="/Script/CoreUObject.Class''{0}''")' -f $wildObj }
    Add-Node '/Script/BlueprintGraph.K2Node_MacroInstance' $p $x $y
}
function InputKey([string]$key, [bool]$consume, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_InputKey' @("InputKey=$key", "bConsumeInput=$(if ($consume) { 'True' } else { 'False' })", 'bExecuteWhenPaused=False', 'bOverrideParentBinding=True') $x $y
}
function OverrideEvent([string]$cls, [string]$fn, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_Event' @("EventReference=(MemberParent=Class'`"$cls`"',MemberName=`"$fn`")", 'bOverrideFunction=True') $x $y
}
function BoundEvent([string]$widgetVar, [string]$delegate, [string]$sig, [int]$x, [int]$y) {
    $k = [int]$script:G.Count['K2Node_ComponentBoundEvent']
    Add-Node '/Script/BlueprintGraph.K2Node_ComponentBoundEvent' @(
        "DelegatePropertyName=`"$delegate`"",
        "DelegateOwnerClass=Class'`"/Script/UMG.Button`"'",
        "ComponentPropertyName=`"$widgetVar`"",
        "EventReference=(MemberParent=Package'`"/Script/UMG`"',MemberName=`"$sig`")",
        'bInternalEvent=True',
        ("CustomFunctionName=`"BndEvt__WBP_SkinLiveEditor_{0}_K2Node_ComponentBoundEvent_{1}_{2}`"" -f $widgetVar, (100 + $k), $sig)) $x $y
}

# string building: Concat_StrStr chains. $parts: node/pin pairs or literals.
#   @( 'SLC_', @($node,'ReturnValue'), '_' )  -> returns the last Concat node
function Concat-Chain([object[]]$parts, [int]$x, [int]$y) {
    $prev = $null
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $c = Call '/Script/Engine.KismetStringLibrary' 'Concat_StrStr' ($x + 180 * $i) $y
        if ($i -eq 1) { Set-StrInput $c 'A' $parts[0] } else { Wire $prev 'ReturnValue' $c 'A' }
        Set-StrInput $c 'B' $parts[$i]
        $prev = $c
    }
    $prev
}
function Set-StrInput($n, [string]$pin, $part) {
    if ($part -is [string]) { Def $n $pin 'string' $part }
    else { Wire $part[0] $part[1] $n $pin }
}

# ---- emit
function Emit-Graph {
    $sb = New-Object System.Text.StringBuilder
    foreach ($n in $script:G.Nodes) {
        [void]$sb.AppendLine(('Begin Object Class={0} Name="{1}"' -f $n.Class, $n.Name))
        foreach ($p in $n.Props) { [void]$sb.AppendLine('   ' + $p) }
        [void]$sb.AppendLine(('   NodePosX={0}' -f $n.X))
        [void]$sb.AppendLine(('   NodePosY={0}' -f $n.Y))
        [void]$sb.AppendLine(('   NodeGuid={0}' -f $n.Guid))
        foreach ($p in $n.Pins.Values) {
            $t = $p.Type
            $mem = if ($t.Member) { $t.Member } else { '()' }
            $dir = if ($p.Out) { 'Direction="EGPD_Output",' } else { '' }
            $def = ''
            if ($null -ne $p.DefObj) { $def = 'DefaultObject="{0}",' -f $p.DefObj }
            elseif ($null -ne $p.Default) { $def = 'DefaultValue="{0}",' -f $p.Default }
            $links = ''
            if ($p.Links.Count -gt 0) { $links = 'LinkedTo=(' + (($p.Links | ForEach-Object { $_ + ',' }) -join '') + '),' }
            $hid = if ($p.Hidden) { 'True' } else { 'False' }
            [void]$sb.AppendLine(('      CustomProperties Pin (PinId={0},PinName="{1}",{2}PinType.PinCategory="{3}",PinType.PinSubCategory="{4}",PinType.PinSubCategoryObject={5},PinType.PinSubCategoryMemberReference={6},PinType.PinValueType=(),PinType.ContainerType={7},PinType.bIsReference=False,PinType.bIsConst=False,PinType.bIsWeakPointer=False,PinType.bIsUObjectWrapper=False,PinType.bSerializeAsSinglePrecisionFloat=False,{8}AutogeneratedDefaultValue="",{9}PersistentGuid=00000000000000000000000000000000,bHidden={10},bNotConnectable=False,bDefaultValueIsReadOnly=False,bDefaultValueIsIgnored=False,bAdvancedView=False,bOrphanedPin=False,)' -f `
                $p.Id, $p.Name, $dir, $t.Cat, $t.Sub, $t.Obj, $mem, $t.Container, $def, $links, $hid))
        }
        foreach ($e in $n.Extra) { [void]$sb.AppendLine('      ' + $e) }
        [void]$sb.AppendLine('End Object')
    }
    $sb.ToString()
}
function Save-Graph([string]$file) {
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    $path = Join-Path $Out $file
    [IO.File]::WriteAllText($path, (Emit-Graph), (New-Object System.Text.UTF8Encoding($false)))
    '{0,-18} {1,3} nodes  {2,6} bytes' -f $file, $script:G.Nodes.Count, (Get-Item $path).Length
}

$GS  = '/Script/Engine.GameplayStatics'
$KM  = '/Script/Engine.KismetMathLibrary'
$KS  = '/Script/Engine.KismetSystemLibrary'
$KSt = '/Script/Engine.KismetStringLibrary'
$KR  = '/Script/Engine.KismetRenderingLibrary'
$WL  = '/Script/UMG.WidgetLayoutLibrary'
$WB  = '/Script/UMG.WidgetBlueprintLibrary'
$SL  = '/Script/UMG.SlateBlueprintLibrary'
$UW  = '/Script/UMG.UserWidget'
$WG  = '/Script/UMG.Widget'
$MIC = '/Script/Engine.MaterialInstanceConstant'
$MID = '/Script/Engine.MaterialInstanceDynamic'
$VisEnum = 'byte:/Script/UMG.ESlateVisibility'   # not $VIS: a $vis parameter would be the same variable

function Flag-Check([string]$slot, $execFrom, [string]$execPin, [int]$x, [int]$y) {
    # DoesSaveGameExist(slot) -> Branch -> DeleteGameInSlot(slot); returns the delete node
    $ds = Call $GS 'DoesSaveGameExist' $x $y; Def $ds 'SlotName' 'string' $slot; Def $ds 'UserIndex' 'int' '0'
    Wire $execFrom $execPin $ds 'execute'
    $br = Branch ($x + 260) $y; Wire $ds 'then' $br 'execute'; Wire $ds 'ReturnValue' $br 'Condition'
    $dg = Call $GS 'DeleteGameInSlot' ($x + 460) $y; Def $dg 'SlotName' 'string' $slot; Def $dg 'UserIndex' 'int' '0'
    Wire $br 'then' $dg 'execute'
    $dg
}
function Send-Literal($execFrom, [string]$execPin, [string]$cmd, [int]$x, [int]$y) {
    $c = CallSelf 'SendCmd' $x $y; Def $c 'Cmd' 'string' $cmd; Wire $execFrom $execPin $c 'execute'; $c
}
# Rivals owns the input mode in a match: MarvelHUD counts the menus that need
# the mouse and restores gameplay mode when none do, which beat our own
# SetInputMode. So Open/Close ask the HUD itself (NeedInputModeUI /
# StopNeedInputModeUI). Our project has no MarvelHUD class, so these are
# authored against stock stand-ins that patch_hud_calls.ps1 rewrites after the
# cook - the guard's class literal /Script/Engine.Info becomes MarvelHUD, and
# the two virtual calls are renamed. Returns the Branch (then = a MarvelHUD) and
# the GetHUD node to call on.
function Hud-Guard($pcNode, [int]$x, [int]$y) {
    $hud = Call '/Script/Engine.PlayerController' 'GetHUD' $x ($y + 160); Wire $pcNode 'ReturnValue' $hud 'self'
    $cls = Call $GS 'GetObjectClass' ($x + 200) ($y + 160); Wire $hud 'ReturnValue' $cls 'Object'
    $isc = Call $KM 'ClassIsChildOf' ($x + 400) ($y + 160); Wire $cls 'ReturnValue' $isc 'TestClass'
    Def $isc 'ParentClass' 'class:/Script/CoreUObject.Object' '/Script/Engine.Info'
    $br = Branch ($x + 600) $y; Wire $isc 'ReturnValue' $br 'Condition'
    @{ Branch = $br; Hud = $hud }
}

function Set-Vis($execFrom, [string]$execPin, [string]$widgetVar, [string]$want, [int]$x, [int]$y) {
    $v = GetMember $widgetVar $x ($y + 120)
    $s = Call $WG 'SetVisibility' ($x + 180) $y
    Wire $v $widgetVar $s 'self'; Def $s 'InVisibility' $VisEnum $want
    Wire $execFrom $execPin $s 'execute'
    $s
}

# ---- standalone additions ----------------------------------------------------
# a Blueprint class (BlueprintGeneratedClass) as a cast target / member owner
function CastBP([string]$cls, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_DynamicCast' @("TargetType=BlueprintGeneratedClass'`"$cls`"'") $x $y
}
function GetVarOfBP([string]$cls, [string]$var, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_VariableGet' @("VariableReference=(MemberParent=BlueprintGeneratedClass'`"$cls`"',MemberName=`"$var`")") $x $y
}
function SetVarOfBP([string]$cls, [string]$var, [int]$x, [int]$y) {
    Add-Node '/Script/BlueprintGraph.K2Node_VariableSet' @("VariableReference=(MemberParent=BlueprintGeneratedClass'`"$cls`"',MemberName=`"$var`")") $x $y
}
# clipboard text for SMyBlueprint's Paste (My Blueprint panel, Ctrl+V): a member
# variable. SMyBlueprint.cpp OnPasteVariable: "BPVar" + FBPVariableDescription
# export text; it mints a fresh guid and a unique name itself.
# PropertyFlags 0x10005 = Edit | BlueprintVisible | DisableEditOnInstance, what
# the "+ Variable" button gives.
function BPVar-Text([string]$name, [string]$pinCategory) {
    'BPVar(VarName="{0}",VarGuid=5C1E7A5000000000000000000000{1:X4},VarType=(PinCategory="{2}"),FriendlyName="{0}",PropertyFlags=65541,ReplicationCondition=COND_None)' -f $name, ($name.Length), $pinCategory
}