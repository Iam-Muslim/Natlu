import Foundation

struct AnchorResult: Sendable, Hashable { let surah: Int, ayah: Int }

enum VoiceSearchAssessment: Sendable, Equatable {
    case needsMoreAudio
    case noExactMatch
    case ambiguous(uniqueAyahs: Int)
    case confirming(AnchorResult)
    case unique(AnchorResult)
}

actor VoiceSearchController {
    private struct IndexedAyah: Sendable {
        let anchor: AnchorResult
        let words: [[UInt16]]
        let displayWords: [String]
    }

    private struct OrderedScore: Sendable, Equatable {
        var matchedWords: Int
        var coveredPhonemes: Int

        func isBetter(than other: OrderedScore) -> Bool {
            matchedWords != other.matchedWords
                ? matchedWords > other.matchedWords
                : coveredPhonemes > other.coveredPhonemes
        }
    }

    private struct OrderedSummary: Sendable {
        let score: OrderedScore
        let anchors: [AnchorResult]
        let heardWords: [String]
    }

    private struct OrderedPath: Sendable {
        let score: OrderedScore
        let wordIndices: [Int]
    }

    private static let minimumWordQueryLength = 2
    private static let minimumFuzzyQueryLength = 8
    private static let maximumErrorRatio = 0.30
    private static let minimumDistanceLead = 2
    private static let requiredConfirmations = 2

    private let search = PhoneticSearch()
    private var loaded = false
    private var lastEvaluatedQuery = ""
    private var lastAssessment: VoiceSearchAssessment = .needsMoreAudio
    private var pendingAnchor: AnchorResult?
    private var pendingConfirmations = 0
    private var indexedAyahs: [IndexedAyah] = []
    private var lastHeardWords: [String] = []

    func configure(verses: [QuranVerse]) {
        indexedAyahs = verses.map { verse in
            IndexedAyah(
                anchor: AnchorResult(surah: verse.surah, ayah: verse.ayah),
                words: verse.phonemeWords.map {
                    Array(PhoneticSearch.normalizedQuery($0).utf16)
                },
                displayWords: verse.phonemeWords.indices.map { index in
                    if verse.readableWords.indices.contains(index) {
                        return verse.readableWords[index]
                    }
                    if verse.uthmaniWords.indices.contains(index) {
                        return verse.uthmaniWords[index]
                    }
                    return ""
                }
            )
        }
        RQLog.write("VOICE-SEARCH", "ordered word index ready ayahs=\(indexedAyahs.count)")
    }

    func preload() async throws { try await search.load(); loaded = true }

    func startSession() async throws {
        if !loaded { try await preload() }
        lastEvaluatedQuery = ""
        lastAssessment = .needsMoreAudio
        pendingAnchor = nil
        pendingConfirmations = 0
        lastHeardWords = []
    }

    func heardWords() -> [String] { lastHeardWords }

    /// Recognition is intentionally forgiving because the phoneme model can
    /// omit or substitute sounds even during a correct recitation. Navigation
    /// still requires one clearly leading ayah to win on two changed ASR
    /// hypotheses, so tolerance does not turn a single noisy result into a jump.
    func assess(_ text: String, isFinal: Bool = false) async throws -> VoiceSearchAssessment {
        if !loaded { try await preload() }
        let normalized = PhoneticSearch.normalizedQuery(text)
        let isRepeatedQuery = normalized == lastEvaluatedQuery
        if isRepeatedQuery {
            // The final endpoint is independent confirmation that the model kept
            // the same short phrase. Re-evaluate it only when a candidate is
            // already waiting; ordinary duplicate partials remain ignored.
            guard isFinal, case .confirming = lastAssessment else { return lastAssessment }
        } else {
            lastEvaluatedQuery = normalized
        }
        let query = Array(normalized.utf16)
        guard query.count >= Self.minimumWordQueryLength else {
            lastAssessment = .needsMoreAudio
            RQLog.write(
                "VOICE-SEARCH",
                "collecting phonemes queryLength=\(query.count)/\(Self.minimumWordQueryLength) final=\(isFinal)"
            )
            return lastAssessment
        }

        let orderedSummary = orderedWordSummary(for: query)
        if let orderedSummary {
            lastHeardWords = orderedSummary.heardWords
            let destinations = orderedSummary.anchors.prefix(8)
                .map { "\($0.surah):\($0.ayah)" }.joined(separator: ", ")
            RQLog.block("VOICE-SEARCH", "Ordered word candidate filter", rows: [
                ("normalized model output", RQLog.preview(normalized, limit: 120)),
                ("matched Quran words", "\(orderedSummary.score.matchedWords)"),
                ("covered phonemes", "\(orderedSummary.score.coveredPhonemes)/\(query.count)"),
                ("remaining ayahs", "\(orderedSummary.anchors.count)"),
                ("candidate sample", destinations.isEmpty ? "none" : destinations)
            ], verdict: orderedSummary.anchors.count == 1
                ? "ONE ORDERED-WORD CANDIDATE — awaiting confirmation"
                : "KEEP LISTENING — every listed ayah still contains the heard words in order")

            let enoughWordEvidence = orderedSummary.score.matchedWords >= 2 ||
                orderedSummary.score.coveredPhonemes >= 5
            if enoughWordEvidence, orderedSummary.anchors.count == 1,
               let anchor = orderedSummary.anchors.first {
                return confirm(
                    anchor,
                    method: "ordered Quran words with omissions allowed",
                    evidence: [
                        ("matched Quran words", "\(orderedSummary.score.matchedWords)"),
                        ("covered phonemes", "\(orderedSummary.score.coveredPhonemes)/\(query.count)"),
                        ("remaining ayahs", "1")
                    ],
                    isFinal: isFinal
                )
            }
        }

        guard query.count >= Self.minimumFuzzyQueryLength else {
            resetPendingConfirmation()
            if let orderedSummary, orderedSummary.anchors.count > 1 {
                lastAssessment = .ambiguous(uniqueAyahs: orderedSummary.anchors.count)
            } else {
                lastAssessment = .needsMoreAudio
            }
            return lastAssessment
        }

        let containedResults = try await search.search(
            normalized,
            errorRatio: Self.maximumErrorRatio
        ).filter {
            $0.start.surah == $0.end.surah &&
                $0.start.ayah == $0.end.ayah
        }
        let resultsByAyah = Dictionary(grouping: containedResults) {
            AnchorResult(surah: $0.start.surah, ayah: $0.start.ayah)
        }
        let ranked = resultsByAyah.map { anchor, results in
            (anchor: anchor, distance: results.map(\.distance).min() ?? Int.max)
        }.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.anchor.surah != $1.anchor.surah { return $0.anchor.surah < $1.anchor.surah }
            return $0.anchor.ayah < $1.anchor.ayah
        }

        guard let best = ranked.first else {
            resetPendingConfirmation()
            if let orderedSummary, orderedSummary.anchors.count > 1 {
                lastAssessment = .ambiguous(uniqueAyahs: orderedSummary.anchors.count)
                return lastAssessment
            }
            RQLog.write(
                "VOICE-SEARCH",
                "no fuzzy whole-ayah-contained match queryLength=\(normalized.utf16.count) tolerance=30%"
            )
            lastAssessment = .noExactMatch
            return lastAssessment
        }

        let runnerUp = ranked.dropFirst().first
        let distanceLead = runnerUp.map { $0.distance - best.distance } ?? Int.max
        guard distanceLead >= Self.minimumDistanceLead else {
            resetPendingConfirmation()
            RQLog.write(
                "VOICE-SEARCH",
                "ambiguous fuzzy result best=\(best.anchor.surah):\(best.anchor.ayah) distance=\(best.distance) " +
                    "runnerUpDistance=\(runnerUp?.distance ?? -1) candidates=\(ranked.count)"
            )
            lastAssessment = .ambiguous(uniqueAyahs: ranked.count)
            return lastAssessment
        }

        let errorRatio = Double(best.distance) / Double(normalized.utf16.count)
        return confirm(
            best.anchor,
            method: "30% fuzzy continuous-phoneme fallback",
            evidence: [
                ("actual difference", "\(best.distance) edit(s), \(Int((errorRatio * 100).rounded()))%"),
                ("lead over runner-up", runnerUp.map { _ in "\(distanceLead) edit(s)" } ?? "no runner-up")
            ],
            isFinal: isFinal
        )
    }

    private func orderedWordSummary(for query: [UInt16]) -> OrderedSummary? {
        guard !indexedAyahs.isEmpty else { return nil }
        var bestScore = OrderedScore(matchedWords: 0, coveredPhonemes: 0)
        var bestAnchors: [AnchorResult] = []

        for ayah in indexedAyahs {
            let score = orderedScore(query: query, words: ayah.words)
            guard score.matchedWords > 0 else { continue }
            if score.isBetter(than: bestScore) {
                bestScore = score
                bestAnchors = [ayah.anchor]
            } else if score == bestScore {
                bestAnchors.append(ayah.anchor)
            }
        }
        guard !bestAnchors.isEmpty,
              let representative = indexedAyahs.first(where: { $0.anchor == bestAnchors[0] }) else {
            return nil
        }
        let path = orderedPath(query: query, words: representative.words)
        let heardWords: [String] = path.wordIndices.compactMap { index -> String? in
            guard representative.displayWords.indices.contains(index) else { return nil }
            let word = representative.displayWords[index]
            return word.isEmpty ? nil : word
        }
        return OrderedSummary(score: bestScore, anchors: bestAnchors, heardWords: heardWords)
    }

    /// Finds the strongest sequence of complete Quran words inside the model
    /// output. Quran words may be skipped at zero cost and unmatched model
    /// phonemes may sit between anchors, but matched words cannot change order.
    private func orderedScore(query: [UInt16], words: [[UInt16]]) -> OrderedScore {
        let zero = OrderedScore(matchedWords: 0, coveredPhonemes: 0)
        var states: [Int: OrderedScore] = [0: zero]

        for word in words where word.count >= Self.minimumWordQueryLength {
            var next = states // Skipping this Quran word is always allowed.
            for (cursor, score) in states {
                for start in occurrenceStarts(of: word, in: query, from: cursor) {
                    let end = start + word.count
                    let candidate = OrderedScore(
                        matchedWords: score.matchedWords + 1,
                        coveredPhonemes: score.coveredPhonemes + word.count
                    )
                    if let existing = next[end] {
                        if candidate.isBetter(than: existing) { next[end] = candidate }
                    } else {
                        next[end] = candidate
                    }
                }
            }
            states = next
        }
        return states.values.reduce(zero) { best, candidate in
            candidate.isBetter(than: best) ? candidate : best
        }
    }

    private func orderedPath(query: [UInt16], words: [[UInt16]]) -> OrderedPath {
        let zeroScore = OrderedScore(matchedWords: 0, coveredPhonemes: 0)
        var states: [Int: OrderedPath] = [0: OrderedPath(score: zeroScore, wordIndices: [])]

        for (wordIndex, word) in words.enumerated()
        where word.count >= Self.minimumWordQueryLength {
            var next = states
            for (cursor, path) in states {
                for start in occurrenceStarts(of: word, in: query, from: cursor) {
                    let end = start + word.count
                    let candidate = OrderedPath(
                        score: OrderedScore(
                            matchedWords: path.score.matchedWords + 1,
                            coveredPhonemes: path.score.coveredPhonemes + word.count
                        ),
                        wordIndices: path.wordIndices + [wordIndex]
                    )
                    if let existing = next[end] {
                        if candidate.score.isBetter(than: existing.score) { next[end] = candidate }
                    } else {
                        next[end] = candidate
                    }
                }
            }
            states = next
        }

        return states.values.reduce(OrderedPath(score: zeroScore, wordIndices: [])) { best, candidate in
            candidate.score.isBetter(than: best.score) ? candidate : best
        }
    }

    private func occurrenceStarts(of needle: [UInt16], in haystack: [UInt16], from cursor: Int) -> [Int] {
        guard !needle.isEmpty, cursor <= haystack.count,
              needle.count <= haystack.count - cursor else { return [] }
        let lastStart = haystack.count - needle.count
        return (cursor...lastStart).filter { start in
            haystack[start..<(start + needle.count)].elementsEqual(needle)
        }
    }

    private func confirm(
        _ anchor: AnchorResult,
        method: String,
        evidence: [(String, String)],
        isFinal: Bool
    ) -> VoiceSearchAssessment {
        if pendingAnchor == anchor {
            pendingConfirmations += 1
        } else {
            pendingAnchor = anchor
            pendingConfirmations = 1
        }

        let rows = evidence + [
            ("method", method),
            ("destination", "Surah \(anchor.surah), Ayah \(anchor.ayah)"),
            ("confirmation", "\(pendingConfirmations)/\(Self.requiredConfirmations) final=\(isFinal)")
        ]
        guard pendingConfirmations >= Self.requiredConfirmations else {
            RQLog.block(
                "VOICE-SEARCH",
                "Possible ayah awaiting confirmation",
                rows: rows,
                verdict: "KEEP LISTENING — the same single ayah must win again"
            )
            lastAssessment = .confirming(anchor)
            return lastAssessment
        }

        RQLog.block(
            "VOICE-SEARCH",
            "Voice-search match confirmed",
            rows: rows,
            verdict: "SAFE NAVIGATION — one ayah survived the filter twice"
        )
        lastAssessment = .unique(anchor)
        return lastAssessment
    }

    private func resetPendingConfirmation() {
        pendingAnchor = nil
        pendingConfirmations = 0
    }
}
