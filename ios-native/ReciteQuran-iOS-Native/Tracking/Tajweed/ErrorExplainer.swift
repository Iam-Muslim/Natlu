import Foundation

enum ErrorCategory: String, Sendable { case tajweed, normal, tashkeel }
enum SpeechErrorType: String, Sendable { case insert, delete, replace }

struct ReciterError: Identifiable, Sendable, Equatable {
    let id = UUID()
    let category: ErrorCategory
    let action: SpeechErrorType
    let expected: String
    let predicted: String
    let rule: TajweedRule?
    let expectedDuration: Double?
    let actualDuration: Double?
}

enum ErrorExplainer {
    static func explain(expected: String, predicted: String,
                        durations: [Double] = [],
                        timing: TajweedTimingProfile = .fixed) -> [ReciterError] {
        evaluateWord(expected: expected, predicted: predicted, durations: durations,
                     nextExpected: "", nextPredicted: "", isLastWord: true,
                     verseLabel: "unit", wordIndex: 0, displayWord: "",
                     timing: timing)
    }

    static func explainAyah(expectedWords: [String], predictedWords: [String],
                            predictedDurations: [[Double]], targetWordIndex: Int? = nil,
                            verseLabel: String, displayWords: [String] = [],
                            timing: TajweedTimingProfile = .fixed) -> [Int: [ReciterError]] {
        let indices: [Int]
        if let targetWordIndex {
            let previous = targetWordIndex - 1
            indices = expectedWords.indices.contains(previous) ? [previous] : []
        } else {
            indices = Array(expectedWords.indices)
        }

        var result: [Int: [ReciterError]] = [:]
        for index in indices {
            guard predictedWords.indices.contains(index), !predictedWords[index].isEmpty else {
                RQLog.block("TAJWEED", "Skipped grading \(verseLabel) word[\(index)]", rows: [
                    ("reason", "no aligned model phonemes were committed for this word"),
                    ("reference", PhoneticDisplay.diagnostic(expectedWords[index]))
                ], verdict: "CODE SKIP — not enough aligned recognition data")
                continue
            }
            let nextExpected = expectedWords.indices.contains(index + 1) ? expectedWords[index + 1] : ""
            let nextPredicted = predictedWords.indices.contains(index + 1) ? predictedWords[index + 1] : ""
            let durations = predictedDurations.indices.contains(index) ? predictedDurations[index] : []
            let displayWord = displayWords.indices.contains(index) ? displayWords[index] : ""
            let errors = evaluateWord(expected: expectedWords[index], predicted: predictedWords[index],
                                      durations: durations, nextExpected: nextExpected,
                                      nextPredicted: nextPredicted,
                                      isLastWord: index == expectedWords.count - 1,
                                      verseLabel: verseLabel, wordIndex: index,
                                      displayWord: displayWord, timing: timing)
            if !errors.isEmpty { result[index] = errors }
        }
        return result
    }

    private enum Operation: String { case equal, insert, delete, replace }
    private struct Alignment {
        let operation: Operation
        let reference: Int?
        let predicted: Int?
    }

