# ============================================================================
# Variant Skin Studio - the studio's own look.
#
# This is the Variant UI chrome (C:\rs\ThemeStudio\ThemeStudio.ps1) lifted into
# a module of its own so the two studios are visibly the same product: same
# neutral-grey surfaces, same rounded owner-drawn buttons and cards, same
# hand-painted sliders / drop-downs / colour picker, same dark title bar and
# scrollbars, same Black Ops One display face.
#
# The ONE difference is the accent: Variant UI wears the logo pink, and Skin
# Studio wears a light sage green. Everything else is byte-for-byte the code
# that already ships in Variant UI, so a fix there ports here by re-running
# build-vuistyle.ps1 (kept beside this file) rather than by hand-editing.
#
# To re-skin the whole studio, change the four Sage* entries below - nothing
# else in the app names an accent colour.
#
# Dot-source it AFTER Add-Type for System.Windows.Forms / System.Drawing:
#     . "$PSScriptRoot\vuistyle.ps1"
# ============================================================================

# ---- palette ---------------------------------------------------------------
# Neutral greys on purpose: the studio is a frame around the skin YOU are
# recolouring, so nothing in the chrome should compete with the texture
# previews. Every surface is exactly R=G=B, exactly as in Variant UI.
#
# The accent is rationed the same way the pink is over there - the wordmark,
# the thing you are on, and the one button that commits - so it always means
# "here".
#
# Sage is 158,189,148: the pink's own HSL, walked round to a green hue and let
# down to a soft, light sage (HSL 105 / 24% / 66%). It is a LIGHT accent, which
# is the one place this palette departs from Variant UI's: white on sage is a
# 2.0:1 contrast and unreadable, so filled accent buttons carry near-black
# labels (8.5:1) instead of white ones. Sage on the grey panels reads 7.3:1.
$Pal = @{
  Bg      = [System.Drawing.Color]::FromArgb(27,27,27)     # app background
  Panel   = [System.Drawing.Color]::FromArgb(40,40,40)     # cards / grouped areas
  # the card gradient stays deliberately shallow: controls that fill a flat
  # rectangle (check boxes, and anything sampling SurfaceOf) can only match ONE
  # point on it, so a strong gradient would outline each in a slightly-wrong box
  CardTop = [System.Drawing.Color]::FromArgb(44,44,44)     # card gradient - top
  CardBot = [System.Drawing.Color]::FromArgb(37,37,37)     # card gradient - bottom
  Panel2  = [System.Drawing.Color]::FromArgb(52,52,52)     # inputs, lists, raised bits
  PanelHi = [System.Drawing.Color]::FromArgb(67,67,67)     # hover
  Line    = [System.Drawing.Color]::FromArgb(74,74,74)     # hairlines / borders
  Text    = [System.Drawing.Color]::FromArgb(233,233,233)  # primary text
  Muted   = [System.Drawing.Color]::FromArgb(155,155,155)  # secondary text / hints
  Faint   = [System.Drawing.Color]::FromArgb(118,118,118)  # disabled-ish
  Sage    = [System.Drawing.Color]::FromArgb(158,189,148)  # THE accent - used sparingly
  SageLt  = [System.Drawing.Color]::FromArgb(190,214,182)  # sage text on grey
  SageDk  = [System.Drawing.Color]::FromArgb(116,146,107)  # pressed
  SageHi  = [System.Drawing.Color]::FromArgb(176,203,167)  # hover on a filled accent
  SageWash= [System.Drawing.Color]::FromArgb(60,60,60)     # hover fill (neutral)
  Amber   = [System.Drawing.Color]::FromArgb(228,172,102)  # warnings only
  Sink    = [System.Drawing.Color]::FromArgb(31,31,31)     # image wells / preview backdrops
}
function PalDim([System.Drawing.Color]$c,[double]$f){
  [System.Drawing.Color]::FromArgb(255,[int]($c.R*$f),[int]($c.G*$f),[int]($c.B*$f))
}
