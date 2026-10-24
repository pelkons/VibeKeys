# Draws the VibeKeys icon (a blue keycap with an Enter arrow) and writes a multi-size .ico.
# Usage: make-icon.ps1 <out.ico> [preview.png] [-MacPng AppIcon.png]
#   -MacPng also writes the 1024 px master for macos/build.sh, with the margin macOS icons use.
param([string]$Out, [string]$Preview, [string]$MacPng)
Add-Type -AssemblyName System.Drawing

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function Frame([int]$n) {
  $bmp = New-Object Drawing.Bitmap $n, $n, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.TextRenderingHint = 'AntiAliasGridFit'
  $g.PixelOffsetMode = 'HighQuality'

  # Background tile: sky blue to indigo
  $bg = RoundRect 0 0 $n $n ($n * 0.22)
  $grad = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, 0), (New-Object Drawing.PointF $n, $n), ([Drawing.Color]::FromArgb(56, 189, 248)), ([Drawing.Color]::FromArgb(79, 70, 229))
  $g.FillPath($grad, $bg)

  $glyphBox = New-Object Drawing.RectangleF 0, 0, $n, $n
  $glyphSize = $n * 0.78
  if ($n -ge 48) {
    # Raised keycap: soft shadow, then a translucent white cap
    $pad = $n * 0.15; $cw = $n - 2 * $pad; $ch = $n - 2 * $pad - $n * 0.05
    $shadow = RoundRect $pad ($pad + $n * 0.06) $cw $ch ($n * 0.12)
    $g.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(60, 20, 20, 60))), $shadow)
    $cap = RoundRect $pad $pad $cw $ch ($n * 0.12)
    $capBrush = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.PointF 0, $pad), (New-Object Drawing.PointF 0, ($pad + $ch)), ([Drawing.Color]::FromArgb(90, 255, 255, 255)), ([Drawing.Color]::FromArgb(35, 255, 255, 255))
    $g.FillPath($capBrush, $cap)
    $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(110, 255, 255, 255)), ([math]::Max(1, $n / 64))), $cap)
    $glyphBox = New-Object Drawing.RectangleF $pad, $pad, $cw, $ch
    $glyphSize = $n * 0.40
  }

  # Enter arrow from the Windows icon font, outlined a little so it stays bold at tray sizes
  $fmt = New-Object Drawing.StringFormat
  $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $arrow = New-Object Drawing.Drawing2D.GraphicsPath
  $arrow.AddString([string][char]0xE751, (New-Object Drawing.FontFamily 'Segoe Fluent Icons'), 0, $glyphSize, $glyphBox, $fmt)
  $g.FillPath([Drawing.Brushes]::White, $arrow)
  $stroke = New-Object Drawing.Pen ([Drawing.Color]::White), ([math]::Max(0.7, $n * 0.025))
  $stroke.LineJoin = 'Round'
  $g.DrawPath($stroke, $arrow)
  $g.Dispose()
  return $bmp
}

# 32-bit DIB entry (what every icon reader understands) for small sizes, PNG for 256
function DibBytes([Drawing.Bitmap]$bmp) {
  $n = $bmp.Width
  $ms = New-Object IO.MemoryStream
  $bw = New-Object IO.BinaryWriter $ms
  $maskRow = [int]([math]::Ceiling($n / 32) * 4)
  $bw.Write([uint32]40); $bw.Write([int32]$n); $bw.Write([int32]($n * 2))
  $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]0)
  $bw.Write([uint32]($n * $n * 4 + $maskRow * $n)); $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)
  $data = $bmp.LockBits((New-Object Drawing.Rectangle 0, 0, $n, $n), 'ReadOnly', ([Drawing.Imaging.PixelFormat]::Format32bppArgb))
  $row = New-Object byte[] ($n * 4)
  for ($y = $n - 1; $y -ge 0; $y--) {
    [Runtime.InteropServices.Marshal]::Copy([IntPtr]($data.Scan0.ToInt64() + $y * $data.Stride), $row, 0, $n * 4)
    $bw.Write($row)
  }
  $bmp.UnlockBits($data)
  $bw.Write((New-Object byte[] ($maskRow * $n)))
  return $ms.ToArray()
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 256
$frames = @{}
$blobs = foreach ($s in $sizes) {
  $f = Frame $s; $frames[$s] = $f
  if ($s -eq 256) { $ms = New-Object IO.MemoryStream; $f.Save($ms, [Drawing.Imaging.ImageFormat]::Png); , $ms.ToArray() }
  else { , (DibBytes $f) }
}

$fs = [IO.File]::Create($Out)
$bw = New-Object IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i] % 256
  $bw.Write([byte]$s); $bw.Write([byte]$s); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$blobs[$i].Length); $bw.Write([uint32]$offset)
  $offset += $blobs[$i].Length
}
foreach ($b in $blobs) { $bw.Write([byte[]]$b) }
$bw.Close()

if ($MacPng) {
  # macOS icon grid: the tile fills about 824 of 1024 px, centred
  $mac = New-Object Drawing.Bitmap 1024, 1024, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($mac)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage((Frame 824), 100, 100, 824, 824)
  $mac.Save($MacPng, [Drawing.Imaging.ImageFormat]::Png)
}

if ($Preview) {
  $pv = New-Object Drawing.Bitmap 520, 280
  $g = [Drawing.Graphics]::FromImage($pv)
  $g.Clear([Drawing.Color]::FromArgb(32, 32, 32))
  $g.DrawImage($frames[256], 10, 10, 256, 256)
  $x = 280
  foreach ($s in 16, 24, 32, 48, 64) { $g.DrawImageUnscaled($frames[$s], $x, 20); $x += $s + 14 }
  $x = 280
  foreach ($s in 16, 24, 32, 48) { $g.InterpolationMode = 'NearestNeighbor'; $g.DrawImage($frames[$s], $x, 120, $s * 3, $s * 3); $x += $s * 3 + 10 }
  $pv.Save($Preview)
}
