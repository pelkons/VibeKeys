// SilenceWatcher: listens to the default microphone and raises Quiet once the speaker has stopped talking.
// Uses the plain winmm waveIn API, so it needs nothing beyond Windows itself.

using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class SilenceWatcher : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    struct WAVEFORMATEX { public ushort wFormatTag, nChannels; public uint nSamplesPerSec, nAvgBytesPerSec; public ushort nBlockAlign, wBitsPerSample, cbSize; }

    [StructLayout(LayoutKind.Sequential)]
    struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength, dwBytesRecorded; public IntPtr dwUser; public uint dwFlags, dwLoops; public IntPtr lpNext, reserved; }

    [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr h, uint device, ref WAVEFORMATEX fmt, IntPtr callback, IntPtr instance, uint flags);
    [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr h, IntPtr hdr, int size);
    [DllImport("winmm.dll")] static extern int waveInStart(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInReset(IntPtr h);
    [DllImport("winmm.dll")] static extern int waveInClose(IntPtr h);

    const uint WAVE_MAPPER = 0xFFFFFFFF, WHDR_DONE = 1;
    const int Rate = 16000, BlockMs = 100, BlockBytes = Rate * 2 * BlockMs / 1000, BufferCount = 4;
    const double MinThreshold = 250;    // RMS of 16-bit samples; quiet room noise is usually well below this
    const int SpeechRunMs = 250;        // loud audio this long without a break counts as speech; shorter
                                        // bursts (mouse clicks, a knock) neither count as speech nor end the pause
    const int MaxSessionMs = 5 * 60 * 1000;   // safety cap: never keep a recording going longer than this

    static readonly int HdrSize = Marshal.SizeOf(typeof(WAVEHDR));
    static readonly int FlagsOffset = (int)Marshal.OffsetOf(typeof(WAVEHDR), "dwFlags");
    static readonly int RecordedOffset = (int)Marshal.OffsetOf(typeof(WAVEHDR), "dwBytesRecorded");

    readonly int silenceMs, noSpeechMs;
    readonly Timer poll = new Timer { Interval = 50 };
    readonly short[] samples = new short[BlockBytes / 2];
    readonly IntPtr[] headers = new IntPtr[BufferCount];
    IntPtr wave;

    double noiseFloor = -1;
    int loudRunMs, quietMs, totalMs;
    bool spoke;

    public event Action Quiet;
    public double LastLevel { get; private set; }
    public double Threshold { get { return Math.Max(noiseFloor * 3, MinThreshold); } }

    // silenceMs: pause after speech that ends the session; noSpeechMs: give up if nothing is said at all
    public SilenceWatcher(int silenceMs, int noSpeechMs)
    {
        this.silenceMs = silenceMs;
        this.noSpeechMs = noSpeechMs;
        poll.Tick += Poll;
    }

    public bool Start()
    {
        var fmt = new WAVEFORMATEX
        {
            wFormatTag = 1, nChannels = 1, nSamplesPerSec = Rate, nAvgBytesPerSec = Rate * 2, nBlockAlign = 2, wBitsPerSample = 16,
        };
        if (waveInOpen(out wave, WAVE_MAPPER, ref fmt, IntPtr.Zero, IntPtr.Zero, 0) != 0) { wave = IntPtr.Zero; return false; }

        for (int i = 0; i < BufferCount; i++)
        {
            var hdr = new WAVEHDR { lpData = Marshal.AllocHGlobal(BlockBytes), dwBufferLength = BlockBytes };
            headers[i] = Marshal.AllocHGlobal(HdrSize);
            Marshal.StructureToPtr(hdr, headers[i], false);
            waveInPrepareHeader(wave, headers[i], HdrSize);
            waveInAddBuffer(wave, headers[i], HdrSize);
        }
        waveInStart(wave);
        poll.Start();
        return true;
    }

    void Poll(object sender, EventArgs e)
    {
        bool quiet = false;
        foreach (var h in headers)
        {
            if ((Marshal.ReadInt32(h, FlagsOffset) & WHDR_DONE) == 0) continue;
            int count = Marshal.ReadInt32(h, RecordedOffset) / 2;
            Marshal.Copy(Marshal.ReadIntPtr(h), samples, 0, count);
            quiet |= Analyze(count);
            waveInAddBuffer(wave, h, HdrSize);
        }
        // Raised after the loop: the handler usually disposes us
        if (quiet && Quiet != null) Quiet();
    }

    bool Analyze(int count)
    {
        if (count == 0) return false;
        double sum = 0;
        for (int i = 0; i < count; i++) sum += (double)samples[i] * samples[i];
        double rms = Math.Sqrt(sum / count);
        int ms = count * 1000 / Rate;
        LastLevel = rms;
        totalMs += ms;

        // Noise floor follows the quietest moments and creeps up (2% per block), so it adapts to a noisy room.
        // It starts low in case the user is already talking when recording begins.
        noiseFloor = noiseFloor < 0 ? Math.Min(rms, MinThreshold / 3) : Math.Min(noiseFloor * 1.02, rms);

        if (rms > Threshold)
        {
            loudRunMs += ms;
            if (loudRunMs >= SpeechRunMs) { spoke = true; quietMs = 0; }
        }
        else { loudRunMs = 0; quietMs += ms; }

        if (totalMs >= MaxSessionMs) return true;
        return spoke ? quietMs >= silenceMs : totalMs >= noSpeechMs;
    }

    public void Dispose()
    {
        poll.Stop();
        poll.Dispose();
        if (wave == IntPtr.Zero) return;
        waveInReset(wave);
        foreach (var h in headers)
        {
            if (h == IntPtr.Zero) continue;
            waveInUnprepareHeader(wave, h, HdrSize);
            Marshal.FreeHGlobal(Marshal.ReadIntPtr(h));
            Marshal.FreeHGlobal(h);
        }
        waveInClose(wave);
        wave = IntPtr.Zero;
    }
}
