# Opens Notepad, clicks the VibeKeys mic button (Win+Alt), screenshots the screen while OpenWhispr
# should be recording, clicks again to stop, then prints what landed in Notepad.
# Usage: mictest.ps1 <recording.png>   (VibeKeys and OpenWhispr must be running; moves the mouse)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class M {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[M]::SetProcessDPIAware() | Out-Null
$A = [System.Windows.Automation.AutomationElement]
$C = [System.Windows.Automation.PropertyCondition]
$root = $A::RootElement

Start-Process notepad
Start-Sleep 3
$npWin = $root.FindFirst('Children', (New-Object $C($A::ClassNameProperty, 'Notepad')))
[M]::SetForegroundWindow([IntPtr]$npWin.Current.NativeWindowHandle) | Out-Null
Start-Sleep 1

$vk = $root.FindFirst('Children', (New-Object $C($A::NameProperty, 'VibeKeys')))
$mic = $vk.FindFirst('Descendants', (New-Object $C($A::NameProperty, [string][char]0xE720)))
$r = $mic.Current.BoundingRectangle
function ClickMic {
  [M]::SetCursorPos([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2)) | Out-Null
  [M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); [M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}

ClickMic
Start-Sleep 2
$scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object Drawing.Bitmap $scr.Width, $scr.Height
[Drawing.Graphics]::FromImage($bmp).CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($args[0])
ClickMic
Start-Sleep 8

$doc = $npWin.FindFirst('Descendants', (New-Object $C($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
$txt = $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
"Notepad text: [" + $txt + "]"
