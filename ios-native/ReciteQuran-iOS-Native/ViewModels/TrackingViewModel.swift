import Foundation
import Observation

enum TrackerState: Equatable { case discovery, tracking }
enum TrackingGuidanceTone: Equatable { case listening, success, warning }
enum TajweedWordGradeTone: Equatable { case gold, red }

@MainActor @Observable
final class TrackingViewModel {
    private let repository: QuranRepository
    private let aligner = PhonemeAligner()
    private(set) var verses: [QuranVerse] = []
    private(set) var targetSurah = 1
    private(set) var activeAyah = 1
    private(set) var state: TrackerState = .discovery
    private(set) var recognizedText = ""
    private(set) var guidanceTitle = "Ready"
    private(set) var guidanceDetail = "Tap the microphone to begin."
    private(set) var guidanceTargetWord = ""
    private(set) var guidanceHeardWords = ""
    private(set) var guidanceTone: TrackingGuidanceTone = .listening
    private(set) var greenWords: [Int: Set<Int>] = [:]
    private(set) var redWords: [Int: Set<Int>] = [:]
    private(set) var yellowWords: [Int: Set<Int>] = [:]
    private(set) var uncertainWords: [Int: Set<Int>] = [:]
    private(set) var errors: [Int: [Int: [ReciterError]]] = [:]
    private var spokenWords: [Int: [Int: String]] = [:]
    private var spokenDurations: [Int: [Int: [Double]]] = [:]
    private var paceEstimator = RecitationPaceEstimator()
    private var lastProcessedText = ""
    private var expectingNewSegment = false
    private var heardWordHistory: [String] = []

    init(repository: QuranRepository) { self.repository = repository }

    func setSurah(_ surah: Int, ayah: Int = 1, clear: Bool = true) async {
        targetSurah = surah
        verses = await repository.surah(surah)
        activeAyah = min(max(1, ayah), max(1, verses.count))
        if clear {
            clearAllProgress()
            recognizedText = ""
            lastProcessedText = ""
            expectingNewSegment = false
            paceEstimator.reset(reason: "full Surah reset to \(surah):\(activeAyah)")
        }
        RQLog.write("FLOW", "select surah=\(surah) ayah=\(activeAyah) clearHighlights=\(clear)")
        await configureActiveVerse(resetTranscript: true, preserveAlignerTail: false, reason: "surah selection")
    }

    func setManualAyah(_ ayah: Int) async {
        let selectedAyah = min(max(1, ayah), max(1, verses.count))
        activeAyah = selectedAyah
        let ayahsToClear = Set([selectedAyah, selectedAyah + 1].filter { $0 <= verses.count })
        clearProgress(ayahs: ayahsToClear)
        lastProcessedText = ""; recognizedText = ""; expectingNewSegment = false
        RQLog.write("FLOW", "manual ayah selection surah=\(targetSurah) ayah=\(activeAyah) clearedAyahs=\(ayahsToClear.sorted())")
        await configureActiveVerse(resetTranscript: true, preserveAlignerTail: false, reason: "manual selection")
        if state == .tracking {
            showListeningGuidance(prefix: localized("Ayah restarted.", "أُعيد بدء الآية."))
        }
    }

    func startTracking() {
        state = .tracking
        paceEstimator.reset(reason: "new recording session at \(targetSurah):\(activeAyah)")
        showListeningGuidance()
        RQLog.write("TRACK", "tracking started at \(targetSurah):\(activeAyah)")
        RQLog.block("DEBUG-GUIDE", "How to identify the source of a recognition problem", rows: [
            ("MODEL", "raw neural-network text, tokens, and timestamp spikes"),
            ("PIPELINE", "app conversion of those tokens into phonemes and durations"),
            ("ALIGNMENT", "which expected Quran word the app assigned the model phonemes to"),
            ("PACE", "clean short vowels used to estimate this recording session's harakah"),
            ("TAJWEED", "rule-by-rule comparison, timing math, and a source verdict"),
            ("UI-RESULT", "the exact errors stored for the yellow word and sheet")
        ], verdict: "The first stage where the values become wrong identifies whether the fault is MODEL or CODE")
    }
    func stopTracking() {
        state = .discovery
        guidanceTitle = localized("Recording stopped", "تم إيقاف التسجيل")
        guidanceDetail = localized("Tap the microphone when you are ready to continue.", "اضغط على الميكروفون عندما تكون مستعدًا للمتابعة.")
        guidanceTargetWord = ""
        resetHeardWords()
        guidanceTone = .listening
        RQLog.write("TRACK", "tracking stopped at \(targetSurah):\(activeAyah)")
    }

