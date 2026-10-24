# Saves a screenshot of the VibeKeys window. Usage: shot.ps1 <out.png>
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
}
"@
[W]::SetProcessDPIAware() | Out-Null
$h = [W]::FindWindow([NullString]::Value, "VibeKeys")
$r = New-Object W+R
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Ri - $r.L; $hh = $r.B - $r.T
"Rect: $($r.L),$($r.T) ${w}x$hh"
$bmp = New-Object Drawing.Bitmap $w, $hh
$g = [Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($args[0])