    private static func evaluateWord(expected: String, predicted: String, durations: [Double],
                                     nextExpected: String, nextPredicted: String,
                                     isLastWord: Bool, verseLabel: String,
                                     wordIndex: Int, displayWord: String,
                                     timing: TajweedTimingProfile) -> [ReciterError] {
        let compactExpected = expected.replacingOccurrences(of: " ", with: "")
        let compactPredicted = predicted.replacingOccurrences(of: " ", with: "")
        let gradedExpected = isLastWord ? droppingTerminalWaqfMark(compactExpected) : compactExpected
        let gradedPredicted = isLastWord ? droppingTerminalWaqfMark(compactPredicted) : compactPredicted
        var reference = QuranNormalizer.chunkPhonemes(gradedExpected)
        var spoken = QuranNormalizer.chunkPhonemes(gradedPredicted)
        var hasReferenceBoundary = false
        var hasSpokenBoundary = false
        if let next = QuranNormalizer.chunkPhonemes(nextExpected).first {
            reference.append(next)
            hasReferenceBoundary = true
        }
        if hasReferenceBoundary, let next = QuranNormalizer.chunkPhonemes(nextPredicted).first {
            spoken.append(next)
            hasSpokenBoundary = true
        }

        let alignment = align(reference, spoken)
        var errors: [ReciterError] = []
        var diagnosticLines: [String] = []
        var timingWasSkipped = false
        var suppressedModelOmissions: [String] = []

        for (position, item) in alignment.enumerated() {
            if hasReferenceBoundary, item.reference == reference.count - 1 { continue }
            if hasSpokenBoundary, item.predicted == spoken.count - 1 { continue }

            let referenceChunk = item.reference.flatMap { reference.indices.contains($0) ? reference[$0] : nil } ?? ""
            let predictedChunk = item.predicted.flatMap { spoken.indices.contains($0) ? spoken[$0] : nil } ?? ""
            let nextReferenceChunk: String
            let nextIsAcrossWord: Bool
            if let referenceIndex = item.reference, reference.indices.contains(referenceIndex + 1) {
                nextReferenceChunk = reference[referenceIndex + 1]
                nextIsAcrossWord = hasReferenceBoundary && referenceIndex == reference.count - 2
            } else {
                nextReferenceChunk = ""
                nextIsAcrossWord = false
            }

            var line = "op[\(position)] \(item.operation.rawValue) ref=\(PhoneticDisplay.diagnostic(referenceChunk)) pred=\(PhoneticDisplay.diagnostic(predictedChunk))"
            if item.reference == nil {
                errors.append(error(.normal, .insert, "", predictedChunk))
                diagnosticLines.append(line + " -> EXTRA MODEL PHONEME")
                continue
            }
            if item.predicted == nil {
                // A deletion proves only that the recognizer did not emit this
                // phoneme, not that the reciter omitted it. Keep it in the
                // diagnostic log, but do not turn a single model omission into
                // definite pronunciation feedback.
                suppressedModelOmissions.append(referenceChunk)
                diagnosticLines.append(line + " -> PROVISIONAL MODEL OMISSION; USER ERROR SUPPRESSED")
                continue
            }

            let referenceBase = referenceChunk.unicodeScalars.first
            let predictedBase = predictedChunk.unicodeScalars.first
            if let referenceBase, let predictedBase, referenceBase != predictedBase {
                errors.append(error(.normal, .replace, referenceChunk, predictedChunk))
                line += " -> BASE LETTER DIFFERENCE cost=\(substitutionCost(referenceBase, predictedBase))"
                diagnosticLines.append(line)
                if substitutionCost(referenceBase, predictedBase) > 6 { continue }
            } else if referenceChunk != predictedChunk {
                if isRepeatedMaddLengthVariation(referenceChunk, predictedChunk) {
                    // Repeated Madd symbols encode how long the vowel was held.
                    // Reporting their count difference as a Tashkeel replacement
                    // produces misleading feedback such as "replace ي with ي".
                    // The duration rule below is the single source of truth.
                    line += " -> MADD LENGTH VARIATION; GRADED BY TIMING"
                } else {
                    errors.append(error(.tashkeel, .replace, referenceChunk, predictedChunk))
                    line += " -> VOWEL/MARK DIFFERENCE"
                }
                diagnosticLines.append(line)
            } else {
                diagnosticLines.append(line + " -> PHONEMES EQUAL")
            }

            let rules = TajweedRules.rules(for: referenceChunk, isLastWord: isLastWord,
                                           nextChunk: nextReferenceChunk,
                                           isNextChunkInNextWord: nextIsAcrossWord,
                                           timing: timing)
            for rule in rules {
                if rule.kind == .shaddah,
                   repeatedBaseCount(referenceChunk) >= 2,
                   repeatedBaseCount(predictedChunk) < 2 {
                    errors.append(error(.tajweed, .replace, referenceChunk, predictedChunk,
                                        rule: rule, expectedDuration: rule.requiredDuration,
                                        actualDuration: durationSlice(predictedIndex: item.predicted,
                                                                      predictedChunk: predictedChunk,
                                                                      spokenGroups: spoken,
                                                                      durations: durations)?.reduce(0, +)))
                    diagnosticLines.append("rule=\(rule.nameEnglish) STRUCTURE FAIL expected doubled consonant")
                    continue
                }

                guard let parts = durationSlice(predictedIndex: item.predicted,
                                                predictedChunk: predictedChunk,
                                                spokenGroups: spoken,
                                                durations: durations) else {
                    timingWasSkipped = true
                    diagnosticLines.append("rule=\(rule.nameEnglish) TIMING SKIPPED: timestamps do not cover this complete chunk")
                    continue
                }
                let actual = parts.reduce(0, +)
                let passed = actual >= rule.requiredDuration
                diagnosticLines.append("rule=\(rule.nameEnglish) sound=\(PhoneticDisplay.baseLetter(referenceChunk)) chars=\(RQLog.durationSummary(parts)) paceTarget=\(String(format: "%.3fs", rule.targetDuration)) acceptedMinimum=\(String(format: "%.3fs", rule.requiredDuration)) -> \(passed ? "PASS" : "FAIL")")
                if !passed {
                    errors.append(error(.tajweed, .replace, referenceChunk, predictedChunk,
                                        rule: rule, expectedDuration: rule.requiredDuration,
                                        actualDuration: actual))
                }
            }
        }

        errors.sort { priority($0) < priority($1) }
        let hasPhonemeError = errors.contains { $0.category == .normal || $0.category == .tashkeel }
        let hasTimingError = errors.contains { $0.category == .tajweed }
        let verdict: String
        if hasPhonemeError {
            verdict = "MODEL/REFERENCE PHONEMES DIFFER — inspect operations above; the app did not invent the displayed letter"
        } else if hasTimingError {
            verdict = "TIMING RULE FAILED — phonemes match; duration was computed by CODE from MODEL token timestamps"
        } else if !suppressedModelOmissions.isEmpty {
            verdict = "RECOGNITION UNCERTAIN — model omissions were logged but not shown as reciter errors"
        } else if timingWasSkipped {
            verdict = "PHONEMES PASS; CODE intentionally skipped timing because timestamp coverage was incomplete"
        } else {
            verdict = "PASS — aligned model phonemes and applicable Tajweed timings match the reference"
        }
        RQLog.block("TAJWEED", "Grade \(verseLabel) word[\(wordIndex)] \(displayWord)", rows: [
            ("reference", PhoneticDisplay.diagnostic(expected)),
            ("model aligned", PhoneticDisplay.diagnostic(predicted)),
            ("timestamps", RQLog.durationSummary(durations)),
            ("pace profile", "harakah=\(String(format: "%.3fs", timing.harakah)) mode=\(timing.isAdaptive ? "adaptive" : "fallback/fixed") samples=\(timing.sampleCount) grace=\(Int((timing.graceFraction * 100).rounded()))%"),
            ("ayah-ending policy", isLastWord
                ? "waqf and wasl accepted; terminal case vowel/sukoon is not graded"
                : "not an ayah-ending word"),
            ("context next", nextExpected.isEmpty ? "end of ayah" : PhoneticDisplay.diagnostic(nextExpected)),
            ("model omissions suppressed", suppressedModelOmissions.isEmpty
                ? "none"
                : suppressedModelOmissions.map(PhoneticDisplay.diagnostic).joined(separator: " | ")),
            ("errors", errors.isEmpty ? "none" : errors.map(errorSummary).joined(separator: " | "))
        ], details: diagnosticLines, verdict: verdict)
        return errors
    }

