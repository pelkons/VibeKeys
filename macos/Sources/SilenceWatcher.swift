// Listens to the default microphone and calls onQuiet once the speaker has stopped talking.
// Same rules as the Windows version: a pause after speech ends the session, so does saying nothing.

import AVFoundation

final class SilenceWatcher {
    private static let minThreshold = 250.0        // RMS on the 16-bit scale; quiet rooms sit well below this
    private static let speechRunMs = 250           // loud audio this long without a break counts as speech;
                                                   // shorter bursts (clicks, a knock) neither count nor end the pause
    private static let maxSessionMs = 5 * 60 * 1000   // safety cap

    var onQuiet: (() -> Void)?

    private let silenceMs: Int, noSpeechMs: Int
    private let engine = AVAudioEngine()
    private var noiseFloor = -1.0
    private var loudRunMs = 0, quietMs = 0, totalMs = 0
    private var spoke = false, finished = false

    private var threshold: Double { max(noiseFloor * 3, Self.minThreshold) }

    /// silenceMs: pause after speech that ends the session; noSpeechMs: give up if nothing is said
    init(silenceMs: Int, noSpeechMs: Int) {
        self.silenceMs = silenceMs
        self.noSpeechMs = noSpeechMs
    }

    func start() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let rate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 1600, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum = 0.0
            for i in 0..<count {
                let value = Double(samples[i]) * 32768
                sum += value * value
            }
            let rms = (sum / Double(count)).squareRoot()
            let ms = Int(Double(count) * 1000 / rate)
            DispatchQueue.main.async { self?.analyze(rms: rms, ms: ms) }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
        return true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func analyze(rms: Double, ms: Int) {
        guard !finished else { return }
        totalMs += ms
        // Noise floor follows the quietest moments and creeps up 2% per block, so it adapts to a noisy room.
        // It starts low in case the user is already talking when recording begins.
        noiseFloor = noiseFloor < 0 ? min(rms, Self.minThreshold / 3) : min(noiseFloor * 1.02, rms)

        if rms > threshold {
            loudRunMs += ms
            if loudRunMs >= Self.speechRunMs { spoke = true; quietMs = 0 }
        } else {
            loudRunMs = 0
            quietMs += ms
        }

        let done = totalMs >= Self.maxSessionMs || (spoke ? quietMs >= silenceMs : totalMs >= noSpeechMs)
        if done {
            finished = true
            onQuiet?()
        }
    }
}
