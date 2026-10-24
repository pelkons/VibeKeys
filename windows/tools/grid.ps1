# Renders 256 Segoe Fluent Icons glyphs with their codes, to pick icons for buttons.
# Usage: grid.ps1 E700 <out.png>
Add-Type -AssemblyName System.Drawing
$start = [Convert]::ToInt32($args[0], 16)
$cols = 16; $rows = 16; $cw = 70; $ch = 60
$bmp = New-Object Drawing.Bitmap ($cols * $cw), ($rows * $ch)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::FromArgb(45,45,48))
$g.TextRenderingHint = 'AntiAlias'
$icon = New-Object Drawing.Font 'Segoe Fluent Icons', 16
$lbl = New-Object Drawing.Font 'Consolas', 7
for ($i = 0; $i -lt $cols * $rows; $i++) {
  $c = $start + $i; $x = ($i % $cols) * $cw; $y = [math]::Floor($i / $cols) * $ch
  $g.DrawString([string][char]$c, $icon, [Drawing.Brushes]::White, $x + 18, $y + 4)
  $g.DrawString($c.ToString('X4'), $lbl, [Drawing.Brushes]::Gray, $x + 18, $y + 44)
}
$bmp.Save($args[1])
