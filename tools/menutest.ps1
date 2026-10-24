# Right-clicks the VibeKeys drag handle, saves a screenshot of the menu, then dismisses it with Esc.
# Usage: menutest.ps1 <out.png>
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
}
"@
[W]::SetProcessDPIAware() | Out-Null
$h = [W]::FindWindow([NullString]::Value, "VibeKeys")
$r = New-Object W+R
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$x = $r.L + 15; $y = $r.T + 30
[W]::SetCursorPos($x, $y) | Out-Null
[W]::mouse_event(8,0,0,0,[UIntPtr]::Zero); [W]::mouse_event(16,0,0,0,[UIntPtr]::Zero)
Start-Sleep 1
$bmp = New-Object Drawing.Bitmap 500, 300
$g = [Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L - 100, $r.T - 200, 0, 0, $bmp.Size)
$bmp.Save($args[0])
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep 0.5
"Still running: " + [bool](Get-Process VibeKeys -ErrorAction SilentlyContinue)
