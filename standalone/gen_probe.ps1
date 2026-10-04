# gen_probe.ps1 - the standalone mod's PROBE: one widget that proves, in one
# practice-range session, the building blocks of a Skin Studio that runs with
# no app:
#   F8   writes a colour set to our own save slot (a SaveGame Blueprint with one
#        String field, all stock engine) - pink first, then teal, then pink...
#   1 s  a looping timer reads that slot back and paints the hero: BaseTint on
#        every material, dye zones 1-7 on dyed ones (mask name ends _ColorID).
#        It keeps doing it, so a respawn or a new match gets painted again.
#   F9   deletes the slot and puts every painted param back to the vanilla
#        value, read off the MID's parent instance.
# Breadcrumbs (SaveGames\<name>.sav): SSProbeInit (class ran), SSProbeF8,
# SSProbeF9 (keys reached it), SSProbeNew_<ms> (a pass made new MIDs: first
# paint, and again after a respawn or a new match = the timer survived).
#
#   .\gen_probe.ps1   -> D:\SkinStudioProbeUE\paste\probe_graph.txt, probe_var.txt
#
# ONE paste: no node calls one of our own events (the timer takes Reapply's
# delegate pin, which is a data link), so paste order cannot cut exec wires.
param([string]$Out = 'D:\SkinStudioProbeUE\paste')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 't3dlib.ps1')

# * t3dlib holds $GS $KM $KS $KSt $MIC $MID $W... as constants, and PowerShell
# names are case-insensitive: every local below is n-prefixed so none of them
# can silently overwrite one ($mid IS $MID).
$WidgetDir = '/Game/Marvel/SkinLive/UI/Widgets'
$SaveBP    = "$WidgetDir/Skinprobesave.Skinprobesave_C"
$ColorSlot = 'SSProbeColors'
$PinkSet   = '1.0,0.35,0.85|0.05,0.60,0.15|0.40,1.00,0.50'   # tint | zone dark | zone light
$TealSet   = '0.30,0.90,1.00|0.60,0.10,0.05|1.00,0.55,0.20'
$PinkMark  = '0.35,0.85|'                                     # only the pink set has it
$Regions   = 1..7

