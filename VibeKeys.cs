// VibeKeys: a small always-on-top panel with a few keyboard keys for mouse-only use.
// The window never takes focus, so a click sends the key to whatever window you were typing in.
// Build: build.cmd (uses the C# compiler that ships with Windows, no installs needed).

using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

class VibeKeys : NoActivateForm
{
    // OpenWhispr dictation hotkey; its button also gets auto-stop on silence (see ToggleDictation)
    static readonly byte[] DictationKeys = { VK_LWIN, VK_MENU };
    const int SilenceMs = 2000, NoSpeechMs = 8000;

    // Long press on Backspace pops up these characters, first one closest to the button
    const string BackspaceSymbols = ".?,!";
    const int LongPressMs = 450;

    // ---- Buttons: label, hover hint, keys pressed together (modifiers first). Edit this list to change the panel. ----
    // Labels made of \uE000+ characters are drawn with the Windows icon font (Segoe Fluent Icons), others as plain text.
    static readonly object[][] Keys_ =
    {
        new object[] { "\uE720",       "Диктовка OpenWhispr (Win+Alt)", DictationKeys },
        new object[] { "\uE8FB",       "Подтвердить (Ctrl+Enter)",   new byte[] { VK_CONTROL, VK_RETURN } },
        new object[] { "\uE751",       "Enter",                      new byte[] { VK_RETURN } },
        new object[] { "\uE8E4",       "Новая строка (Shift+Enter)", new byte[] { VK_SHIFT, VK_RETURN } },
        new object[] { "\uE7A7",       "Отменить (Ctrl+Z)",          new byte[] { VK_CONTROL, (byte)'Z' } },
        new object[] { "Esc",          "Escape",                     new byte[] { VK_ESCAPE } },
        new object[] { "\uE924",       "Скриншот области (Win+Shift+S)", new byte[] { VK_LWIN, VK_SHIFT, (byte)'S' } },
        new object[] { "\uE750",       "Стереть (Backspace)",        new byte[] { VK_BACK } },
    };

    const byte VK_BACK = 0x08, VK_RETURN = 0x0D, VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_ESCAPE = 0x1B, VK_LWIN = 0x5B;
    const uint KEYEVENTF_KEYUP = 0x2;

    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10;