    func setTajweed(_ enabled: Bool) async {
        RQLog.write("FLOW", "tajweed mode changed enabled=\(enabled)")
        await configureActiveVerse(resetTranscript: true, preserveAlignerTail: false, reason: "mode change")
    }

    func handle(_ result: TranscriptionResult, tajweed: Bool) async {
        guard state == .tracking, let verse = currentVerse else {
            RQLog.write("TRACK", "ignored ASR because tracker is not active")
            return
        }
        let prepared = prepareASR(result)
        let asrText = prepared.text
        var durations = prepared.durations
        let previousRecognizedText = recognizedText
        recognizedText = asrText
        if asrText != previousRecognizedText || result.isFinal {
            RQLog.block("PIPELINE", "Model tokens converted to tracker input", rows: [
                ("verse", "\(verse.surah):\(verse.ayah) wordCursor=\(currentWord(in: verse).map(String.init) ?? "complete")"),
                ("raw model text", "\"\(RQLog.preview(result.text, limit: 140))\""),
                ("tracker text", "\"\(RQLog.preview(asrText, limit: 140))\""),
                ("tracker unicode", RQLog.codepoints(asrText)),
                ("derived durations", RQLog.durationSummary(durations)),
                ("ASR segment", result.isFinal ? "final endpoint" : "cumulative partial")
            ], verdict: "CODE TRANSFORM — 320ms timestamp compensation and per-scalar duration distribution applied")
        }
        guard asrText.unicodeScalars.count <= 8_000 else { lastProcessedText = ""; return }
        if asrText.isEmpty {
            if result.isFinal {
                let events = await aligner.feed("", isFinal: true)
                apply(events, verse: verse, tajweed: tajweed)
            }
            lastProcessedText = ""
            if result.isFinal { expectingNewSegment = true }
            return
        }
        if expectingNewSegment { lastProcessedText = ""; expectingNewSegment = false }
        let old = Array(lastProcessedText.unicodeScalars), new = Array(asrText.unicodeScalars)
        var common = 0
        while common < min(old.count, new.count), old[common] == new[common] { common += 1 }
        if common == 0 || (common < 5 && old.count > 20) { lastProcessedText = "" }
        let currentOld = Array(lastProcessedText.unicodeScalars)
        common = 0
        while common < min(currentOld.count, new.count), currentOld[common] == new[common] { common += 1 }
        let events: [AlignerEvent]
        if common == currentOld.count {
            let delta = String(String.UnicodeScalarView(new.dropFirst(common)))
            if durations.count >= common { durations = Array(durations.dropFirst(common)) } else { durations = [] }
            if !delta.isEmpty {
                RQLog.write("TRACK", "ASR append verse=\(targetSurah):\(activeAyah) total=\(new.count) cursor=\(currentOld.count) delta=\(delta.unicodeScalars.count) final=\(result.isFinal) text=\(RQLog.preview(delta))")
            }
            events = delta.isEmpty && !result.isFinal
                ? []
                : await aligner.feed(delta, timestamps: durations, isFinal: result.isFinal)
        } else {
            let backtrack = currentOld.count - common
            let tail = String(String.UnicodeScalarView(new.dropFirst(common)))
            let tailDurations = durations.count >= common ? Array(durations.dropFirst(common)) : []
            RQLog.write("TRACK", "ASR rewrite verse=\(targetSurah):\(activeAyah) common=\(common) backtrack=\(backtrack) newTail=\(RQLog.preview(tail))")
            events = await aligner.replaceTail(backtrack: backtrack, with: tail,
                                               timestamps: tailDurations,
                                               isFinal: result.isFinal)
        }
        apply(events, verse: verse, tajweed: tajweed)
        lastProcessedText = asrText
        if result.isFinal { expectingNewSegment = true }
    }