function Crumb($nFrom, [string]$nPin, $nameSrc, [int]$x, [int]$y) {
    # LoadGameFromSlot("HighlightSettings") -> SaveGameToSlot(<name>): the game's
    # own save object, borrowed, so no class pin has to resolve
    $nl = Call $GS 'LoadGameFromSlot' $x $y; Def $nl 'SlotName' 'string' 'HighlightSettings'; Def $nl 'UserIndex' 'int' '0'
    Wire $nFrom $nPin $nl 'execute'
    $ns = Call $GS 'SaveGameToSlot' ($x + 260) $y; Def $ns 'UserIndex' 'int' '0'
    Wire $nl 'then' $ns 'execute'; Wire $nl 'ReturnValue' $ns 'SaveGameObject'
    if ($nameSrc -is [string]) { Def $ns 'SlotName' 'string' $nameSrc } else { Wire $nameSrc[0] $nameSrc[1] $ns 'SlotName' }
    $ns
}
function Ms-Name([string]$prefix, [int]$x, [int]$y) {
    # "<prefix><GetRealTimeSeconds*1000>": one name per pass
    $nrt = Call $GS 'GetRealTimeSeconds' $x $y
    $nmu = Call $KM 'Multiply_DoubleDouble' ($x + 200) $y; Wire $nrt 'ReturnValue' $nmu 'A'; Def $nmu 'B' 'real' '1000.000000'
    $nrd = Call $KM 'Round' ($x + 400) $y; Wire $nmu 'ReturnValue' $nrd 'A'
    $nis = Call $KSt 'Conv_IntToString' ($x + 600) $y; Wire $nrd 'ReturnValue' $nis 'InInt'
    Concat-Chain @($prefix, @($nis, 'ReturnValue')) ($x + 600) ($y + 100)
}
function Parse-Color($nSrc, [string]$nSrcPin, [int]$x, [int]$y) {
    # "r,g,b" -> LinearColor
    $npa = Call $KSt 'ParseIntoArray' $x $y; Wire $nSrc $nSrcPin $npa 'SourceString'
    Def $npa 'Delimiter' 'string' ','; Def $npa 'CullEmptyStrings' 'bool' 'true'
    $nmc = Call $KM 'MakeColor' ($x + 700) $y; Def $nmc 'A' 'float' '1.000000'
    $k = 0
    foreach ($ch in @('R', 'G', 'B')) {
        $ngi = Add-Node '/Script/BlueprintGraph.K2Node_GetArrayItem' @() ($x + 250) ($y + 110 * $k)
        Wire $npa 'ReturnValue' $ngi 'Array'; Def $ngi 'Dimension 1' 'int' ([string]$k)
        $ncd = Call $KSt 'Conv_StringToDouble' ($x + 450) ($y + 110 * $k); Wire $ngi 'Output' $ncd 'InString'
        Wire $ncd 'ReturnValue' $nmc $ch
        $k++
    }
    $nmc
}
# every material slot of every skeletal mesh on the pawn's attached actors -
# the same walk the working F6 uses (ingame\gen_graphs.ps1 Walk). $body gets
# (exec node, exec pin, mesh component node, its pin, loop node for Index).
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
    $nnm = Call '/Script/Engine.PrimitiveComponent' 'GetNumMaterials' ($x + 2400) ($y + 200); Wire $nca 'AsSkeletal Mesh Component' $nnm 'self'
    $nsb = Call $KM 'Subtract_IntInt' ($x + 2600) ($y + 200); Wire $nnm 'ReturnValue' $nsb 'A'; Def $nsb 'B' 'int' '1'
    $nfl = Macro 'ForLoop' '' ($x + 2800) $y; Def $nfl 'FirstIndex' 'int' '0'; Wire $nsb 'ReturnValue' $nfl 'LastIndex'
    Wire $nca 'then' $nfl 'execute'
    & $body $nfl 'LoopBody' $nca 'AsSkeletal Mesh Component' $nfl ($x + 3100) $y
}
# a dyed material: its parent instance's DyeingTexture is a _ColorID mask
# (only dyed MIs store one - checked against 327 cached character MIs).
# Returns the Branch; its 'then' continues the chain.
function Dyed-Branch($nFrom, [string]$nPin, $nMic, [int]$x, [int]$y) {
    $ngt = Call $MIC 'K2_GetTextureParameterValue' $x $y; Wire $nFrom $nPin $ngt 'execute'
    Wire $nMic 'AsMaterial Instance Constant' $ngt 'self'; Def $ngt 'ParameterName' 'name' 'DyeingTexture'
    $non = Call $KS 'GetObjectName' ($x + 250) ($y + 160); Wire $ngt 'ReturnValue' $non 'Object'
    $new = Call $KSt 'EndsWith' ($x + 450) ($y + 160); Wire $non 'ReturnValue' $new 'SourceString'; Def $new 'InSuffix' 'string' '_ColorID'
    $nbr = Branch ($x + 500) $y; Wire $ngt 'then' $nbr 'execute'; Wire $new 'ReturnValue' $nbr 'Condition'
    $nbr
}
function Zone-Names { foreach ($r in $Regions) { "Region $r - ColorA"; "Region $r - ColorB" } }

New-Graph 7

# =========================================================== OnInitialized
$nOi = OverrideEvent $UW 'OnInitialized' 0 0
$nCr = Crumb $nOi 'then' 'SSProbeInit' 250 0
$nRe = CustomEvent 'Reapply' 0 700 @()
$nTm = Call $KS 'K2_SetTimerDelegate' 850 0; Wire $nCr 'then' $nTm 'execute'
Wire $nRe 'OutputDelegate' $nTm 'Delegate'
Def $nTm 'Time' 'float' '1.000000'; Def $nTm 'bLooping' 'bool' 'true'

# =========================================================== Reapply (every 1 s)
$nDs = Call $GS 'DoesSaveGameExist' 250 700; Def $nDs 'SlotName' 'string' $ColorSlot; Def $nDs 'UserIndex' 'int' '0'
Wire $nRe 'then' $nDs 'execute'
$nBd = Branch 500 700; Wire $nDs 'then' $nBd 'execute'; Wire $nDs 'ReturnValue' $nBd 'Condition'
$nLg = Call $GS 'LoadGameFromSlot' 700 700; Def $nLg 'SlotName' 'string' $ColorSlot; Def $nLg 'UserIndex' 'int' '0'
Wire $nBd 'then' $nLg 'execute'
$nCs = CastBP $SaveBP 950 700; Wire $nLg 'then' $nCs 'execute'; Wire $nLg 'ReturnValue' $nCs 'Object'
$nDt = GetVarOfBP $SaveBP 'Data' 950 900; Wire $nCs 'AsSkinprobesave' $nDt 'self'
$nPa = Call $KSt 'ParseIntoArray' 1150 900; Wire $nDt 'Data' $nPa 'SourceString'
Def $nPa 'Delimiter' 'string' '|'; Def $nPa 'CullEmptyStrings' 'bool' 'true'
$nCol = @()
for ($k = 0; $k -lt 3; $k++) {
    $ngi = Add-Node '/Script/BlueprintGraph.K2Node_GetArrayItem' @() 1400 (900 + 400 * $k)
    Wire $nPa 'ReturnValue' $ngi 'Array'; Def $ngi 'Dimension 1' 'int' ([string]$k)
    $nCol += , (Parse-Color $ngi 'Output' 1600 (900 + 400 * $k))
}
$nTint = $nCol[0]; $nZoneA = $nCol[1]; $nZoneB = $nCol[2]

