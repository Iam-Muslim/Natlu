import Foundation

struct RecitationPaceEstimator {
    private static let fallbackHarakah = 0.160
    private static let graceFraction = 0.15
    private static let timestampAllowance = 0.020
    private static let minimumSamples = 8
    private static let maximumSamples = 30
    private static let minimumSampleDuration = 0.080
    private static let maximumSampleDuration = 0.450
    private static let smoothingWeight = 0.20
    private static let shortVowels = Set<UInt32>([0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650])

    private var samples: [Double] = []
    private var smoothedHarakah = fallbackHarakah
    private var hasAdaptiveEstimate = false

    var profile: TajweedTimingProfile {
        TajweedTimingProfile(
            harakah: smoothedHarakah,
            graceFraction: Self.graceFraction,
            timestampAllowance: Self.timestampAllowance,
            sampleCount: samples.count,
            isAdaptive: hasAdaptiveEstimate
        )
    }

    mutating func reset(reason: String) {
        samples = []
        smoothedHarakah = Self.fallbackHarakah
        hasAdaptiveEstimate = false
        logProfile(title: "Pace estimator reset", rows: [
            ("reason", reason),
            ("learning", "needs \(Self.minimumSamples) clean short-vowel samples"),
            ("fallback harakah", seconds(smoothedHarakah))
        ], verdict: "FALLBACK ACTIVE — thresholds will adapt after enough reliable speech")
    }

    mutating func observe(expected: String, predicted: String, durations: [Double],
                          verseLabel: String, wordIndex: Int) {
        let referenceGroups = QuranNormalizer.chunkPhonemes(expected.replacingOccurrences(of: " ", with: ""))
        let predictedGroups = QuranNormalizer.chunkPhonemes(predicted.replacingOccurrences(of: " ", with: ""))
        guard referenceGroups.count == predictedGroups.count else {
            logProfile(title: "Ignored pace word \(verseLabel) word[\(wordIndex)]", rows: [
                ("reference", PhoneticDisplay.diagnostic(expected)),
                ("model aligned", PhoneticDisplay.diagnostic(predicted)),
                ("reason", "phoneme-group count differs (\(referenceGroups.count) vs \(predictedGroups.count))")
            ], verdict: "PACE SAMPLE REJECTED — only exact ordinary sounds may teach reading speed")
            return
        }

        let scalarTotal = predictedGroups.reduce(0) { $0 + $1.unicodeScalars.count }
        guard durations.count >= scalarTotal else {
            logProfile(title: "Ignored pace word \(verseLabel) word[\(wordIndex)]", rows: [
                ("reference", PhoneticDisplay.diagnostic(expected)),
                ("model aligned", PhoneticDisplay.diagnostic(predicted)),
                ("timestamps", RQLog.durationSummary(durations)),
                ("reason", "timestamps do not cover every predicted scalar")
            ], verdict: "PACE SAMPLE REJECTED — incomplete timestamp coverage")
            return
        }

        var cursor = 0
        var accepted: [(String, Double)] = []
        var ignored: [String: Int] = [:]
        for index in referenceGroups.indices {
            let reference = referenceGroups[index]
            let spoken = predictedGroups[index]
            let scalarCount = spoken.unicodeScalars.count
            defer { cursor += scalarCount }

            guard reference == spoken else {
                ignored["phoneme mismatch", default: 0] += 1
                continue
            }
            guard reference.unicodeScalars.contains(where: { Self.shortVowels.contains($0.value) }) else {
                ignored["not a short vowel", default: 0] += 1
                continue
            }
            guard TajweedRules.rules(for: reference, isLastWord: false).isEmpty else {
                ignored["has a Tajweed timing rule", default: 0] += 1
                continue
            }
            let parts = Array(durations[cursor..<(cursor + scalarCount)])
            guard parts.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                ignored["invalid timestamp", default: 0] += 1
                continue
            }
            let duration = parts.reduce(0, +)
            guard duration >= Self.minimumSampleDuration,
                  duration <= Self.maximumSampleDuration else {
                ignored["pause/outlier", default: 0] += 1
                continue
            }
            accepted.append((reference, duration))
        }

        if !accepted.isEmpty {
            samples.append(contentsOf: accepted.map { $0.1 })
            if samples.count > Self.maximumSamples {
                samples.removeFirst(samples.count - Self.maximumSamples)
            }
            if samples.count >= Self.minimumSamples {
                let middle = median(samples).clamped(to: 0.120...0.300)
                if hasAdaptiveEstimate {
                    smoothedHarakah = (1 - Self.smoothingWeight) * smoothedHarakah +
                        Self.smoothingWeight * middle
                } else {
                    smoothedHarakah = middle
                    hasAdaptiveEstimate = true
                }
            }
        }

        let acceptedDescription = accepted.isEmpty
            ? "none"
            : accepted.map { "\(PhoneticDisplay.readable($0.0))=\(seconds($0.1))" }.joined(separator: ", ")
        let ignoredDescription = ignored.isEmpty
            ? "none"
            : ignored.keys.sorted().map { "\($0)=\(ignored[$0] ?? 0)" }.joined(separator: ", ")
        let current = profile
        logProfile(title: "Learn pace from \(verseLabel) word[\(wordIndex)]", rows: [
            ("reference", PhoneticDisplay.diagnostic(expected)),
            ("model aligned", PhoneticDisplay.diagnostic(predicted)),
            ("accepted samples", acceptedDescription),
            ("ignored chunks", ignoredDescription),
            ("rolling window", "\(samples.count)/\(Self.maximumSamples) samples"),
            ("estimated harakah", "\(seconds(current.harakah)) mode=\(current.isAdaptive ? "adaptive" : "fallback")")
        ], verdict: accepted.isEmpty
            ? "NO PACE UPDATE — this word contained no safe ordinary timing samples"
            : "PACE UPDATED — future Tajweed duration checks use the profile below")
    }

    private func logProfile(title: String, rows: [(String, String)], verdict: String) {
        let current = profile
        let naturalTarget = current.targetDuration(for: .normalMadd)
        let naturalMinimum = current.minimumDuration(for: .normalMadd)
        RQLog.block("PACE", title, rows: rows + [
            ("grace", "\(Int((current.graceFraction * 100).rounded()))% plus \(seconds(current.timestampAllowance)) timestamp allowance"),
            ("Natural Madd", "target=\(seconds(naturalTarget)) minimum=\(seconds(naturalMinimum)) (one harakah minus timestamp allowance)"),
            ("Ghunnah", "target=\(seconds(current.targetDuration(for: .ghunnah))) minimum=\(seconds(current.minimumDuration(for: .ghunnah)))"),
            ("4-count Madd", "target=\(seconds(current.targetDuration(for: .temporaryMadd))) minimum=\(seconds(current.minimumDuration(for: .temporaryMadd)))")
        ], verdict: verdict)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.3fs", value)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
