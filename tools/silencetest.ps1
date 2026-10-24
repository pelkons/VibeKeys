# Clicks the VibeKeys mic button in a fresh Notepad window and, without anyone speaking, watches for
# 15 seconds whether the button stays highlighted (ff205c96 = recording, ff3e3e42 = idle).
# Auto-stop should end the recording after NoSpeechMs (8 s). Clicks the mic again at the end if it did not.
# Usage: silencetest.ps1 [screenshot-prefix]   (saves full screenshots at 3 s and 12 s)
# (VibeKeys and OpenWhispr must be running; moves the mouse; keep quiet while it runs)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[M]::SetProcessDPIAware() | Out-Null
$A = [System.Windows.Automation.AutomationElement]
$C = [System.Windows.Automation.PropertyCondition]

Start-Process notepad
Start-Sleep 3
$h = [M]::GetForegroundWindow()
$cls = New-Object Text.StringBuilder 64; [M]::GetClassName($h, $cls, 64) | Out-Null
if ($cls.ToString() -ne 'Notepad') { "New Notepad window is not in front ($cls), stopping"; exit 1 }

$vk = $A::RootElement.FindFirst('Children', (New-Object $C($A::NameProperty, 'VibeKeys')))
$r = $vk.FindFirst('Descendants', (New-Object $C($A::NameProperty, [string][char]0xE720))).Current.BoundingRectangle
$x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
function MicColor { $b = New-Object Drawing.Bitmap 1, 1; [Drawing.Graphics]::FromImage($b).CopyFromScreen([int]$r.X + 3, [int]$r.Y + 3, 0, 0, $b.Size); $b.GetPixel(0, 0).Name }

"before: color " + (MicColor)
[M]::SetCursorPos($x, $y) | Out-Null
[M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
[M]::SetCursorPos($x, $y - 400) | Out-Null   # move away so hover colour does not hide the state
for ($i = 1; $i -le 15; $i++) {
  Start-Sleep 1; "{0,2}s: color {1}" -f $i, (MicColor)
  if ($args[0] -and ($i -eq 3 -or $i -eq 12)) { $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $b = New-Object Drawing.Bitmap $s.Width, $s.Height; [Drawing.Graphics]::FromImage($b).CopyFromScreen(0, 0, 0, 0, $b.Size); $b.Save(($args[0] + "_$i.png")) }
}
if ((MicColor) -ne 'ff3e3e42') {
  "still recording after 15 s -> clicking mic to stop"
  [M]::SetCursorPos($x, $y) | Out-Null
  [M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}