$applyBody = {
    param($nEx, $nExPin, $nComp, $nCompPin, $nLoop, [int]$x, [int]$y)
    $ngm = Call '/Script/Engine.PrimitiveComponent' 'GetMaterial' $x ($y + 200); Wire $nComp $nCompPin $ngm 'self'; Wire $nLoop 'Index' $ngm 'ElementIndex'
    $ncm = Cast $MID ($x + 250) $y; Wire $nEx $nExPin $ncm 'execute'; Wire $ngm 'ReturnValue' $ncm 'Object'
    # not a dynamic instance yet = this pass is painting it for the first time
    $nnm = Ms-Name 'SSProbeNew_' ($x + 250) ($y + 500)
    $nck = Crumb $ncm 'CastFailed' @($nnm, 'ReturnValue') ($x + 500) ($y + 300)
    $ncd = Call '/Script/Engine.PrimitiveComponent' 'CreateDynamicMaterialInstance' ($x + 1100) $y
    Wire $ncm 'then' $ncd 'execute'; Wire $nck 'then' $ncd 'execute'
    Wire $nComp $nCompPin $ncd 'self'; Wire $nLoop 'Index' $ncd 'ElementIndex'
    $nsv = Call $MID 'SetVectorParameterValue' ($x + 1400) $y; Wire $ncd 'then' $nsv 'execute'
    Wire $ncd 'ReturnValue' $nsv 'self'; Def $nsv 'ParameterName' 'name' 'BaseTint'; Wire $nTint 'ReturnValue' $nsv 'Value'
    $npg = GetVarOf '/Script/Engine.MaterialInstance' 'Parent' ($x + 1500) ($y + 200); Wire $ncd 'ReturnValue' $npg 'self'
    $nmc = Cast $MIC ($x + 1700) $y; Wire $nsv 'then' $nmc 'execute'; Wire $npg 'Parent' $nmc 'Object'
    $nbr = Dyed-Branch $nmc 'then' $nmc ($x + 1950) $y
    $nPrev = $nbr; $nPrevPin = 'then'; $j = 0
    foreach ($pn in (Zone-Names)) {
        $nz = Call $MID 'SetVectorParameterValue' ($x + 2500 + 250 * $j) $y; Wire $nPrev $nPrevPin $nz 'execute'
        Wire $ncd 'ReturnValue' $nz 'self'; Def $nz 'ParameterName' 'name' $pn
        if ($pn.EndsWith('A')) { Wire $nZoneA 'ReturnValue' $nz 'Value' } else { Wire $nZoneB 'ReturnValue' $nz 'Value' }
        $nPrev = $nz; $nPrevPin = 'then'; $j++
    }
}
Walk-Slots $nCs 'then' $applyBody 2400 700

# =========================================================== F8: next colour set
$nF8 = InputKey 'F8' $false 0 2600
$nC8 = Crumb $nF8 'Pressed' 'SSProbeF8' 250 2600
$nL8 = Call $GS 'LoadGameFromSlot' 800 2600; Def $nL8 'SlotName' 'string' $ColorSlot; Def $nL8 'UserIndex' 'int' '0'
Wire $nC8 'then' $nL8 'execute'
$nK8 = CastBP $SaveBP 1050 2600; Wire $nL8 'then' $nK8 'execute'; Wire $nL8 'ReturnValue' $nK8 'Object'
# pink now -> teal next; anything else (no save yet reads as "") -> pink
$nD8 = GetVarOfBP $SaveBP 'Data' 1050 2800; Wire $nK8 'AsSkinprobesave' $nD8 'self'
$nH8 = Call $KSt 'Contains' 1250 2800; Wire $nD8 'Data' $nH8 'SearchIn'; Def $nH8 'Substring' 'string' $PinkMark
$nS8 = Call $KM 'SelectString' 1450 2800; Def $nS8 'A' 'string' $TealSet; Def $nS8 'B' 'string' $PinkSet; Wire $nH8 'ReturnValue' $nS8 'bPickA'
$nCo = Call $GS 'CreateSaveGameObject' 1350 2600; Def $nCo 'SaveGameClass' 'class:/Script/Engine.SaveGame' $SaveBP
Wire $nK8 'then' $nCo 'execute'; Wire $nK8 'CastFailed' $nCo 'execute'
$nK9 = CastBP $SaveBP 1600 2600; Wire $nCo 'then' $nK9 'execute'; Wire $nCo 'ReturnValue' $nK9 'Object'
$nSd = SetVarOfBP $SaveBP 'Data' 1850 2600; Wire $nK9 'then' $nSd 'execute'; Wire $nK9 'AsSkinprobesave' $nSd 'self'; Wire $nS8 'ReturnValue' $nSd 'Data'
$nSg = Call $GS 'SaveGameToSlot' 2100 2600; Wire $nSd 'then' $nSg 'execute'; Wire $nK9 'AsSkinprobesave' $nSg 'SaveGameObject'
Def $nSg 'SlotName' 'string' $ColorSlot; Def $nSg 'UserIndex' 'int' '0'

