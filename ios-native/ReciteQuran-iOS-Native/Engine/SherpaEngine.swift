import Foundation

actor SherpaEngine {
    private var recognizer: SherpaOnnxRecognizer?
    private var lastLoggedText = ""
    private var resultSequence = 0

    var isInitialized: Bool { recognizer != nil }

    func initialize() throws {
        guard recognizer == nil else { RQLog.write("ASR", "recognizer already initialized"); return }
        RQLog.write("ASR", "initializing Zipformer2-CTC recognizer")
        let model = try BundleResources.requiredURL("zipformer_p_arabic_v2.int8", extension: "onnx").path
        let tokens = try BundleResources.requiredURL("tokens", extension: "txt").path
        let zipformer = sherpaOnnxOnlineZipformer2CtcModelConfig(model: model)
        let modelConfig = sherpaOnnxOnlineModelConfig(
            tokens: tokens, zipformer2Ctc: zipformer, numThreads: 1,
            provider: "cpu", debug: 0, modelType: "zipformer2_ctc"
        )
        let feature = sherpaOnnxFeatureConfig(sampleRate: 16_000, featureDim: 80)
        var config = sherpaOnnxOnlineRecognizerConfig(
            featConfig: feature, modelConfig: modelConfig,
            enableEndpoint: false, rule1MinTrailingSilence: 2.4
        )
        recognizer = withUnsafePointer(to: &config) { SherpaOnnxRecognizer(config: $0) }
        recognizer?.acceptWaveform(samples: Array(repeating: 0, count: 4_800), sampleRate: 16_000)
        RQLog.write("ASR", "recognizer ready and primed with 4800 silence samples")
    }

    func transcribe(_ samples: [Float], isFinal: Bool = false) throws -> TranscriptionResult {
        if recognizer == nil { try initialize() }
        guard let recognizer else { throw EngineError.initializationFailed }
        let submitted = Int64(Date().timeIntervalSince1970 * 1_000)
        if !samples.isEmpty { recognizer.acceptWaveform(samples: samples, sampleRate: 16_000) }
        while recognizer.isReady() { recognizer.decode() }
        if isFinal {
            recognizer.inputFinished()
            while recognizer.isReady() { recognizer.decode() }
        }
        let output = recognizer.getResult()
        let result = TranscriptionResult(text: output.text, isFinal: isFinal,
                                         submitTimeMs: submitted, tokens: output.tokens,
                                         timestamps: output.timestamps)
        if output.text != lastLoggedText || isFinal {
            resultSequence += 1
            let latency = Int64(Date().timeIntervalSince1970 * 1_000) - submitted
            let tokenCount = min(output.tokens.count, output.timestamps.count)
            let timeline = (0..<tokenCount).prefix(24).map { index in
                let timestamp = String(format: "%.3fs", output.timestamps[index])
                return "token[\(index)]=\"\(output.tokens[index])\" spike=\(timestamp)"
            }
            RQLog.block("MODEL", "Raw recognizer result #\(resultSequence)", rows: [
                ("final", "\(isFinal)"),
                ("audio", "samples=\(samples.count) @16kHz latency=\(latency)ms"),
                ("model text", "\"\(RQLog.preview(output.text, limit: 140))\""),
                ("unicode", RQLog.codepoints(output.text)),
                ("tokens", "\(output.tokens.count), timestamps=\(output.timestamps.count)")
            ], details: timeline, verdict: "MODEL OUTPUT — everything below this point is app alignment/rule logic")
            lastLoggedText = output.text
        }
        if isFinal {
            recognizer.reset()
            recognizer.acceptWaveform(samples: Array(repeating: 0, count: 4_800), sampleRate: 16_000)
            lastLoggedText = ""
            RQLog.write("ASR", "endpoint finalized; recognizer reset and re-primed")
        }
        return result
    }

    func reset() {
        recognizer?.reset()
        recognizer?.acceptWaveform(samples: Array(repeating: 0, count: 4_800), sampleRate: 16_000)
        lastLoggedText = ""
        RQLog.write("ASR", "manual recognizer reset and re-prime")
    }

    enum EngineError: Error { case initializationFailed }
}