    var currentVerse: QuranVerse? { verses.first { $0.ayah == activeAyah } }
    var guidanceHeardLabel: String { localized("Heard approximately", "سمعت تقريبًا") }
    func isGreen(ayah: Int, word: Int) -> Bool { greenWords[ayah]?.contains(word) == true }
    func isRed(ayah: Int, word: Int) -> Bool { redWords[ayah]?.contains(word) == true }
    func isYellow(ayah: Int, word: Int) -> Bool { yellowWords[ayah]?.contains(word) == true }
    func isUncertain(ayah: Int, word: Int) -> Bool { uncertainWords[ayah]?.contains(word) == true }
    func wordErrors(ayah: Int, word: Int) -> [ReciterError] { errors[ayah]?[word] ?? [] }
    func currentWord(in verse: QuranVerse) -> Int? {
        guard verse.ayah == activeAyah else { return nil }
        return verse.phonemeWords.indices.first { index in
            !(greenWords[verse.ayah]?.contains(index) == true) && !(redWords[verse.ayah]?.contains(index) == true)
                && !(yellowWords[verse.ayah]?.contains(index) == true)
                && !(uncertainWords[verse.ayah]?.contains(index) == true)
        }
    }

    private func configureActiveVerse(resetTranscript: Bool, preserveAlignerTail: Bool,
                                       reason: String) async {
        guard let verse = currentVerse else { return }
        resetHeardWords()
        if resetTranscript {
            lastProcessedText = ""
            expectingNewSegment = false
        }
        let startingWord = firstUnresolvedWord(in: verse)
        let continuationWords = verses.first { $0.ayah == verse.ayah + 1 }
            .map { Array($0.phonemeWords.prefix(2)) } ?? []
        await aligner.setVerse(verse.phonemeWords,
                               tajweed: AppState.shared.mode == .tajweed,
                               forceClear: !preserveAlignerTail,
                               startingWord: startingWord,
                               label: "\(verse.surah):\(verse.ayah)",
                               continuationWords: continuationWords)
        let alignerState = await aligner.debugState()
        RQLog.write("FLOW", "configured ayah=\(verse.surah):\(verse.ayah) reason=\(reason) resetTranscript=\(resetTranscript) transcriptCursor=\(lastProcessedText.unicodeScalars.count) startWord=\(startingWord) preserveTail=\(preserveAlignerTail) \(alignerState)")
    }

    private func firstUnresolvedWord(in verse: QuranVerse) -> Int {
        verse.phonemeWords.indices.first { index in
            !(greenWords[verse.ayah]?.contains(index) == true) &&
                !(redWords[verse.ayah]?.contains(index) == true) &&
                !(yellowWords[verse.ayah]?.contains(index) == true) &&
                !(uncertainWords[verse.ayah]?.contains(index) == true)
        } ?? verse.phonemeWords.count
    }

    private func clearProgress(ayahs: Set<Int>) {
        for ayah in ayahs {
            greenWords.removeValue(forKey: ayah)
            redWords.removeValue(forKey: ayah)
            yellowWords.removeValue(forKey: ayah)
            uncertainWords.removeValue(forKey: ayah)
            errors.removeValue(forKey: ayah)
            spokenWords.removeValue(forKey: ayah)
            spokenDurations.removeValue(forKey: ayah)
        }
    }

    private func prepareASR(_ result: TranscriptionResult) -> (text: String, durations: [Double]) {
        struct TimedToken { let text: String, time: Double }
        let ignored = Set(["<blank>", "<blk>", "<eps>", "eps", "<s>", "</s>", "<unk>"])
        var tokens: [TimedToken] = []
        for index in 0..<min(result.tokens.count, result.timestamps.count) {
            let token = result.tokens[index].replacingOccurrences(of: " ", with: "")
            guard !token.isEmpty, !ignored.contains(token) else { continue }
            tokens.append(.init(text: token, time: max(0, Double(result.timestamps[index]) - 0.320)))
        }
        guard !tokens.isEmpty else {
            return (result.text.replacingOccurrences(of: "<blank>|<s>|</s>|<unk>| ", with: "", options: .regularExpression), [])
        }
        var text = "", durations: [Double] = []
        for index in tokens.indices {
            let start = index == 0 ? max(0, tokens[index].time - 0.5) : tokens[index - 1].time
            let end = index == tokens.count - 1 ? tokens[index].time + 0.3 : tokens[index].time
            let scalarCount = max(1, tokens[index].text.unicodeScalars.count)
            let perScalar = max(0.04, end - start) / Double(scalarCount)
            text += tokens[index].text
            durations += Array(repeating: perScalar, count: scalarCount)
        }
        return (text, durations)
    }

