# Checks the Backspace button in a fresh Notepad window: a short click deletes one character, and a
# long press opens the symbol column; sliding onto the second symbol and releasing types it.
# Usage: popuptest.ps1 <popup.png>   (VibeKeys must be running; moves the mouse)
# Stops before clicking anything if the new Notepad window is not in front.
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
$root = $A::RootElement

Start-Process notepad
Start-Sleep 3
$h = [M]::GetForegroundWindow()
$cls = New-Object Text.StringBuilder 64; [M]::GetClassName($h, $cls, 64) | Out-Null
if ($cls.ToString() -ne 'Notepad') { "New Notepad window is not in front ($cls), stopping"; exit 1 }
$doc = $A::FromHandle($h).FindFirst('Descendants', (New-Object $C($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Document)))
function Text { $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1) }
function InFront { if ([M]::GetForegroundWindow() -ne $h) { "Notepad lost focus, stopping"; exit 1 } }

[System.Windows.Forms.SendKeys]::SendWait("abc"); Start-Sleep 0.5
"Typed:            [" + (Text) + "]"

$vk = $root.FindFirst('Children', (New-Object $C($A::NameProperty, 'VibeKeys')))
$r = $vk.FindFirst('Descendants', (New-Object $C($A::NameProperty, [string][char]0xE750))).Current.BoundingRectangle
$x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)

InFront
[M]::SetCursorPos($x, $y) | Out-Null
[M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.8
"After short click: [" + (Text) + "]   (expected ab)"

InFront
[M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.8
[M]::SetCursorPos($x, [int]($y - 2 * ($r.Height + 2))) | Out-Null
Start-Sleep 0.3
# Screenshot while still holding: the symbol under the cursor should be highlighted
$bmp = New-Object Drawing.Bitmap 300, 500
[Drawing.Graphics]::FromImage($bmp).CopyFromScreen($x - 150, $y - 450, 0, 0, $bmp.Size)
$bmp.Save($args[0])
[M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.8
"After long press:  [" + (Text) + "]   (expected ab?)"
