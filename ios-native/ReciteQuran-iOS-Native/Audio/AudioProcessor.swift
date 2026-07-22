@preconcurrency import AVFoundation
import Foundation

enum AudioEvent: Sendable { case samples([Float]), endpoint }

@MainActor
final class AudioProcessor {
    static let sampleRate = 16_000
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var fifo: [Float] = []
    private var vad: SherpaOnnxVoiceActivityDetectorWrapper?
    private var speechDetected = false
    private var silenceMilliseconds = 0
    private var preRoll: [[Float]] = []
    private var continuation: AsyncStream<AudioEvent>.Continuation?
    private(set) var isRunning = false

    func initializeVAD() throws {
        guard vad == nil else { return }
        let model = try BundleResources.requiredURL("silero_vad", extension: "onnx").path
        let silero = sherpaOnnxSileroVadModelConfig(
            model: model, threshold: 0.1, minSilenceDuration: 0.1,
            minSpeechDuration: 0.15, windowSize: 512, maxSpeechDuration: 1_000
        )
        var config = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: 16_000,
                                               numThreads: 1, provider: "cpu")
        vad = withUnsafePointer(to: &config) {
            SherpaOnnxVoiceActivityDetectorWrapper(config: $0, buffer_size_in_seconds: 10)
        }
    }

    func start() async throws -> AsyncStream<AudioEvent> {
        guard !isRunning else { throw AudioError.alreadyRunning }
        let permitted = await AVAudioApplication.requestRecordPermission()
        guard permitted else { throw AudioError.permissionDenied }
        try await AudioSessionConfigurator.configure()
        try initializeVAD()
        resetState()
        let channel = AsyncStream<AudioEvent>.makeStream()
        continuation = channel.continuation
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: 16_000, channels: 1,
                                               interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            channel.continuation.finish()
            continuation = nil
            throw AudioError.converterUnavailable
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / inputFormat.sampleRate)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, let channel = output.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            Task { @MainActor [weak self] in self?.ingest(samples) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            converter.reset()
            self.converter = nil
            channel.continuation.finish()
            continuation = nil
            throw error
        }
        isRunning = true
        RQLog.write("AUDIO", "AVAudioEngine running inputRate=\(Int(inputFormat.sampleRate)) outputRate=16000")
        return channel.stream
    }

    func stop(finalize: Bool = true) {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isRunning = false
        if finalize, speechDetected { continuation?.yield(.endpoint) }
        continuation?.finish()
        continuation = nil
        resetState()
        RQLog.write("AUDIO", "AVAudioEngine stopped finalize=\(finalize)")
    }

    func resetForNavigation() {
        resetState()
        converter?.reset()
        RQLog.write("AUDIO", "navigation reset cleared FIFO, VAD, silence, and pre-roll state")
    }

    private func resetState() {
        fifo.removeAll(keepingCapacity: true); vad?.reset(); speechDetected = false
        silenceMilliseconds = 0; preRoll.removeAll(keepingCapacity: true)
    }

    private func ingest(_ samples: [Float]) {
        fifo.append(contentsOf: samples)
        let chunkCount = 5_120
        while fifo.count >= chunkCount {
            let chunk = Array(fifo.prefix(chunkCount)); fifo.removeFirst(chunkCount)
            vad?.acceptWaveform(samples: chunk)
            let detected = vad?.isSpeechDetected() ?? true
            if detected {
                silenceMilliseconds = 0
                if !speechDetected {
                    speechDetected = true
                    RQLog.write("AUDIO", "VAD speech detected; flushing \(preRoll.count) pre-roll chunks")
                    preRoll.forEach { continuation?.yield(.samples($0)) }
                    preRoll.removeAll(keepingCapacity: true)
                }
                continuation?.yield(.samples(chunk))
            } else if speechDetected {
                silenceMilliseconds += 320
                if silenceMilliseconds >= 2_500 {
                    RQLog.write("AUDIO", "VAD silence reached \(silenceMilliseconds)ms; emitting endpoint")
                    continuation?.yield(.endpoint); speechDetected = false; silenceMilliseconds = 0
                } else { continuation?.yield(.samples(chunk)) }
            } else {
                preRoll.append(chunk)
                if preRoll.count > 2 { preRoll.removeFirst() }
            }
        }
    }

    enum AudioError: LocalizedError {
        case permissionDenied, converterUnavailable, alreadyRunning
        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Microphone permission was denied."
            case .converterUnavailable: "The microphone audio format could not be converted."
            case .alreadyRunning: "Recording is already running."
            }
        }
    }
}