    private func apply(_ events: [AlignerEvent], verse: QuranVerse, tajweed: Bool) {
        for event in events {
            switch event {
            case .highlight(let word, let isRed, let spoken, let timestamps):
                RQLog.write("TRACK", "highlight verse=\(verse.surah):\(verse.ayah) word=\(word) color=\(isRed ? "red" : "green") spoken=\(RQLog.preview(spoken))")
                spokenWords[verse.ayah, default: [:]][word] = spoken
                spokenDurations[verse.ayah, default: [:]][word] = timestamps
                if isRed { redWords[verse.ayah, default: []].insert(word) }
                else { greenWords[verse.ayah, default: []].insert(word) }
                if tajweed, !isRed, !spoken.isEmpty,
                   verse.phonemeWords.indices.contains(word) {
                    paceEstimator.observe(expected: verse.phonemeWords[word],
                                          predicted: spoken,
                                          durations: timestamps,
                                          verseLabel: "\(verse.surah):\(verse.ayah)",
                                          wordIndex: word)
                }
                let displayed = displayWord(for: word, in: verse)
                if !spoken.isEmpty, !displayed.isEmpty {
                    appendHeardWord(displayed, verse: verse, phonemeIndex: word)
                }
                if isRed {
                    guidanceTitle = localized("Tracking is recovering", "جارٍ استعادة التتبع")
                    guidanceTargetWord = displayed
                    guidanceDetail = localized("Keep reciting normally. The app will align with the following words.", "واصل التلاوة بشكل طبيعي، وسيحاذي التطبيق الكلمات التالية.")
                    guidanceTone = .listening
                } else {
                    guidanceTitle = localized("Recognized", "تم التعرف")
                    guidanceTargetWord = displayed
                    let next = displayWord(for: word + 1, in: verse)
                    guidanceDetail = next.isEmpty
                        ? localized("Finishing this ayah…", "جاري إكمال الآية…")
                        : localized("Good. Continue with the highlighted word.", "جيد. تابع بالكلمة المظللة.")
                    guidanceTone = .success
                }
                if tajweed, !spoken.isEmpty, word > 0 {
                    clearTajweedGrade(word - 1, verse: verse)
                    applyTajweedGrades(gradeTajweed(verse: verse, targetWordIndex: word), verse: verse)
                }
            case .uncertain(let word):
                uncertainWords[verse.ayah, default: []].insert(word)
                greenWords[verse.ayah]?.remove(word)
                redWords[verse.ayah]?.remove(word)
                yellowWords[verse.ayah]?.remove(word)
                errors[verse.ayah]?.removeValue(forKey: word)
                guidanceTitle = localized("Tracking recovered", "تمت استعادة التتبع")
                guidanceTargetWord = displayWord(for: word + 1, in: verse)
                guidanceDetail = localized("One word was left ungraded because recognition was uncertain. Keep reciting.", "تُركت كلمة واحدة بلا تقييم لعدم وضوح التعرّف. واصل التلاوة.")
                guidanceTone = .listening
            case .waiting(let word, _, let heard, let enoughAudio):
                let displayed = displayWord(for: word, in: verse)
                updateHeardApproximation(from: heard, around: word, in: verse)
                if enoughAudio {
                    guidanceTitle = localized("Still aligning", "جارٍ ضبط التتبع")
                    guidanceTargetWord = displayed
                    guidanceDetail = localized("Keep reciting normally. Recognition will recover from the following words.", "واصل التلاوة بشكل طبيعي، وسيُستعاد التتبع من الكلمات التالية.")
                    guidanceTone = .listening
                    RQLog.write("RECOVERY", "provisional mismatch verse=\(verse.surah):\(verse.ayah) word=\(word) heard=\(RQLog.preview(heard)); UI continues without requesting a repeat")
                } else {
                    guidanceTitle = localized("Listening for", "أستمع إلى")
                    guidanceTargetWord = displayed
                    guidanceDetail = heard.isEmpty
                        ? localized("Continue reciting clearly.", "تابع التلاوة بوضوح.")
                        : localized("Matching the sound to nearby Quran words.", "أطابق الصوت مع كلمات القرآن القريبة.")
                    guidanceTone = .listening
                }
            case .ayahCompleted(let spokenWords, let timestamps, let preserveCarryover):
                RQLog.write("FLOW", "completion received verse=\(verse.surah):\(verse.ayah) words=\(spokenWords.count) preserveCarryover=\(preserveCarryover); scheduling auto-advance")
                guidanceTitle = localized("Ayah \(verse.ayah) complete", "اكتملت الآية \(verse.ayah)")
                guidanceDetail = localized("Moving to the next ayah. Keep reciting.", "ننتقل إلى الآية التالية. واصل التلاوة.")
                guidanceTargetWord = ""
                guidanceTone = .success
                if tajweed {
                    for index in verse.phonemeWords.indices {
                        clearTajweedGrade(index, verse: verse)
                    }
                    applyTajweedGrades(ErrorExplainer.explainAyah(
                        expectedWords: verse.phonemeWords,
                        predictedWords: spokenWords,
                        predictedDurations: timestamps,
                        verseLabel: "\(verse.surah):\(verse.ayah)",
                        displayWords: verse.phonemeWords.indices.map { displayWord(for: $0, in: verse) },
                        timing: paceEstimator.profile
                    ), verse: verse)
                }
                Task { await advance(after: verse.ayah, preserveCarryover: preserveCarryover) }
            }
        }
    }

