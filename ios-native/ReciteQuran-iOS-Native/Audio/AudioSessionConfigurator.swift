@preconcurrency import AVFoundation

enum AudioSessionConfigurator {
    static func configure() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setPreferredSampleRate(16_000)
            try session.setActive(true)
        }.value
    }
}
