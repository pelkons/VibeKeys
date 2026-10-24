// Console check for SilenceWatcher: prints the mic level and threshold every 200 ms and reports when
// it would have stopped dictation. Does not press any keys.
// Build and run: tools\leveltest.cmd [seconds]

using System;
using System.Windows.Forms;

static class LevelTest
{
    [STAThread]
    static void Main(string[] args)
    {
        int seconds = args.Length > 0 ? int.Parse(args[0]) : 6;
        var watcher = new SilenceWatcher(2000, 8000);
        var started = DateTime.Now;
        watcher.Quiet += () => { Console.WriteLine("QUIET after {0:0.0}s -> would press Win+Alt", (DateTime.Now - started).TotalSeconds); Application.Exit(); };
        if (!watcher.Start()) { Console.WriteLine("Could not open the microphone"); return; }

        var print = new Timer { Interval = 200 };
        print.Tick += (o, e) =>
        {
            Console.WriteLine("{0,5:0.0}s  level {1,6:0}  threshold {2,6:0}", (DateTime.Now - started).TotalSeconds, watcher.LastLevel, watcher.Threshold);
            if ((DateTime.Now - started).TotalSeconds > seconds) { Console.WriteLine("time limit, no stop"); Application.Exit(); }
        };
        print.Start();
        Application.Run();
        watcher.Dispose();
    }
}