    private func gradeTajweed(verse: QuranVerse, targetWordIndex: Int) -> [Int: [ReciterError]] {
        let predicted = verse.phonemeWords.indices.map { spokenWords[verse.ayah]?[$0] ?? "" }
        let durations = verse.phonemeWords.indices.map { spokenDurations[verse.ayah]?[$0] ?? [] }
        return ErrorExplainer.explainAyah(
            expectedWords: verse.phonemeWords,
            predictedWords: predicted,
            predictedDurations: durations,
            targetWordIndex: targetWordIndex,
            verseLabel: "\(verse.surah):\(verse.ayah)",
            displayWords: verse.phonemeWords.indices.map { displayWord(for: $0, in: verse) },
            timing: paceEstimator.profile
        )
    }

    private func clearTajweedGrade(_ index: Int, verse: QuranVerse) {
        yellowWords[verse.ayah]?.remove(index)
        errors[verse.ayah]?.removeValue(forKey: index)
        if spokenWords[verse.ayah]?[index]?.isEmpty == false {
            // A red word with committed speech came from Tajweed grading, not
            // whole-word alignment loss, so it is safe to restore before the
            // latest grade is applied.
            redWords[verse.ayah]?.remove(index)
            greenWords[verse.ayah, default: []].insert(index)
        }
    }

    static func gradeTone(for errors: [ReciterError]) -> TajweedWordGradeTone {
        errors.allSatisfy {
            $0.category == .tajweed && $0.rule?.kind == .normalMadd
        } ? .gold : .red
    }

    private func applyTajweedGrades(_ grades: [Int: [ReciterError]], verse: QuranVerse) {
        for (index, found) in grades where !found.isEmpty {
            greenWords[verse.ayah]?.remove(index)
            yellowWords[verse.ayah]?.remove(index)
            redWords[verse.ayah]?.remove(index)
            let tone = Self.gradeTone(for: found)
            switch tone {
            case .gold: yellowWords[verse.ayah, default: []].insert(index)
            case .red: redWords[verse.ayah, default: []].insert(index)
            }
            errors[verse.ayah, default: [:]][index] = found
            RQLog.block("UI-RESULT", "Stored Tajweed feedback \(verse.surah):\(verse.ayah) word[\(index)]", rows: [
                ("Quran word", displayWord(for: index, in: verse)),
                ("error count", "\(found.count)"),
                ("word color", tone == .gold ? "gold — Natural Madd timing only" : "red — pronunciation or non-Natural-Madd error"),
                ("categories", found.map { "\($0.category.rawValue)/\($0.rule?.kind.rawValue ?? $0.action.rawValue)" }.joined(separator: ", "))
            ], verdict: "CODE RESULT — this exact payload and severity color are displayed")
        }
    }

