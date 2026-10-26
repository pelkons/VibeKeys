# Opens the Start menu, reports the VibeKeys window state and screenshots the panel area while Start
# is open, then closes Start with Esc and reports again.
# Usage: starttest.ps1 <out-prefix>   (VibeKeys must be running; briefly opens the Start menu)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Ri, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
[W]::SetProcessDPIAware() | Out-Null
$h = [W]::FindWindow([NullString]::Value, "VibeKeys")
function State($label, $prefix) {
  $r = New-Object W+R; [W]::GetWindowRect($h, [ref]$r) | Out-Null
  "{0}: visible={1} iconic={2} rect={3},{4} {5}x{6}" -f $label, [W]::IsWindowVisible($h), [W]::IsIconic($h), $r.L, $r.T, ($r.Ri - $r.L), ($r.B - $r.T)
  $b = New-Object Drawing.Bitmap 1400, 300
  [Drawing.Graphics]::FromImage($b).CopyFromScreen($r.L - 200, $r.B - 300, 0, 0, $b.Size)
  $b.Save("$($prefix)_$label.png")
}
State before $args[0]
[W]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); [W]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero)
Start-Sleep 1.5
State start-open $args[0]
[W]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); [W]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero)
Start-Sleep 1.5
State after $args[0]
