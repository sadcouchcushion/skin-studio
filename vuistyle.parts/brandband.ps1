
# ---- retitling a card -------------------------------------------------------
# PaintCard takes the caption OFF a GroupBox (WinForms draws its own before our
# Paint handler runs, so it would show twice, slightly offset) and paints it
# from $script:cardTitle instead. Anything that used to assign .Text at runtime
# has to come through here, or the native caption comes back AND the painted one
# never changes.
function Set-CardTitle($ctl,[string]$title){
  $script:cardTitle[$ctl] = $title
  if($ctl -is [System.Windows.Forms.GroupBox]){ $ctl.Text='' }
  $ctl.Invalidate()
}

# ---- the brand band ---------------------------------------------------------
# Variant UI wears its lockup down the side of the always-on guide column. Skin
# Studio has no guide column - every pixel of width is spoken for by the four
# working columns - so the same brand block lies on its side as a strip across
# the top: lockup, sage rule, the app's name in the display face, and a muted
# note on the right the app keeps up to date (which skin is open).
#
# It is a card like any other, so it picks up the same gradient, hairline and
# rounded corners as the panels below it.
#
# The strings live in script scope, not on the control: the Paint handler is a
# plain script block on purpose (a .GetNewClosure() one could not reach FunFont
# or $Pal at all), and Tag is already spoken for by the card radius.
$script:brandNote    = ''
$script:brandTitle   = ''
$script:brandSub     = ''
$script:brandNoteCtl = $null
function AddBrandHeader($parent,[int]$x,[int]$y,[int]$w,[int]$h,[string]$title,[string]$sub){
  $p = New-Object System.Windows.Forms.Panel
  $p.Location = New-Object System.Drawing.Point($x,$y)
  $p.Size = New-Object System.Drawing.Size($w,$h)
  $p.BackColor = $Pal.Panel
  $parent.Controls.Add($p)
  $script:brandTitle = $title
  $script:brandSub   = $sub
  $script:brandNoteCtl = $p
  DoubleBuffer $p
  SetGradientBg $p
  $p.Tag = 'keep-card r12'
  $p.Add_Paint({
    param($s,$e)
    $gfx=$e.Graphics; $gfx.SmoothingMode='AntiAlias'; $gfx.TextRenderingHint='ClearTypeGridFit'
    $path=RoundedPath 0.5 0.5 ($s.Width-1.5) ($s.Height-1.5) 12
    # knock the corners back to the app background, then edge the card
    $ring=RingPath $s.Width $s.Height $path
    $sb=New-Object System.Drawing.SolidBrush($Pal.Bg); $gfx.FillPath($sb,$ring); $sb.Dispose(); $ring.Dispose()
    $pn=New-Object System.Drawing.Pen($Pal.Line,1); $gfx.DrawPath($pn,$path); $pn.Dispose(); $path.Dispose()
    $gfx.InterpolationMode='HighQualityBicubic'
    $lx = 18.0
    if($script:wordImg){
      # the real lockup - badge and wordmark are one drawing, so nothing here
      # has to fake the spacing between them. Height drives the size; the width
      # comes off the artwork's own aspect so a re-export can change shape safely.
      $wh = 26.0
      $ww = [single]($wh * ($script:wordImg.Width / [double]$script:wordImg.Height))
      $gfx.DrawImage($script:wordImg,[single]$lx,8.0,$ww,[single]$wh)
      $rule=RoundedPath ([single]($lx+1)) 38 44 3 1.5
      $br=New-Object System.Drawing.SolidBrush($Pal.Sage); $gfx.FillPath($br,$rule); $br.Dispose(); $rule.Dispose()
      $lx = $lx + $ww + 20
    } elseif($script:markImg){
      $gfx.DrawImage($script:markImg,[int]$lx,10,28,28)
      $lx = $lx + 44
    }
    # the hairline that separates the product from this app's own name
    $ln=New-Object System.Drawing.SolidBrush($Pal.Line)
    $gfx.FillRectangle($ln,[single]$lx,12,1,($s.Height-24)); $ln.Dispose()
    $lx = $lx + 17
    $ttl=[string]$script:brandTitle; if(-not $ttl){ $ttl='Skin Studio' }
    $f=FunFont 12 13
    $tb=New-Object System.Drawing.SolidBrush($Pal.Text)
    $gfx.DrawString($ttl,$f,$tb,[single]$lx,6.0)
    $f.Dispose(); $tb.Dispose()
    $sb2=[string]$script:brandSub
    if($sb2){
      $f2=UIFont 8.25
      $mb=New-Object System.Drawing.SolidBrush($Pal.Muted)
      $gfx.DrawString($sb2,$f2,$mb,[single]($lx+2),27.0)
      $f2.Dispose(); $mb.Dispose()
    }
    # right-hand note: whatever the app last put there (the open skin)
    if($script:brandNote){
      $f3=UIFont 8.25
      $mb=New-Object System.Drawing.SolidBrush($Pal.Muted)
      $nw=$gfx.MeasureString($script:brandNote,$f3).Width
      $gfx.DrawString($script:brandNote,$f3,$mb,[single]($s.Width-20-$nw),[single](($s.Height-15)/2))
      $f3.Dispose(); $mb.Dispose()
    }
  })
  return $p
}
function Set-BrandNote([string]$text){
  $script:brandNote = $text
  if($script:brandNoteCtl){ $script:brandNoteCtl.Invalidate() }
}

# ---- a status strip we own --------------------------------------------------
# StatusStrip is a ToolStrip: it renders from the system theme's colour table,
# so a dark BackColor still leaves a light 1px top border and a light grip. A
# docked Panel with a Label in it is the whole feature, and it takes the
# palette without argument.
function AddStatusBar($form,[string]$initial){
  $bar = New-Object System.Windows.Forms.Panel
  $bar.Height = 26; $bar.Dock = 'Bottom'; $bar.BackColor = $Pal.Panel
  DoubleBuffer $bar
  $bar.Add_Paint({
    param($s,$e)
    $pn=New-Object System.Drawing.Pen($Pal.Line,1)
    $e.Graphics.DrawLine($pn,0,0,$s.Width,0); $pn.Dispose()
  })
  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Location = New-Object System.Drawing.Point(16,5)
  $lbl.Size = New-Object System.Drawing.Size(($form.ClientSize.Width-32),18)
  $lbl.ForeColor = $Pal.SageLt
  $lbl.BackColor = [System.Drawing.Color]::Transparent
  $lbl.Text = $initial
  $lbl.Tag = 'keep-status'          # StyleTree must not relight it to Muted
  $bar.Controls.Add($lbl)
  $form.Controls.Add($bar)
  return $lbl
}