    static readonly string SettingsDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "VibeKeys");
    static readonly string PosFile = Path.Combine(SettingsDir, "position.txt");

    // Autostart is on unless the user turned it off in the tray menu (remembered in autostart.txt)
    static readonly string AutostartFile = Path.Combine(SettingsDir, "autostart.txt");
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    static readonly Color ButtonColor = Color.FromArgb(62, 62, 66), HoverColor = Color.FromArgb(0, 122, 204),
        RecordingColor = Color.FromArgb(32, 92, 150);   // muted blue, calmer than the hover color

    Point dragStart;
    bool dragging;
    Button micButton;
    SilenceWatcher watcher;
    SymbolPopup popup;

    VibeKeys()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(45, 45, 48);
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Text = "VibeKeys";

        float s;
        using (var g = CreateGraphics()) s = g.DpiX / 96f;
        var iconFont = new Font(HasFont("Segoe Fluent Icons") ? "Segoe Fluent Icons" : "Segoe MDL2 Assets", 13f);
        var textFont = new Font("Segoe UI Semibold", 10.5f);
        var tips = new ToolTip { ShowAlways = true, InitialDelay = 600 };
        Padding = new Padding((int)(3 * s));   // breathing room inside the rounded window
        var gap = new Padding((int)(2 * s));

        var row = new FlowLayoutPanel
        {
            AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, WrapContents = false, Margin = Padding.Empty,
            Location = new Point(Padding.Left, Padding.Top),   // form Padding only grows the size, it doesn't move controls
        };
        Controls.Add(row);

        // Drag handle: left button drags, right button opens a menu (hide to tray / exit)
        var grip = new Label
        {
            Text = "\uE75F", ForeColor = Color.Gray, Font = iconFont, Cursor = Cursors.SizeAll,
            TextAlign = ContentAlignment.MiddleCenter, Size = new Size((int)(18 * s), (int)(34 * s)), Margin = gap,
        };
        grip.MouseDown += (o, e) => { if (e.Button == MouseButtons.Left) { dragging = true; dragStart = e.Location; } };
        grip.MouseMove += (o, e) => { if (dragging) Location = new Point(Left + e.X - dragStart.X, Top + e.Y - dragStart.Y); };
        grip.MouseUp += (o, e) => { if (dragging) { dragging = false; KeepOnScreen(); SavePosition(); } };
        var menu = new ContextMenuStrip { Font = new Font("Segoe UI", 10f) };
        menu.Items.Add("Скрыть в трей", null, (o, e) => Hide());
        menu.Items.Add("Выход", null, (o, e) => Close());
        grip.ContextMenuStrip = menu;
        tips.SetToolTip(grip, "Тянуть — переместить, правый клик — меню");
        row.Controls.Add(grip);

        foreach (var k in Keys_)
        {
            var keys = (byte[])k[2];
            var label = (string)k[0];
            bool isIcon = label[0] >= '\uE000';
            int width = isIcon ? 44 + 16 * (label.Length - 1) : 44;   // two-icon buttons get extra room
            var b = new NoFocusButton
            {
                Text = label, Font = isIcon ? iconFont : textFont,
                ForeColor = Color.White, BackColor = ButtonColor,
                Size = new Size((int)(width * s), (int)(34 * s)),
                Margin = gap, Cursor = Cursors.Hand, CornerRadius = (int)(6 * s),
            };
            tips.SetToolTip(b, (string)k[1]);
            b.FlatAppearance.MouseOverBackColor = HoverColor;
            if (keys == DictationKeys) { micButton = b; b.Click += (o, e) => ToggleDictation(); }
            else if (keys.Length == 1 && keys[0] == VK_BACK) AttachSymbolPopup(b, keys, BackspaceSymbols);
            else b.Click += (o, e) => Press(keys);
            row.Controls.Add(b);
        }

        Location = LoadPosition();
        Load += (o, e) => KeepOnScreen();

        // Tray icon: left click shows/hides the panel, right click opens a menu
        var trayMenu = new ContextMenuStrip { Font = new Font("Segoe UI", 10f) };
        trayMenu.Items.Add("Показать / скрыть панель", null, (o, e) => Toggle());
        var autostart = new ToolStripMenuItem("Запускать вместе с Windows") { Checked = AutostartWanted(), CheckOnClick = true };
        autostart.CheckedChanged += (o, e) => ApplyAutostart(autostart.Checked);
        trayMenu.Items.Add(autostart);
        trayMenu.Items.Add(new ToolStripSeparator());
        trayMenu.Items.Add("Выход", null, (o, e) => Close());
        ApplyAutostart(autostart.Checked);   // also re-points the entry if the exe was moved
        var tray = new NotifyIcon { Icon = LoadIcon(), Text = "VibeKeys", ContextMenuStrip = trayMenu, Visible = true };
        tray.MouseClick += (o, e) => { if (e.Button == MouseButtons.Left) Toggle(); };
        FormClosed += (o, e) => { tray.Dispose(); if (watcher != null) watcher.Dispose(); };

        // The taskbar is also topmost and jumps above us when clicked, so keep pushing ourselves back on top
        var raise = new System.Windows.Forms.Timer { Interval = 300 };
        raise.Tick += (o, e) => { if (Visible && !dragging) SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE); };
        raise.Start();
    }

    void Toggle()
    {
        if (Visible) Hide(); else Show();
    }

    // First click starts OpenWhispr and listens to the mic; a pause (or a second click) stops it.
    // The button stays highlighted while recording.
    void ToggleDictation()
    {
        Press(DictationKeys);
        if (watcher != null) { StopWatching(); return; }

        watcher = new SilenceWatcher(SilenceMs, NoSpeechMs);
        watcher.Quiet += () => { Press(DictationKeys); StopWatching(); };
        if (!watcher.Start()) { watcher = null; return; }   // no microphone available: plain toggle
        micButton.BackColor = micButton.FlatAppearance.MouseOverBackColor = RecordingColor;
    }

    // Short click presses the key; holding it opens a column of symbols above the button
    void AttachSymbolPopup(Button b, byte[] keys, string symbols)
    {
        var hold = new System.Windows.Forms.Timer { Interval = LongPressMs };
        bool longPressed = false;
        hold.Tick += (o, e) =>
        {
            hold.Stop();
            if ((Control.MouseButtons & MouseButtons.Left) == 0) return;   // released already, MouseUp just got lost
            longPressed = true;
            if (popup != null) popup.Close();
            var p = new SymbolPopup(b, symbols, new Font("Segoe UI Semibold", 14f), BackColor, ButtonColor, HoverColor);
            p.FormClosed += (o2, e2) => { if (popup == p) popup = null; };
            popup = p;
            p.Show();
            p.TrackHeldButton();   // slide onto a symbol and release to type it
        };
        b.MouseDown += (o, e) => { if (e.Button == MouseButtons.Left) { longPressed = false; hold.Start(); } };
        b.MouseUp += (o, e) => hold.Stop();
        b.Click += (o, e) => { if (!longPressed) Press(keys); };
    }

    void StopWatching()
    {
        watcher.Dispose();
        watcher = null;
        micButton.BackColor = ButtonColor;
        micButton.FlatAppearance.MouseOverBackColor = HoverColor;
    }

    // vibekeys.ico is embedded into the exe by build.cmd
    static Icon LoadIcon()
    {
        using (var s = typeof(VibeKeys).Assembly.GetManifestResourceStream("vibekeys.ico"))
            return new Icon(s, SystemInformation.SmallIconSize);
    }

    static bool HasFont(string name)
    {
        foreach (var f in FontFamily.Families) if (f.Name == name) return true;
        return false;
    }

    static void Press(byte[] keys)
    {
        foreach (var k in keys) keybd_event(k, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);   // brief hold so global-hotkey listeners (OpenWhispr) see the combo
        for (int i = keys.Length - 1; i >= 0; i--) keybd_event(keys[i], 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    Point LoadPosition()
    {
        try
        {
            var p = File.ReadAllText(PosFile).Split(',');
            var pt = new Point(int.Parse(p[0]), int.Parse(p[1]));
            foreach (var scr in Screen.AllScreens)
                if (scr.Bounds.Contains(pt)) return pt;   // Bounds, not WorkingArea: the panel may sit on the taskbar
        }
        catch { }
        var wa = Screen.PrimaryScreen.WorkingArea;
        return new Point(wa.Right - 420, wa.Bottom - 70);
    }

    static bool AutostartWanted()
    {
        try { return File.ReadAllText(AutostartFile).Trim() != "off"; }
        catch { return true; }   // never chosen: on by default
    }

    // Adds or removes VibeKeys in the current user's Run key and remembers the choice
    static void ApplyAutostart(bool on)
    {
        try
        {
            using (var key = Registry.CurrentUser.OpenSubKey(RunKey, true))
            {
                if (on) key.SetValue("VibeKeys", "\"" + Application.ExecutablePath + "\"");
                else key.DeleteValue("VibeKeys", false);
            }
            Directory.CreateDirectory(SettingsDir);
            File.WriteAllText(AutostartFile, on ? "on" : "off");
        }
        catch { }
    }

    // Pulls the whole panel back inside its screen (a saved spot can be off by a few pixels after a resize)
    void KeepOnScreen()
    {
        var area = Screen.FromControl(this).Bounds;
        Left = Math.Max(area.Left, Math.Min(Left, area.Right - Width));
        Top = Math.Max(area.Top, Math.Min(Top, area.Bottom - Height));
    }

    void SavePosition()
    {
        try
        {
            Directory.CreateDirectory(SettingsDir);
            File.WriteAllText(PosFile, Left + "," + Top);
        }
        catch { }
    }

    [STAThread]
    static void Main()
    {
        bool first;
        using (new Mutex(true, "VibeKeys_single_instance", out first))
        {
            if (!first) return;
            SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.Run(new VibeKeys());
        }
    }
}