# =========================================================== F9: back to vanilla
$nF9 = InputKey 'F9' $false 0 3200
$nC9 = Crumb $nF9 'Pressed' 'SSProbeF9' 250 3200
$nDg = Call $GS 'DeleteGameInSlot' 800 3200; Def $nDg 'SlotName' 'string' $ColorSlot; Def $nDg 'UserIndex' 'int' '0'
Wire $nC9 'then' $nDg 'execute'
$resetBody = {
    param($nEx, $nExPin, $nComp, $nCompPin, $nLoop, [int]$x, [int]$y)
    $ngm = Call '/Script/Engine.PrimitiveComponent' 'GetMaterial' $x ($y + 200); Wire $nComp $nCompPin $ngm 'self'; Wire $nLoop 'Index' $ngm 'ElementIndex'
    $ncm = Cast $MID ($x + 250) $y; Wire $nEx $nExPin $ncm 'execute'; Wire $ngm 'ReturnValue' $ncm 'Object'
    $npg = GetVarOf '/Script/Engine.MaterialInstance' 'Parent' ($x + 400) ($y + 200); Wire $ncm 'AsMaterial Instance Dynamic' $npg 'self'
    $nmc = Cast $MIC ($x + 600) $y; Wire $ncm 'then' $nmc 'execute'; Wire $npg 'Parent' $nmc 'Object'
    # BaseTint back to the parent's value (the parent's own default if it stores none)
    $ngv = Call $MIC 'K2_GetVectorParameterValue' ($x + 850) $y; Wire $nmc 'then' $ngv 'execute'
    Wire $nmc 'AsMaterial Instance Constant' $ngv 'self'; Def $ngv 'ParameterName' 'name' 'BaseTint'
    $nsv = Call $MID 'SetVectorParameterValue' ($x + 1100) $y; Wire $ngv 'then' $nsv 'execute'
    Wire $ncm 'AsMaterial Instance Dynamic' $nsv 'self'; Def $nsv 'ParameterName' 'name' 'BaseTint'; Wire $ngv 'ReturnValue' $nsv 'Value'
    $nbr = Dyed-Branch $nsv 'then' $nmc ($x + 1350) $y
    $nPrev = $nbr; $nPrevPin = 'then'; $j = 0
    foreach ($pn in (Zone-Names)) {
        $nzg = Call $MIC 'K2_GetVectorParameterValue' ($x + 1900 + 500 * $j) ($y - 150); Wire $nPrev $nPrevPin $nzg 'execute'
        Wire $nmc 'AsMaterial Instance Constant' $nzg 'self'; Def $nzg 'ParameterName' 'name' $pn
        $nzs = Call $MID 'SetVectorParameterValue' ($x + 2150 + 500 * $j) $y; Wire $nzg 'then' $nzs 'execute'
        Wire $ncm 'AsMaterial Instance Dynamic' $nzs 'self'; Def $nzs 'ParameterName' 'name' $pn; Wire $nzg 'ReturnValue' $nzs 'Value'
        $nPrev = $nzs; $nPrevPin = 'then'; $j++
    }
}
Walk-Slots $nDg 'then' $resetBody 1100 3200

Save-Graph 'probe_graph.txt'
$vt = BPVar-Text 'Data' 'string'
[IO.File]::WriteAllText((Join-Path $Out 'probe_var.txt'), $vt, (New-Object System.Text.UTF8Encoding($false)))
'probe_var.txt      {0}' -f $vt