    private func advance(after ayah: Int, preserveCarryover: Bool) async {
        guard activeAyah == ayah else { return }
        try? await Task.sleep(for: .milliseconds(50))
        if verses.contains(where: { $0.ayah == ayah + 1 }) {
            activeAyah = ayah + 1
            RQLog.write("FLOW", "auto-advance within surah \(targetSurah):\(ayah) -> \(targetSurah):\(activeAyah)")
            await configureActiveVerse(resetTranscript: false, preserveAlignerTail: preserveCarryover,
                                       reason: "automatic advance")
            showListeningGuidance(prefix: localized("Now recite the next ayah.", "ابدأ الآن بالآية التالية."))
        } else if targetSurah < 114 {
            let previousSurah = targetSurah
            targetSurah += 1
            verses = await repository.surah(targetSurah)
            activeAyah = 1
            clearAllProgress()
            recognizedText = ""
            lastProcessedText = ""
            expectingNewSegment = true
            paceEstimator.reset(reason: "automatic Surah boundary reset to \(targetSurah):1")
            RQLog.write("FLOW", "auto-advance across surah \(previousSurah):\(ayah) -> \(targetSurah):1")
            await configureActiveVerse(resetTranscript: true, preserveAlignerTail: false,
                                       reason: "automatic surah advance")
            showListeningGuidance(prefix: localized("The next surah is ready.", "السورة التالية جاهزة."))
        }
    }

    private func clearAllProgress() {
        greenWords = [:]
        redWords = [:]
        yellowWords = [:]
        uncertainWords = [:]
        errors = [:]
        spokenWords = [:]
        spokenDurations = [:]
        RQLog.write("FLOW", "cleared Surah-scoped highlights and grading state")
    }

    private func showListeningGuidance(prefix: String? = nil) {
        guard let verse = currentVerse else { return }
        resetHeardWords()
        let first = displayWord(for: currentWord(in: verse) ?? 0, in: verse)
        guidanceTitle = localized("Listening to Ayah \(verse.ayah)", "أستمع إلى الآية \(verse.ayah)")
        guidanceTargetWord = first
        let instruction = localized("Begin with the highlighted word.", "ابدأ بالكلمة المظللة.")
        guidanceDetail = prefix.map { "\($0) \(instruction)" } ?? instruction
        guidanceTone = .listening
    }

    private func resetHeardWords() {
        heardWordHistory = []
        guidanceHeardWords = ""
    }

    private func appendHeardWord(_ word: String, verse: QuranVerse, phonemeIndex: Int) {
        heardWordHistory.append(word)
        if heardWordHistory.count > 3 { heardWordHistory.removeFirst(heardWordHistory.count - 3) }
        guidanceHeardWords = heardWordHistory.joined(separator: " ")
        RQLog.write("HEARD-WORDS", "confirmed alignment verse=\(verse.surah):\(verse.ayah) phonemeWord=\(phonemeIndex) Arabic=\(readableWord(for: phonemeIndex, in: verse))")
    }

    private func updateHeardApproximation(from heard: String, around word: Int, in verse: QuranVerse) {
        let previous = guidanceHeardWords
        guard let match = Self.approximateHeardWordIndex(
            from: heard,
            expectedWords: verse.phonemeWords,
            around: word
        ) else {
            guidanceHeardWords = heardWordHistory.joined(separator: " ")
            if previous != guidanceHeardWords, !heard.isEmpty {
                RQLog.write("HEARD-WORDS", "no confident Quran-word approximation verse=\(verse.surah):\(verse.ayah) cursor=\(word) raw=\(RQLog.preview(heard))")
            }
            return
        }

        let approximation = displayWord(for: match.index, in: verse)
        guard !approximation.isEmpty else { return }
        var visibleWords = heardWordHistory
        if visibleWords.last != approximation { visibleWords.append(approximation) }
        guidanceHeardWords = visibleWords.suffix(3).joined(separator: " ")
        if previous != guidanceHeardWords {
            RQLog.block("HEARD-WORDS", "Readable approximation for the top banner", rows: [
                ("verse / cursor", "\(verse.surah):\(verse.ayah) / word[\(word)]"),
                ("raw model phonemes", RQLog.preview(heard, limit: 100)),
                ("nearest Quran word", "word[\(match.index)] \(readableWord(for: match.index, in: verse))"),
                ("similarity", String(format: "%.3f", match.similarity)),
                ("banner text", guidanceHeardWords)
            ], verdict: "APPROXIMATION — the model emits phonemes; the app mapped them to a nearby Quran word")
        }
    }

