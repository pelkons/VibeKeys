// SymbolPopup: a column of extra characters that pops up above a panel button on long press,
// like the alternate-key popup on a phone keyboard. Pick a character by clicking it, or by
// sliding onto it while still holding the mouse button.

using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class SymbolPopup : NoActivateForm
{
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion u; }

    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 0x2, KEYEVENTF_UNICODE = 0x4;

    const int CloseAfterMs = 1500;   // closes once the mouse has been away from it (and its button) this long

    readonly Control anchor;
    readonly Color buttonColor, hoverColor;
    readonly Timer watch = new Timer { Interval = 200 };
    DateTime lastNear = DateTime.Now;

    // symbols: first one sits right above the anchor button, the rest stack upward
    public SymbolPopup(Control anchor, string symbols, Font font, Color back, Color button, Color hover)
    {
        this.anchor = anchor;
        buttonColor = button;
        hoverColor = hover;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = back;

        // Same button size, spacing and rounding as the anchor, so the column looks like part of the panel
        int m = anchor.Margin.Left;
        var anchorButton = anchor as NoFocusButton;
        var column = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.BottomUp, WrapContents = false, Dock = DockStyle.Fill, Padding = new Padding(m),
        };
        Controls.Add(column);
        foreach (var ch in symbols)
        {
            var c = ch;
            var b = new NoFocusButton
            {
                Text = c.ToString(), Font = font, ForeColor = Color.White, BackColor = button,
                Size = anchor.Size, Margin = new Padding(m), Cursor = Cursors.Hand,
                CornerRadius = anchorButton != null ? anchorButton.CornerRadius : 6,
            };
            b.FlatAppearance.MouseOverBackColor = hover;
            b.Click += (o, e) => Pick(c);
            column.Controls.Add(b);
        }

        ClientSize = new Size(anchor.Width + 4 * m, symbols.Length * (anchor.Height + 2 * m) + 2 * m);
        var r = anchor.RectangleToScreen(anchor.ClientRectangle);
        Location = new Point(r.Left - 2 * m, r.Top - 3 * m - Height);
        if (Top < Screen.FromControl(anchor).Bounds.Top) Top = r.Bottom + 3 * m;   // no room above: open downward

        watch.Tick += (o, e) =>
        {
            var p = Cursor.Position;
            if (Bounds.Contains(p) || anchor.RectangleToScreen(anchor.ClientRectangle).Contains(p)) lastNear = DateTime.Now;
            else if ((DateTime.Now - lastNear).TotalMilliseconds > CloseAfterMs) Close();
        };
        watch.Start();
        FormClosed += (o, e) => watch.Dispose();
    }

    // Phone-style slide: while the mouse button that opened us is still held, light up the symbol
    // under the cursor; on release, type that symbol. Mouse messages during the hold go to whichever
    // window holds capture, so this polls the cursor and button state instead of relying on them.
    public void TrackHeldButton()
    {
        var drag = new Timer { Interval = 30 };
        drag.Tick += (o, e) =>
        {
            if ((Control.MouseButtons & MouseButtons.Left) != 0)
            {
                foreach (Control c in Controls[0].Controls) c.BackColor = IsUnderCursor(c) ? hoverColor : buttonColor;
                return;
            }
            drag.Dispose();
            foreach (Control c in Controls[0].Controls)
                if (IsUnderCursor(c)) { Pick(c.Text[0]); return; }
            foreach (Control c in Controls[0].Controls) c.BackColor = buttonColor;   // released elsewhere: stay open for a click
        };
        drag.Start();
        FormClosed += (o, e) => drag.Dispose();
    }

    static bool IsUnderCursor(Control c)
    {
        return c.RectangleToScreen(c.ClientRectangle).Contains(Cursor.Position);
    }

    void Pick(char c)
    {
        TypeChar(c);
        Close();
    }

    // Types the character itself rather than a key, so it comes out right in any keyboard layout
    static void TypeChar(char c)
    {
        var down = new INPUT { type = INPUT_KEYBOARD };
        down.u.ki = new KEYBDINPUT { wScan = c, dwFlags = KEYEVENTF_UNICODE };
        var up = down;
        up.u.ki.dwFlags |= KEYEVENTF_KEYUP;
        SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
    }
}
