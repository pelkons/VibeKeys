# Opens Notepad, clicks VibeKeys buttons with the mouse and prints the resulting text.
# VibeKeys must be running. Moves the mouse while it runs.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[M]::SetProcessDPIAware() | Out-Null
$A = [System.Windows.Automation.AutomationElement]
$C = [System.Windows.Automation.PropertyCondition]
$root = $A::RootElement

$np = Start-Process notepad -PassThru
Start-Sleep 3
$npWin = $root.FindFirst('Children', (New-Object $C($A::ClassNameProperty, 'Notepad')))
$h = [IntPtr]$npWin.Current.NativeWindowHandle
[M]::SetForegroundWindow($h) | Out-Null
Start-Sleep 1
[System.Windows.Forms.SendKeys]::SendWait("line1")
Start-Sleep 0.5

$kp = $root.FindFirst('Children', (New-Object $C($A::NameProperty, 'VibeKeys')))
function ClickBtn($name) {
  $b = $kp.FindFirst('Descendants', (New-Object $C($A::NameProperty, $name)))
  $r = $b.Current.BoundingRectangle
  [M]::SetCursorPos([int]($r.X + $r.Width/2), [int]($r.Y + $r.Height/2)) | Out-Null
  [M]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [M]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  Start-Sleep 0.5
}
# Buttons are found by their icon-font label (see Keys_ in VibeKeys.cs)
ClickBtn ([string][char]0xE751)                                  # Enter
[System.Windows.Forms.SendKeys]::SendWait("line2")
ClickBtn ([string][char]0xE8E4)                                  # Shift+Enter
[System.Windows.Forms.SendKeys]::SendWait("line3x")
ClickBtn ([string][char]0xE750)                                  # Backspace
"Foreground still Notepad: " + ([M]::GetForegroundWindow() -eq $h)

$doc = $npWin.FindFirst('Descendants', (New-Object $C($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
$txt = $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
"Text: [" + ($txt -replace "`r", '\r' -replace "`n", '\n') + "]"