    /// Converts the model's uncommitted phoneme buffer into the most plausible
    /// nearby Quran word. This is intentionally an approximation, not a claim
    /// that the acoustic model produced an Arabic orthographic transcript.
    static func approximateHeardWordIndex(from heard: String, expectedWords: [String],
                                          around currentWord: Int) -> (index: Int, similarity: Double)? {
        guard !heard.isEmpty, !expectedWords.isEmpty else { return nil }
        let allHeard = QuranNormalizer.chunkPhonemes(heard).compactMap(phonemeBase)
        guard allHeard.count >= 2 else { return nil }
        let heardBases = Array(allHeard.suffix(24))
        let lower = max(0, currentWord - 2)
        let upper = min(expectedWords.count - 1, currentWord + 3)
        guard lower <= upper else { return nil }

        var best: (index: Int, similarity: Double, score: Double)?
        for index in lower...upper {
            let reference = QuranNormalizer.chunkPhonemes(expectedWords[index]).compactMap(phonemeBase)
            guard !reference.isEmpty else { continue }
            let minimumWindow = max(2, reference.count - 2)
            let maximumWindow = min(heardBases.count, reference.count + 2)
            guard minimumWindow <= maximumWindow else { continue }

            for used in minimumWindow...maximumWindow {
                for start in 0...(heardBases.count - used) {
                    let predicted = Array(heardBases[start..<(start + used)])
                    let similarity = phonemeSimilarity(reference, predicted)
                    let trailingNoise = heardBases.count - start - used
                    let distanceFromCursor = abs(index - currentWord)
                    let score = similarity - Double(trailingNoise) * 0.012
                        - Double(distanceFromCursor) * 0.025
                    if best == nil || score > best!.score {
                        best = (index, similarity, score)
                    }
                }
            }
        }
        guard let best, best.similarity >= 0.55 else { return nil }
        return (best.index, best.similarity)
    }

    private static func phonemeBase(_ chunk: String) -> Unicode.Scalar? {
        chunk.unicodeScalars.first
    }

    private static let approximateEquivalentGroups = [
        "ذدضتط", "ظزذصسث", "جزش", "ءأإآاهعحغخ", "ةهت", "ۦي", "ۥو", "ںن۾م", "قكغ", "فبم"
    ]

    private static func approximatelyEqual(_ lhs: Unicode.Scalar, _ rhs: Unicode.Scalar) -> Bool {
        lhs == rhs || approximateEquivalentGroups.contains {
            $0.unicodeScalars.contains(lhs) && $0.unicodeScalars.contains(rhs)
        }
    }

    private static func phonemeSimilarity(_ reference: [Unicode.Scalar],
                                          _ predicted: [Unicode.Scalar]) -> Double {
        guard !reference.isEmpty else { return predicted.isEmpty ? 1 : 0 }
        var previous = Array(0...predicted.count)
        for row in 1...reference.count {
            var current = Array(repeating: 0, count: predicted.count + 1)
            current[0] = row
            for column in 1...predicted.count {
                current[column] = min(
                    previous[column] + 1,
                    current[column - 1] + 1,
                    previous[column - 1] + (approximatelyEqual(reference[row - 1], predicted[column - 1]) ? 0 : 1)
                )
            }
            previous = current
        }
        let distance = previous.last ?? reference.count
        return max(0, 1 - Double(distance) / Double(max(reference.count, predicted.count)))
    }

    private func displayWord(for phonemeIndex: Int, in verse: QuranVerse) -> String {
        guard phonemeIndex >= 0 else { return "" }
        if let uthmaniIndex = verse.wordMap.firstIndex(of: phonemeIndex),
           verse.uthmaniWords.indices.contains(uthmaniIndex) {
            return verse.uthmaniWords[uthmaniIndex]
        }
        return verse.uthmaniWords.indices.contains(phonemeIndex) ? verse.uthmaniWords[phonemeIndex] : ""
    }

    private func readableWord(for phonemeIndex: Int, in verse: QuranVerse) -> String {
        guard phonemeIndex >= 0 else { return "" }
        if let wordIndex = verse.wordMap.firstIndex(of: phonemeIndex),
           verse.readableWords.indices.contains(wordIndex) {
            return verse.readableWords[wordIndex]
        }
        return verse.readableWords.indices.contains(phonemeIndex) ? verse.readableWords[phonemeIndex] : ""
    }

    private func localized(_ english: String, _ arabic: String) -> String {
        AppState.shared.isArabic ? arabic : english
    }
}
