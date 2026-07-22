import Foundation

struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let isFinal: Bool
    let submitTimeMs: Int64
    let tokens: [String]
    let timestamps: [Float]

    init(text: String, isFinal: Bool = false, submitTimeMs: Int64 = 0,
         tokens: [String] = [], timestamps: [Float] = []) {
        self.text = text
        self.isFinal = isFinal
        self.submitTimeMs = submitTimeMs
        self.tokens = tokens
        self.timestamps = timestamps
    }
}