    private static let terminalWaqfMarks = Set("ًٌٍَُِْ".unicodeScalars)

    private static func droppingTerminalWaqfMark(_ value: String) -> String {
        var scalars = Array(value.unicodeScalars)
        while let last = scalars.last, terminalWaqfMarks.contains(last) {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func durationSlice(predictedIndex: Int?, predictedChunk: String,
                                      spokenGroups: [String], durations: [Double]) -> [Double]? {
        guard let predictedIndex, spokenGroups.indices.contains(predictedIndex),
              !predictedChunk.isEmpty else { return nil }
        let start = spokenGroups.prefix(predictedIndex).reduce(0) { $0 + $1.unicodeScalars.count }
        let count = predictedChunk.unicodeScalars.count
        guard count > 0, durations.count >= start + count else { return nil }
        let result = Array(durations[start..<(start + count)])
        guard result.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return result
    }

    private static func error(_ category: ErrorCategory, _ action: SpeechErrorType,
                              _ expected: String, _ predicted: String,
                              rule: TajweedRule? = nil,
                              expectedDuration: Double? = nil,
                              actualDuration: Double? = nil) -> ReciterError {
        .init(category: category, action: action, expected: expected, predicted: predicted,
              rule: rule, expectedDuration: expectedDuration, actualDuration: actualDuration)
    }

    private static func errorSummary(_ error: ReciterError) -> String {
        if let rule = error.rule, let expected = error.expectedDuration, let actual = error.actualDuration {
            return "\(rule.nameEnglish) timing \(String(format: "%.3f", actual))s/\(String(format: "%.3f", expected))s"
        }
        return "\(error.category.rawValue).\(error.action.rawValue) expected=\(PhoneticDisplay.readable(error.expected)) predicted=\(PhoneticDisplay.readable(error.predicted))"
    }

    private static func repeatedBaseCount(_ chunk: String) -> Int {
        guard let base = chunk.unicodeScalars.first else { return 0 }
        return chunk.unicodeScalars.reduce(into: 0) { count, scalar in
            if scalar == base { count += 1 }
        }
    }

    private static func isRepeatedMaddLengthVariation(_ reference: String,
                                                      _ predicted: String) -> Bool {
        let referenceScalars = Array(reference.unicodeScalars)
        let predictedScalars = Array(predicted.unicodeScalars)
        guard let base = referenceScalars.first,
              predictedScalars.first == base,
              referenceScalars.count != predictedScalars.count,
              referenceScalars.allSatisfy({ $0 == base }),
              predictedScalars.allSatisfy({ $0 == base }) else { return false }
        return Set<UInt32>([0x0627, 0x06E5, 0x06E6, 0x0648, 0x064A]).contains(base.value)
    }

    private static func align(_ reference: [String], _ predicted: [String]) -> [Alignment] {
        let n = reference.count, m = predicted.count
        var matrix = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { matrix[i][0] = i * 10 }
        for j in 0...m { matrix[0][j] = j * 10 }
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let lhs = reference[i - 1].unicodeScalars.first
                    let rhs = predicted[j - 1].unicodeScalars.first
                    let cost = lhs.flatMap { left in rhs.map { substitutionCost(left, $0) } } ?? 10
                    matrix[i][j] = min(matrix[i - 1][j - 1] + cost,
                                       matrix[i - 1][j] + 10,
                                       matrix[i][j - 1] + 10)
                }
            }
        }
        var i = n, j = m, output: [Alignment] = []
        while i > 0 || j > 0 {
            if i > 0, j > 0 {
                let lhs = reference[i - 1].unicodeScalars.first
                let rhs = predicted[j - 1].unicodeScalars.first
                let cost = lhs.flatMap { left in rhs.map { substitutionCost(left, $0) } } ?? 10
                if matrix[i][j] == matrix[i - 1][j - 1] + cost {
                    output.append(.init(operation: cost == 0 ? .equal : .replace,
                                        reference: i - 1, predicted: j - 1))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0, matrix[i][j] == matrix[i - 1][j] + 10 {
                output.append(.init(operation: .delete, reference: i - 1, predicted: nil))
                i -= 1
            } else if j > 0 {
                output.append(.init(operation: .insert, reference: nil, predicted: j - 1))
                j -= 1
            }
        }
        return output.reversed()
    }

    private static let similarGroups = [
        "ذدضتط", "ظزذصسث", "جزش", "ءأإآاهعحغخ", "ةهت",
        "ۦي", "ۥو", "ںن۾م", "قكغ", "فبم"
    ]

    private static func substitutionCost(_ lhs: Unicode.Scalar, _ rhs: Unicode.Scalar) -> Int {
        if lhs == rhs { return 0 }
        if similarGroups.contains(where: { group in
            group.unicodeScalars.contains(lhs) && group.unicodeScalars.contains(rhs)
        }) { return 6 }
        return 12
    }

    private static func priority(_ error: ReciterError) -> Int {
        if error.category == .tashkeel { return 1 }
        switch error.rule?.kind {
        case .normalMadd, .separatedMadd, .connectedMadd, .temporaryMadd, .leenMadd, .lazimMadd: return 2
        case .ghunnah: return 3
        case .shaddah: return 4
        case nil: return 5
        }
    }
}
