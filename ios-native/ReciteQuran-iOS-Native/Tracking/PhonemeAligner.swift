import Foundation

enum AlignerEvent: Sendable {
    case highlight(wordID: Int, isRed: Bool, wordASR: String, timestamps: [Double])
    case uncertain(wordID: Int)
    case waiting(wordID: Int, expected: String, heard: String, enoughAudio: Bool)
    case ayahCompleted(wordsASR: [String], timestamps: [[Double]], preserveCarryover: Bool)
}

actor PhonemeAligner {
    private var words: [String] = []
    private var currentWord = 0
    private var buffer = ""
    private var bufferDurations: [Double] = []
    private var accepted: [String] = []
    private var acceptedTimestamps: [[Double]] = []
    private var continuationWords: [String] = []
    private var completionEmitted = false
    private var completionPreservesCarryover = false
    private var recoveryBypassUsed = false
    private var isTajweed = false
    private var verseLabel = "unset"

    func setVerse(_ phonemeWords: [String], tajweed: Bool, forceClear: Bool = true,
                  startingWord: Int = 0, label: String = "test",
                  continuationWords: [String] = []) {
        let carriedBuffer = forceClear ? "" : buffer
        let carriedDurations = forceClear ? [] : bufferDurations
        words = phonemeWords.map { $0.replacingOccurrences(of: " ", with: "") }
        currentWord = min(max(0, startingWord), words.count)
        buffer = carriedBuffer; bufferDurations = carriedDurations
        isTajweed = tajweed; verseLabel = label
        self.continuationWords = continuationWords.map { $0.replacingOccurrences(of: " ", with: "") }
        completionEmitted = false
        completionPreservesCarryover = false
        recoveryBypassUsed = false
        accepted = Array(repeating: "", count: words.count)
        acceptedTimestamps = Array(repeating: [], count: words.count)
        for index in 0..<currentWord { accepted[index] = words[index] }
        RQLog.write("ALIGN", "set verse=\(label) words=\(words.count) startWord=\(currentWord) forceClear=\(forceClear) carriedScalars=\(buffer.unicodeScalars.count) continuationWords=\(self.continuationWords.count)")
    }

    func feed(_ value: String, timestamps: [Double] = [], isFinal: Bool = false) -> [AlignerEvent] {
        buffer += value
        let addedCount = value.unicodeScalars.count
        bufferDurations += timestamps.prefix(addedCount)
        if timestamps.count < addedCount { bufferDurations += Array(repeating: .nan, count: addedCount - timestamps.count) }
        if buffer.unicodeScalars.count > 8_000 {
            let excess = buffer.unicodeScalars.count - 8_000
            buffer = String(String.UnicodeScalarView(buffer.unicodeScalars.dropFirst(excess)))
            if bufferDurations.count >= excess { bufferDurations.removeFirst(excess) }
        }
        if !value.isEmpty || isFinal {
            RQLog.write("ALIGN", "feed verse=\(verseLabel) added=\(addedCount) buffered=\(buffer.unicodeScalars.count) currentWord=\(currentWord) final=\(isFinal) text=\(RQLog.preview(value))")
        }
        var events: [AlignerEvent] = []
        var chunks = QuranNormalizer.chunkPhonemes(buffer)
        while currentWord < words.count, !chunks.isEmpty {
            // Tajweed also needs guarded lookahead so one damaged model word
            // cannot stall the rest of a continuous recitation. The strict
            // tail anchor and next-word proof below still prevent an early
            // partial from jumping the cursor forward.
            // Word zero anchors every new ayah. Recovery may bypass at most one
            // later word in the entire ayah; it must never cascade through
            // several words from stale or duplicated recognizer text.
            let lookahead = currentWord == 0 || recoveryBypassUsed ? 0 : 1
            var match: (word: Int, start: Int, used: Int, similarity: Double,
                        score: Double, continuationProved: Bool)?
            for wordIndex in currentWord...min(words.count - 1, currentWord + lookahead) {
                let ref = QuranNormalizer.chunkPhonemes(words[wordIndex]).compactMap { $0.unicodeScalars.first }
                guard !ref.isEmpty else { continue }
                let minimum = ref.count <= 3 || wordIndex == 0 ? 0.60 : 0.70
                let minimumWindow = max(1, ref.count - 2)
                guard chunks.count >= minimumWindow else { continue }

                // Slide across every possible buffer start. A partially committed
                // previous word can leave trailing chunks before the next word
                // (for example `مدُ` before `لِللَااهِ`). Those chunks are noise
                // for the current target and must not permanently block tracking.
                for start in 0...max(0, chunks.count - minimumWindow) {
                    let available = chunks.count - start
                    let maximumWindow = min(available, ref.count + 3)
                    guard maximumWindow >= minimumWindow else { continue }
                    for used in minimumWindow...maximumWindow {
                        let pred = Array(chunks[start..<(start + used)]).compactMap { $0.unicodeScalars.first }
                        let metrics = Self.alignmentMetrics(ref, pred)
                        let similarity = metrics.similarity
                        let priorPenalty = min(0.15, Double(start) * 0.02)
                        let score = similarity - priorPenalty
                        // Flutter's Tajweed tracker does not commit a word until
                        // the word's final expected phoneme is aligned as equal.
                        // This is especially important for the last word of an
                        // ayah, where there is no following word to prove that the
                        // recognizer has finished (for example the final meem in
                        // `الرَّحِيمِ` or noon in `الْعَالَمِينَ`).
                        if isTajweed, !metrics.tailMatched { continue }
                        if isTajweed, wordIndex + 1 < words.count,
                           let nextFirst = QuranNormalizer.chunkPhonemes(words[wordIndex + 1]).first?.unicodeScalars.first {
                            let provesNextWord = chunks.dropFirst(start + used).contains { chunk in
                                chunk.unicodeScalars.first.map { Self.equal($0, nextFirst) } == true
                            }
                            if !provesNextWord { continue }
                        }
                        // A partial recognizer hypothesis is still allowed to
                        // rewrite its ending. Never let it complete an ayah
                        // unless the ASR endpoint is final, or following audio
                        // proves that recitation has continued into the next
                        // ayah. This keeps the final hypothesis owned by the
                        // ayah that produced it.
                        var continuationProved = !isTajweed && wordIndex == words.count - 1 && !isFinal
                        if isTajweed, wordIndex == words.count - 1, !isFinal {
                            let remaining = chunks.dropFirst(start + used)
                            if !provesAyahContinuation(remaining) { continue }
                            continuationProved = true
                        }
                        if similarity >= minimum,
                           match == nil || score > match!.score {
                            match = (wordIndex, start, used, similarity, score, continuationProved)
                        }
                    }
                }
            }
            guard let match else {
                let expectedChunks = QuranNormalizer.chunkPhonemes(words[currentWord]).count
                RQLog.block("ALIGNMENT", "Waiting at \(verseLabel) word[\(currentWord)]", rows: [
                    ("reference", PhoneticDisplay.diagnostic(words[currentWord])),
                    ("model buffer", PhoneticDisplay.diagnostic(buffer)),
                    ("chunk counts", "reference=\(expectedChunks) model=\(chunks.count)"),
                    ("mode", isTajweed ? "Tajweed: guarded two-word recovery + final/next anchors" : "Reading: two-word lookahead allowed")
                ], verdict: isTajweed && currentWord == words.count - 1 && chunks.count >= expectedChunks && !isFinal
                    ? "CODE HOLD — final ayah word awaits a final ASR endpoint or proven next-ayah continuation"
                    : chunks.count >= expectedChunks
                    ? "CODE ALIGNMENT has enough audio but no acceptable ordered match yet"
                    : "MODEL has not emitted enough phoneme chunks yet")
                events.append(.waiting(wordID: currentWord, expected: words[currentWord],
                                       heard: buffer,
                                       enoughAudio: chunks.count >= expectedChunks))
                break
            }
            if match.word > currentWord, match.word + 1 < words.count {
                let nextFirst = QuranNormalizer.chunkPhonemes(words[match.word + 1]).first?.unicodeScalars.first
                guard nextFirst == nil || chunks.dropFirst(match.start + match.used).contains(where: { $0.unicodeScalars.first == nextFirst }) else { break }
            }
            if match.word > currentWord { recoveryBypassUsed = true }
            for skipped in currentWord..<match.word {
                if isTajweed {
                    events.append(.uncertain(wordID: skipped))
                    RQLog.write("RECOVERY", "bypassed \(verseLabel) word[\(skipped)] as ungraded recognition uncertainty")
                } else {
                    events.append(.highlight(wordID: skipped, isRed: true, wordASR: "", timestamps: []))
                }
            }
            let spokenChunks = Array(chunks[match.start..<(match.start + match.used)])
            let spoken = spokenChunks.joined()
            let skippedScalarCount = chunks.prefix(match.start).joined().unicodeScalars.count
            let spokenScalarCount = spoken.unicodeScalars.count
            let spokenDurations = Array(bufferDurations.dropFirst(skippedScalarCount).prefix(spokenScalarCount))
            let consumedChunkCount = match.start + match.used
            let consumedScalarCount = chunks.prefix(consumedChunkCount).joined().unicodeScalars.count
            accepted[match.word] = spoken
            acceptedTimestamps[match.word] = spokenDurations
            events.append(.highlight(wordID: match.word, isRed: false, wordASR: spoken, timestamps: spokenDurations))
            RQLog.block("ALIGNMENT", "Committed \(verseLabel) word[\(match.word)]", rows: [
                ("reference", PhoneticDisplay.diagnostic(words[match.word])),
                ("model aligned", PhoneticDisplay.diagnostic(spoken)),
                ("similarity", "\(String(format: "%.3f", match.similarity)) score=\(String(format: "%.3f", match.score))"),
                ("window", "noiseBefore=\(match.start) chunks used=\(match.used)"),
                ("timestamps", RQLog.durationSummary(spokenDurations))
            ], verdict: match.word == currentWord
                ? "CODE MATCH — this model segment is now assigned to the expected word"
                : "CODE SKIP — earlier expected words will be marked missing")
            chunks.removeFirst(consumedChunkCount)
            buffer = chunks.joined()
            if bufferDurations.count >= consumedScalarCount { bufferDurations.removeFirst(consumedScalarCount) }
            currentWord = match.word + 1
            if match.word == words.count - 1 {
                completionPreservesCarryover = match.continuationProved
            }
        }
        if currentWord == words.count, !words.isEmpty, !completionEmitted {
            completionEmitted = true
            RQLog.write("ALIGN", "ayah complete verse=\(verseLabel) preserveCarryover=\(completionPreservesCarryover) carryScalars=\(buffer.unicodeScalars.count) carry=\(RQLog.preview(buffer))")
            events.append(.ayahCompleted(wordsASR: accepted,
                                         timestamps: acceptedTimestamps,
                                         preserveCarryover: completionPreservesCarryover))
        }
        return events
    }

    func replaceTail(backtrack: Int, with newTail: String, timestamps: [Double],
                     isFinal: Bool = false) -> [AlignerEvent] {
        let scalars = Array(buffer.unicodeScalars)
        let removable = min(max(0, backtrack), scalars.count)
        buffer = String(String.UnicodeScalarView(scalars.dropLast(removable)))
        if removable > 0, bufferDurations.count >= removable { bufferDurations.removeLast(removable) }
        RQLog.write("ALIGN", "replace tail verse=\(verseLabel) requestedBacktrack=\(backtrack) localBacktrack=\(removable) newTail=\(RQLog.preview(newTail))")
        return feed(newTail, timestamps: timestamps, isFinal: isFinal)
    }

    private func provesAyahContinuation(_ remaining: ArraySlice<String>) -> Bool {
        guard let firstWord = continuationWords.first else { return false }
        let chunks = Array(remaining)
        let reference = QuranNormalizer.chunkPhonemes(firstWord).compactMap { $0.unicodeScalars.first }
        guard !reference.isEmpty else { return false }
        let minimum = reference.count <= 3 ? 0.60 : 0.70
        let minimumWindow = max(1, reference.count - 2)
        guard chunks.count >= minimumWindow else { return false }

        let maximumNoise = min(2, max(0, chunks.count - minimumWindow))
        for start in 0...maximumNoise {
            let available = chunks.count - start
            let maximumWindow = min(available, reference.count + 3)
            guard maximumWindow >= minimumWindow else { continue }
            for used in minimumWindow...maximumWindow {
                let predicted = Array(chunks[start..<(start + used)]).compactMap { $0.unicodeScalars.first }
                let metrics = Self.alignmentMetrics(reference, predicted)
                guard metrics.similarity >= minimum, metrics.tailMatched else { continue }

                if continuationWords.count > 1,
                   let secondFirst = QuranNormalizer.chunkPhonemes(continuationWords[1]).first?.unicodeScalars.first {
                    let provesSecondWord = chunks.dropFirst(start + used).contains { chunk in
                        chunk.unicodeScalars.first.map { Self.equal($0, secondFirst) } == true
                    }
                    guard provesSecondWord else { continue }
                }
                RQLog.write("ALIGN", "next-ayah continuation proved after \(verseLabel) using \(used) chunks of the following ayah")
                return true
            }
        }
        return false
    }

    func debugState() -> String {
        "verse=\(verseLabel) word=\(currentWord)/\(words.count) bufferScalars=\(buffer.unicodeScalars.count) buffer=\(RQLog.preview(buffer))"
    }

    private static let equivalentGroups = ["ذدضتط", "ظزذصسث", "جزش", "ءأإآاهعحغخ", "ةهت", "ۦي", "ۥو", "ںن۾م", "قكغ", "فبم"]
    private static func equal(_ lhs: Unicode.Scalar, _ rhs: Unicode.Scalar) -> Bool {
        lhs == rhs || equivalentGroups.contains { $0.unicodeScalars.contains(lhs) && $0.unicodeScalars.contains(rhs) }
    }
    private struct AlignmentMetrics {
        let similarity: Double
        let tailMatched: Bool
    }

    private static func alignmentMetrics(_ reference: [Unicode.Scalar],
                                         _ predicted: [Unicode.Scalar]) -> AlignmentMetrics {
        guard !reference.isEmpty else {
            return .init(similarity: predicted.isEmpty ? 1 : 0, tailMatched: predicted.isEmpty)
        }
        var previous = Array(0...predicted.count)
        var matrix = [previous]
        for i in 1...reference.count {
            var current = Array(repeating: 0, count: predicted.count + 1); current[0] = i
            for j in 1...predicted.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1,
                                 previous[j - 1] + (equal(reference[i - 1], predicted[j - 1]) ? 0 : 1))
            }
            previous = current
            matrix.append(current)
        }

        // Backtrack the same optimal edit path used for the similarity score.
        // A tail anchor is valid only when the final reference chunk participates
        // in an exact diagonal match; merely seeing an equivalent sound elsewhere
        // in the buffer is not enough.
        var i = reference.count
        var j = predicted.count
        var tailMatched = false
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let cost = equal(reference[i - 1], predicted[j - 1]) ? 0 : 1
                if matrix[i][j] == matrix[i - 1][j - 1] + cost {
                    // The terminal anchor is deliberately stricter than the
                    // forgiving body matcher. In particular, ن and م are an
                    // acceptable zero-cost body pair, but a trailing م must not
                    // prove that the expected final ن of `العالمين` was spoken.
                    if i == reference.count,
                       reference[i - 1] == predicted[j - 1] { tailMatched = true }
                    i -= 1
                    j -= 1
                    continue
                }
            }
            if i > 0, matrix[i][j] == matrix[i - 1][j] + 1 {
                i -= 1
            } else if j > 0 {
                j -= 1
            }
        }

        let distance = previous.last ?? reference.count
        return .init(similarity: 1 - Double(distance) / Double(max(1, reference.count)),
                     tailMatched: tailMatched)
    }
}
