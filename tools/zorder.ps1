# Checks that VibeKeys stays above the taskbar after the taskbar is brought forward.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Z {
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  // true if a is above b in z-order
  public static bool Above(IntPtr a, IntPtr b) {
    for (IntPtr w = GetWindow(b, 3); w != IntPtr.Zero; w = GetWindow(w, 3)) if (w == a) return true;
    return false;
  }
}
"@
$kp = [Z]::FindWindow([NullString]::Value, "VibeKeys")
$tb = [Z]::FindWindow("Shell_TrayWnd", [NullString]::Value)
"Before: VibeKeys above taskbar = " + [Z]::Above($kp, $tb)
[Z]::SetForegroundWindow($tb) | Out-Null
"Right after taskbar activated = " + [Z]::Above($kp, $tb)
Start-Sleep 1
"1s later = " + [Z]::Above($kp, $tb)
