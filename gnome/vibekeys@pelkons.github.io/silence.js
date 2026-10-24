// Listens to the default microphone and calls onQuiet once the speaker has stopped talking.
// Same rules as the Windows and macOS versions. Audio comes from `parec` (PulseAudio / PipeWire)
// or `pw-record`, read as raw 16-bit mono samples; nothing is stored.

import GLib from 'gi://GLib';
import Gio from 'gi://Gio';

const RATE = 16000;
const MIN_THRESHOLD = 250;            // RMS of 16-bit samples; quiet rooms sit well below this
const SPEECH_RUN_MS = 250;            // loud audio this long without a break counts as speech; shorter
                                      // bursts (clicks, a knock) neither count nor end the pause
const MAX_SESSION_MS = 5 * 60 * 1000; // safety cap

const RECORDERS = [
    ['parec', '--raw', '--format=s16le', `--rate=${RATE}`, '--channels=1', '--latency-msec=100'],
    ['pw-record', '--rate', `${RATE}`, '--channels', '1', '--format', 's16', '-'],
];

export class SilenceWatcher {
    // silenceMs: pause after speech that ends the session; noSpeechMs: give up if nothing is said
    constructor(silenceMs, noSpeechMs, onQuiet) {
        this._silenceMs = silenceMs;
        this._noSpeechMs = noSpeechMs;
        this._onQuiet = onQuiet;
        this._noiseFloor = -1;
        this._loudRunMs = 0;
        this._quietMs = 0;
        this._totalMs = 0;
        this._spoke = false;
        this._finished = false;
        this._carry = null;
        this._first = true;
    }

    start() {
        for (const argv of RECORDERS) {
            if (!GLib.find_program_in_path(argv[0]))
                continue;
            try {
                this._proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
                break;
            } catch (e) {
                logError(e, 'VibeKeys: could not start recorder');
            }
        }
        if (!this._proc)
            return false;
        this._cancellable = new Gio.Cancellable();
        this._stream = this._proc.get_stdout_pipe();
        this._read();
        return true;
    }

    stop() {
        this._finished = true;
        this._cancellable?.cancel();
        this._proc?.force_exit();
        this._proc = null;
    }

    _read() {
        this._stream.read_bytes_async(RATE / 10 * 2, GLib.PRIORITY_DEFAULT, this._cancellable, (stream, result) => {
            let bytes;
            try {
                bytes = stream.read_bytes_finish(result);
            } catch (e) {
                return;   // cancelled or the recorder died
            }
            if (this._finished || !bytes || bytes.get_size() === 0)
                return;
            this._analyze(bytes.toArray());
            if (!this._finished)
                this._read();
        });
    }

    _analyze(chunk) {
        let data = chunk;
        if (this._first) {
            this._first = false;
            // pw-record writes a WAV header to stdout; skip it
            if (data.length >= 44 && data[0] === 0x52 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x46)
                data = data.slice(44);
        }
        if (this._carry) {
            const joined = new Uint8Array(this._carry.length + data.length);
            joined.set(this._carry);
            joined.set(data, this._carry.length);
            data = joined;
            this._carry = null;
        }
        const count = Math.floor(data.length / 2);
        if (data.length % 2)
            this._carry = data.slice(data.length - 1);
        if (count === 0)
            return;

        const view = new DataView(data.buffer, data.byteOffset, count * 2);
        let sum = 0;
        for (let i = 0; i < count; i++) {
            const v = view.getInt16(i * 2, true);
            sum += v * v;
        }
        const rms = Math.sqrt(sum / count);
        const ms = Math.round(count * 1000 / RATE);
        this._totalMs += ms;

        // Noise floor follows the quietest moments and creeps up 2% per block, so it adapts to a noisy room.
        // It starts low in case the user is already talking when recording begins.
        this._noiseFloor = this._noiseFloor < 0 ? Math.min(rms, MIN_THRESHOLD / 3) : Math.min(this._noiseFloor * 1.02, rms);
        const threshold = Math.max(this._noiseFloor * 3, MIN_THRESHOLD);

        if (rms > threshold) {
            this._loudRunMs += ms;
            if (this._loudRunMs >= SPEECH_RUN_MS) {
                this._spoke = true;
                this._quietMs = 0;
            }
        } else {
            this._loudRunMs = 0;
            this._quietMs += ms;
        }

        const done = this._totalMs >= MAX_SESSION_MS ||
            (this._spoke ? this._quietMs >= this._silenceMs : this._totalMs >= this._noSpeechMs);
        if (done) {
            this.stop();
            this._onQuiet();
        }
    }
}
