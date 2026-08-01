import Observation
import SwiftUI

struct SelfTestResult: Identifiable, Equatable {
    let id: String, name: String, passed: Bool, detail: String
}

@MainActor @Observable
final class SelfTestRunner {
    private(set) var results: [SelfTestResult] = []
    private(set) var running = false
    private let repository = QuranRepository()

    func run() async {
        guard !running else { return }; running = true; results = []
        await check("T0", "Bundle resources + Hafs font") {
            try FontRegistrar.register()
            let names = ["ordered_quran_phonemes.json", "ph_index.npy", "zipformer_p_arabic_v2.int8.onnx", "ref_norm_ph.txt", "silero_vad.onnx", "tokens.txt"]
            return names.allSatisfy { BundleResources.url($0) != nil } && FontRegistrar.fontName == "KFGQPCHafsSmart-Regular"
        }
        await check("T1", "NPY index shape") {
            let search = PhoneticSearch(); try await search.load()
            let header = await search.headerLength, offset = await search.dataOffset, rows = await search.rowCount()
            return header == 118 && offset == 128 && rows == 311_886
        }
        await check("T2", "Quran JSON integrity") {
            try await repository.load(); let verses = await repository.verses()
            let first = await repository.verse(surah: 1, ayah: 1)
            let bmp = verses.allSatisfy { $0.textPhoneme.unicodeScalars.allSatisfy { $0.value <= 0xffff } }
            return verses.count == 6_236 && first?.phonemeWords.count == 4 &&
                first?.ayahMarker.isEmpty == false && bmp
        }
        await check("T3", "Phoneme chunking") {
            let input = "بِسمِللَاا", chunks = QuranNormalizer.chunkPhonemes("بِسمِللَاا")
            return chunks.joined() == input && !chunks.isEmpty
        }
        await check("T4", "Aligner happy path") {
            let words = ["بِسمِ", "للَااهِ", "ررَحمَاانِ", "ررَحِۦۦۦۦم"]
            let partialAligner = PhonemeAligner()
            await partialAligner.setVerse(words, tajweed: false)
            let earlyPartial = await partialAligner.feed("ب")
            let aligner = PhonemeAligner()
            await aligner.setVerse(words, tajweed: false)
            let events = await aligner.feed(words.joined())
            let highlights = events.compactMap { event -> (Int, Bool)? in if case .highlight(let id, let red, _, _) = event { return (id, red) }; return nil }
            let earlyPartialIsWaiting = earlyPartial.contains {
                if case .waiting(let id, _, _, let enoughAudio) = $0 {
                    return id == 0 && !enoughAudio
                }
                return false
            }
            return earlyPartialIsWaiting && highlights.map(\.0) == [0, 1, 2, 3] && highlights.allSatisfy { !$0.1 }
        }
        await check("T5", "Aligner skipped-word detection") {
            let aligner = PhonemeAligner(), words = ["بِسمِ", "للَااهِ", "ررَحمَاانِ", "ررَحِۦۦۦۦم"]
            await aligner.setVerse(words, tajweed: false)
            let events = await aligner.feed(words[0] + words[2] + words[3])
            let skipped = events.contains { if case .highlight(let id, let red, _, _) = $0 { return id == 1 && red }; return false }

            // Exact device regression: the 60% first-word match leaves `مدُ`
            // before Allah. Sliding must skip that tail and find word 1.
            let transitionAligner = PhonemeAligner()
            let secondAyah = ["ءَلحَمدُ", "لِللَااهِ", "رَببِ", "لعَاالَمِۦۦن"]
            await transitionAligner.setVerse(secondAyah, tajweed: false, label: "device-regression")
            _ = await transitionAligner.feed("ءَلحَ")
            let transitionEvents = await transitionAligner.feed("مدُلِللَااهِرَببِلعَاالَمِۦۦن")
            let foundAllah = transitionEvents.contains {
                if case .highlight(let id, let red, _, _) = $0 { return id == 1 && !red }
                return false
            }
            return skipped && foundAllah
        }
        await check("T6", "Error explainer") {
            return ErrorExplainer.explain(expected: "بِت", predicted: "بِت").isEmpty &&
            ErrorExplainer.explain(expected: "بِت", predicted: "بَت").contains { $0.category == .tashkeel }
        }
        await check("T7", "Voice search 112:1") {
            guard let verse = await repository.verse(surah: 112, ayah: 1) else { return false }
            let search = PhoneticSearch(); let result = try await search.search(verse.textPhoneme, errorRatio: 0.18).first
            return result?.start.surah == 112 && result?.start.ayah == 1
        }
        await check("T8", "Recognizer model + silence") {
            let engine = SherpaEngine(); try await engine.initialize()
            _ = try await engine.transcribe(Array(repeating: 0, count: 16_000), isFinal: true)
            return await engine.isInitialized
        }
        await check("T9", "Silero VAD + zeros") {
            let model = try BundleResources.requiredURL("silero_vad", extension: "onnx").path
            let silero = sherpaOnnxSileroVadModelConfig(model: model, threshold: 0.1, minSilenceDuration: 0.1, minSpeechDuration: 0.15, maxSpeechDuration: 1_000)
            var config = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: 16_000, numThreads: 1)
            let vad = withUnsafePointer(to: &config) { SherpaOnnxVoiceActivityDetectorWrapper(config: $0, buffer_size_in_seconds: 10) }
            vad.acceptWaveform(samples: Array(repeating: 0, count: 16_000))
            return !vad.isSpeechDetected()
        }
        await check("T10", "Fuzzy search offsets") {
            return FuzzySearch.nearMatches(query: "abc", in: "xxabczz", maxDistance: 0).first == .init(start: 2, end: 5, distance: 0) &&
            FuzzySearch.nearMatches(query: "abc", in: "xxaxczz", maxDistance: 1).first?.distance == 1
        }
        await check("T11", "Continuous two-ayah tracking pipeline") {
            let vm = TrackingViewModel(repository: repository); await vm.setSurah(1); vm.startTracking()
            guard let first = vm.currentVerse else { return false }
            await vm.handle(.init(text: first.textPhoneme), tajweed: false)
            try? await Task.sleep(for: .milliseconds(100))
            guard vm.activeAyah == 2, let second = vm.currentVerse else { return false }
            // Sherpa partials are cumulative inside one uninterrupted segment.
            // Ayah 2 must receive only the suffix after the preserved ayah-1 cursor.
            await vm.handle(.init(text: first.textPhoneme + second.textPhoneme), tajweed: false)
            try? await Task.sleep(for: .milliseconds(100))
            return vm.greenWords[1]?.count == first.phonemeWords.count &&
                vm.greenWords[2]?.count == second.phonemeWords.count && vm.activeAyah == 3
        }
        await check("T12", "Manual ayah restart keeps cursor and highlight aligned") {
            let vm = TrackingViewModel(repository: repository)
            await vm.setSurah(2, ayah: 2)
            vm.startTracking()
            guard let verse = vm.currentVerse, verse.phonemeWords.count > 5,
                  let firstDisplayIndex = verse.wordMap.firstIndex(of: 0) else { return false }

            await vm.handle(.init(text: verse.phonemeWords.prefix(5).joined()), tajweed: false)
            guard vm.currentWord(in: verse) == 5 else { return false }

            await vm.setManualAyah(2)
            return vm.currentWord(in: verse) == 0 &&
                (vm.greenWords[2]?.isEmpty ?? true) &&
                (vm.redWords[2]?.isEmpty ?? true) &&
                (vm.yellowWords[2]?.isEmpty ?? true) &&
                vm.guidanceTargetWord == verse.uthmaniWords[firstDisplayIndex] &&
                vm.recognizedText.isEmpty
        }
        await check("T13", "Al-Kahf hidden-Noon Tajweed diagnostic") {
            let anzala = "ءَںںںزَلَ"
            let durations = Array(repeating: 0.10, count: anzala.unicodeScalars.count)
            let errors = ErrorExplainer.explain(expected: anzala, predicted: anzala,
                                                durations: durations)
            let ghunnah = errors.first { $0.rule?.kind == .ghunnah }
            let missingTimestampErrors = ErrorExplainer.explain(expected: anzala,
                                                                predicted: anzala)
            return ghunnah?.expected == ghunnah?.predicted &&
                ghunnah?.expectedDuration == TajweedDurations.ghunnah &&
                PhoneticDisplay.baseLetter(ghunnah?.expected ?? "") == "ن" &&
                !errors.contains(where: { $0.category == .normal }) &&
                missingTimestampErrors.isEmpty
        }
        await check("T14", "Tajweed waits for final ayah phoneme") {
            let rahimAligner = PhonemeAligner()
            await rahimAligner.setVerse(["ررَحِۦۦۦۦم"], tajweed: true,
                                        label: "terminal-meem-regression")
            let prematureRahim = await rahimAligner.feed("ررَحِۦۦ")
            let completedRahim = await rahimAligner.feed("م", isFinal: true)

            let alaminAligner = PhonemeAligner()
            await alaminAligner.setVerse(["لعَاالَمِۦۦۦۦن"], tajweed: true,
                                         label: "terminal-noon-regression")
            let prematureAlamin = await alaminAligner.feed("لعَاالَمِۦۦ")
            let completedAlamin = await alaminAligner.feed("ن", isFinal: true)

            func completed(_ events: [AlignerEvent]) -> Bool {
                events.contains { if case .ayahCompleted = $0 { return true }; return false }
            }
            return !completed(prematureRahim) && completed(completedRahim) &&
                !completed(prematureAlamin) && completed(completedAlamin)
        }
        await check("T15", "Madd repetition is timing-only feedback") {
            let passed = ErrorExplainer.explain(expected: "ۦۦۦۦ", predicted: "ۦۦ",
                                                durations: [0.55, 0.55])
            let tooShort = ErrorExplainer.explain(expected: "ۦۦۦۦ", predicted: "ۦۦ",
                                                  durations: [0.10, 0.10])
            return passed.isEmpty &&
                tooShort.contains(where: { $0.category == .tajweed }) &&
                !tooShort.contains(where: { $0.category == .tashkeel })
        }
        await check("T16", "Adaptive recitation pace profile") {
            var estimator = RecitationPaceEstimator()
            estimator.reset(reason: "self-test")
            for index in 0..<8 {
                estimator.observe(expected: "حَ", predicted: "حَ",
                                  durations: [0.08, 0.08],
                                  verseLabel: "test", wordIndex: index)
            }
            let timing = estimator.profile
            let naturalTarget = timing.targetDuration(for: .normalMadd)
            let naturalMinimum = timing.minimumDuration(for: .normalMadd)
            return timing.isAdaptive && timing.sampleCount == 8 &&
                abs(timing.harakah - 0.16) < 0.001 &&
                abs(naturalTarget - 0.24) < 0.001 &&
                abs(naturalMinimum - 0.14) < 0.001
        }
        await check("T17", "Model omissions remain provisional") {
            let droppedPhonemes = ErrorExplainer.explain(
                expected: "ءَلحَمدُ",
                predicted: "لحَدُ"
            )
            let positiveSubstitution = ErrorExplainer.explain(
                expected: "سَ",
                predicted: "شَ"
            )
            return droppedPhonemes.isEmpty &&
                positiveSubstitution.contains { $0.action == .replace }
        }
        await check("T18", "Tajweed recovers without grading a lost word") {
            let aligner = PhonemeAligner()
            let words = ["ءَلحَمدُ", "لِللَااهِ", "رَببِ"]
            await aligner.setVerse(words, tajweed: true, label: "uncertain-recovery")
            let events = await aligner.feed(words[1] + words[2])
            let firstIsUncertain = events.contains {
                if case .uncertain(let id) = $0 { return id == 0 }
                return false
            }
            let recoveredAtSecond = events.contains {
                if case .highlight(let id, let red, _, _) = $0 { return id == 1 && !red }
                return false
            }
            return firstIsUncertain && recoveredAtSecond
        }
        await check("T19", "Final ayah word waits for endpoint ownership") {
            let aligner = PhonemeAligner()
            let finalWord = "ررَحِۦۦۦۦم"
            await aligner.setVerse([finalWord], tajweed: true,
                                   label: "endpoint-ownership")
            let partial = await aligner.feed(finalWord)
            let final = await aligner.feed("", isFinal: true)
            func completed(_ events: [AlignerEvent]) -> Bool {
                events.contains { if case .ayahCompleted = $0 { return true }; return false }
            }
            return !completed(partial) && completed(final)
        }
        await check("T20", "Connected ayahs advance with continuation proof") {
            let aligner = PhonemeAligner()
            let finalWord = "ررَحِۦۦۦۦم"
            let continuation = ["مَاالِكِ", "يَومِ"]
            await aligner.setVerse([finalWord], tajweed: true,
                                   label: "connected-ayahs",
                                   continuationWords: continuation)
            let events = await aligner.feed(finalWord + continuation.joined())
            return events.contains { if case .ayahCompleted = $0 { return true }; return false }
        }
        await check("T21", "Ayah-ending harakah is optional") {
            let stopped = ErrorExplainer.explainAyah(
                expectedWords: ["ررَحِۦۦۦۦمِ"],
                predictedWords: ["ررَحِۦۦۦۦم"],
                predictedDurations: [[]],
                verseLabel: "waqf"
            )
            let connected = ErrorExplainer.explainAyah(
                expectedWords: ["ررَحِۦۦۦۦم"],
                predictedWords: ["ررَحِۦۦۦۦمِ"],
                predictedDurations: [[]],
                verseLabel: "wasl"
            )
            return stopped.isEmpty && connected.isEmpty
        }
        await check("T22", "Final ASR endpoint remains owned by ayah 1:3") {
            let previousMode = AppState.shared.mode
            AppState.shared.mode = .tajweed
            defer { AppState.shared.mode = previousMode }

            let vm = TrackingViewModel(repository: repository)
            await vm.setSurah(1, ayah: 3)
            vm.startTracking()
            guard let verse = vm.currentVerse else { return false }

            await vm.handle(.init(text: verse.textPhoneme, isFinal: false), tajweed: true)
            try? await Task.sleep(for: .milliseconds(100))
            guard vm.activeAyah == 3 else { return false }

            await vm.handle(.init(text: verse.textPhoneme, isFinal: true), tajweed: true)
            try? await Task.sleep(for: .milliseconds(100))
            return vm.activeAyah == 4
        }
        await check("T23", "Stopped endpoint discards recognizer carryover") {
            let aligner = PhonemeAligner()
            let finalWord = "ررَحِۦۦۦۦم"
            await aligner.setVerse([finalWord], tajweed: true,
                                   label: "stopped-carryover")
            let events = await aligner.feed(finalWord + "خَ", isFinal: true)
            return events.contains {
                if case .ayahCompleted(_, _, let preserveCarryover) = $0 {
                    return !preserveCarryover
                }
                return false
            }
        }
        await check("T24", "A new ayah cannot bypass its first word") {
            let aligner = PhonemeAligner()
            let words = ["خَتَمَ", "وَلَهُم", "عَذَاابُن"]
            await aligner.setVerse(words, tajweed: true,
                                   label: "first-word-anchor")
            let events = await aligner.feed(words[1] + words[2], isFinal: true)
            return !events.contains {
                switch $0 {
                case .uncertain(let id): return id == 0
                case .highlight(let id, _, _, _): return id > 0
                default: return false
                }
            }
        }
        await check("T25", "Cross-surah advance clears prior colors") {
            let previousMode = AppState.shared.mode
            AppState.shared.mode = .wordChecker
            defer { AppState.shared.mode = previousMode }

            let vm = TrackingViewModel(repository: repository)
            await vm.setSurah(1, ayah: 7)
            vm.startTracking()
            guard let verse = vm.currentVerse else { return false }
            await vm.handle(.init(text: verse.textPhoneme, isFinal: true), tajweed: false)
            try? await Task.sleep(for: .milliseconds(100))
            return vm.targetSurah == 2 && vm.activeAyah == 1 &&
                vm.greenWords.isEmpty && vm.redWords.isEmpty &&
                vm.yellowWords.isEmpty && vm.uncertainWords.isEmpty &&
                vm.errors.isEmpty
        }
        await check("T26", "Manual selection clears selected and next ayah only") {
            let previousMode = AppState.shared.mode
            AppState.shared.mode = .wordChecker
            defer { AppState.shared.mode = previousMode }

            let vm = TrackingViewModel(repository: repository)
            await vm.setSurah(1)
            vm.startTracking()
            for expectedAyah in 1...4 {
                guard let verse = vm.currentVerse, verse.ayah == expectedAyah else { return false }
                await vm.handle(.init(text: verse.textPhoneme, isFinal: true), tajweed: false)
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard vm.greenWords[1]?.isEmpty == false,
                  vm.greenWords[2]?.isEmpty == false,
                  vm.greenWords[3]?.isEmpty == false,
                  vm.greenWords[4]?.isEmpty == false else { return false }

            await vm.setManualAyah(2)
            return vm.activeAyah == 2 &&
                vm.greenWords[1]?.isEmpty == false &&
                vm.greenWords[2] == nil && vm.greenWords[3] == nil &&
                vm.greenWords[4]?.isEmpty == false &&
                vm.errors[2] == nil && vm.errors[3] == nil
        }
        await check("T27", "Natural Madd accepts timestamp-tolerant pace floor") {
            let timing = TajweedTimingProfile(
                harakah: 0.16,
                graceFraction: 0.15,
                timestampAllowance: 0.02,
                sampleCount: 8,
                isAdaptive: true
            )
            let minimum = timing.minimumDuration(for: .normalMadd)
            let accepted = ErrorExplainer.explain(
                expected: "اا",
                predicted: "اا",
                durations: [0.07, 0.07],
                timing: timing
            )
            return abs(minimum - 0.14) < 0.001 && accepted.isEmpty
        }
        await check("T28", "Only Natural Madd timing feedback is gold") {
            let timing = TajweedTimingProfile(
                harakah: 0.16,
                graceFraction: 0.15,
                timestampAllowance: 0.02,
                sampleCount: 8,
                isAdaptive: true
            )
            let naturalMadd = ErrorExplainer.explain(
                expected: "اا",
                predicted: "اا",
                durations: [0.05, 0.05],
                timing: timing
            )
            let vowelError = ErrorExplainer.explain(
                expected: "بِت",
                predicted: "بَت",
                timing: timing
            )
            return !naturalMadd.isEmpty && !vowelError.isEmpty &&
                TrackingViewModel.gradeTone(for: naturalMadd) == .gold &&
                TrackingViewModel.gradeTone(for: vowelError) == .red &&
                TrackingViewModel.gradeTone(for: naturalMadd + vowelError) == .red
        }
        await check("T29", "Phoneme buffer maps to a readable nearby Quran word") {
            guard let verse = await repository.verse(surah: 2, ayah: 2),
                  verse.phonemeWords.indices.contains(3) else { return false }
            let exact = TrackingViewModel.approximateHeardWordIndex(
                from: verse.phonemeWords[3],
                expectedWords: verse.phonemeWords,
                around: 3
            )
            let partialChunks = QuranNormalizer.chunkPhonemes(verse.phonemeWords[3])
            let partial = TrackingViewModel.approximateHeardWordIndex(
                from: partialChunks.dropLast().joined(),
                expectedWords: verse.phonemeWords,
                around: 3
            )
            return exact?.index == 3 && partial?.index == 3 &&
                (exact?.similarity ?? 0) >= (partial?.similarity ?? 0)
        }
        await check("T30", "Voice search tolerates model errors and confirms a unique ayah twice") {
            guard let verse = await repository.verse(surah: 18, ayah: 1),
                  verse.phonemeWords.count >= 7 else { return false }
            let controller = VoiceSearchController()
            try await controller.startSession()
            let short = try await controller.assess("قُل")
            var firstPhrase = verse.phonemeWords.prefix(5).joined()
            if let index = firstPhrase.indices.dropFirst(2).first {
                firstPhrase.remove(at: index)
            }
            let first = try await controller.assess(firstPhrase)
            let second = try await controller.assess(verse.phonemeWords.prefix(7).joined())
            guard short == .needsMoreAudio else { return false }
            guard case .confirming(let firstAnchor) = first,
                  firstAnchor == AnchorResult(surah: 18, ayah: 1) else { return false }
            if case .unique(let anchor) = second {
                guard anchor == AnchorResult(surah: 18, ayah: 1) else { return false }
            } else {
                return false
            }

            // Regression: this is the actual short Al-Ikhlas output seen from
            // the model. It normalizes to only ten phonemes, so a twelve-sound
            // minimum made the search silently ignore the complete ayah.
            let shortController = VoiceSearchController()
            try await shortController.startSession()
            let shortPartial = try await shortController.assess("قُلهُوَللَااهُءَحَ")
            let shortFinal = try await shortController.assess("قُلهُوَللَااهُءَحَدڇ", isFinal: true)
            guard case .confirming(let shortAnchor) = shortPartial,
                  shortAnchor == AnchorResult(surah: 112, ayah: 1) else { return false }
            if case .unique(let finalAnchor) = shortFinal {
                return finalAnchor == AnchorResult(surah: 112, ayah: 1)
            }
            return false
        }
        await check("T31", "Voice search identifies ordered Quran words while skipped words are allowed") {
            guard let verse = await repository.verse(surah: 18, ayah: 1),
                  verse.phonemeWords.count >= 8 else { return false }
            let controller = VoiceSearchController()
            await controller.configure(verses: await repository.verses())
            try await controller.startSession()

            // Skip عَلَىٰ and عَبْدِهِ entirely. The surviving ordered anchors
            // still identify Al-Kahf 18:1 without requiring a contiguous phrase.
            let firstQuery = [0, 1, 2, 3, 6].map { verse.phonemeWords[$0] }.joined()
            let secondQuery = [0, 1, 2, 3, 6, 7].map { verse.phonemeWords[$0] }.joined()
            let first = try await controller.assess(firstQuery)
            let second = try await controller.assess(secondQuery)
            guard case .confirming(let firstAnchor) = first,
                  firstAnchor == AnchorResult(surah: 18, ayah: 1) else { return false }
            if case .unique(let finalAnchor) = second {
                return finalAnchor == AnchorResult(surah: 18, ayah: 1)
            }
            return false
        }
        running = false
        print("SELFTEST RESULT: \(results.filter(\.passed).count)/\(results.count)")
    }

    private func check(_ id: String, _ name: String, operation: () async throws -> Bool) async {
        do {
            let passed = try await operation()
            results.append(.init(id: id, name: name, passed: passed, detail: passed ? "PASS" : "FAIL"))
            print("SELFTEST \(passed ? "PASS" : "FAIL") \(id) \(name)")
        } catch {
            results.append(.init(id: id, name: name, passed: false, detail: error.localizedDescription))
            print("SELFTEST FAIL \(id) \(name): \(error)")
        }
    }
}

struct SelfTestView: View {
    @State private var runner = SelfTestRunner()
    var body: some View {
        NavigationStack {
            List(runner.results) { result in
                HStack {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.passed ? .green : .red)
                    VStack(alignment: .leading) { Text("\(result.id) · \(result.name)"); Text(result.detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .overlay { if runner.running && runner.results.isEmpty { ProgressView("Running self-tests…") } }
            .navigationTitle("Self Tests \(runner.results.filter(\.passed).count)/\(runner.results.count)")
        }.task { await runner.run() }
    }
}
