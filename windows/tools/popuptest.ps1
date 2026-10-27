# Checks the Space and Backspace buttons in a fresh Notepad window:
#   a short click on Backspace deletes one character;
#   a long press on Space opens the symbol column, and sliding onto the second symbol types it;
#   holding Backspace keeps deleting, like a held keyboard key.
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

$vk = $root.FindFirst('Children', (New-Object $C($A::NameProperty, 'VibeKeys')))
function Center($glyph) {
  $r = $vk.FindFirst('Descendants', (New-Object $C($A::NameProperty, [string][char]$glyph))).Current.BoundingRectangle
  return @([int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2), $r.Height)
}
$bs = Center 0xE750
$sp = Center 0xE75D

[System.Windows.Forms.SendKeys]::SendWait("abc"); Start-Sleep 0.5
"Typed:             [" + (Text) + "]"

InFront
[M]::SetCursorPos($bs[0], $bs[1]) | Out-Null; Start-Sleep 0.2
[M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.8
"Backspace click:   [" + (Text) + "]   (expected ab)"

InFront
[M]::SetCursorPos($sp[0], $sp[1]) | Out-Null; Start-Sleep 0.2
[M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.8
[M]::SetCursorPos($sp[0], [int]($sp[1] - 2 * ($sp[2] + 4))) | Out-Null
Start-Sleep 0.4
# Screenshot while still holding: the symbol under the cursor should be highlighted
$bmp = New-Object Drawing.Bitmap 300, 500
[Drawing.Graphics]::FromImage($bmp).CopyFromScreen($sp[0] - 150, $sp[1] - 450, 0, 0, $bmp.Size)
$bmp.Save($args[0])
[M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.8
"Space long press:  [" + (Text) + "]   (expected ab?)"

[System.Windows.Forms.SendKeys]::SendWait("defghij"); Start-Sleep 0.5
InFront
[M]::SetCursorPos($bs[0], $bs[1]) | Out-Null; Start-Sleep 0.2
[M]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 1.5
[M]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep 0.5
"Backspace held:    [" + (Text) + "]   (expected empty: ab?defghij all deleted)"
