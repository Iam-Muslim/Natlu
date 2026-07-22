import Observation
import UIKit

enum VoiceSearchFeedback: Equatable {
    case idle
    case listening
    case needsMoreAudio
    case noExactMatch
    case ambiguous(uniqueAyahs: Int)
    case confirming(AnchorResult)
    case confirmed(AnchorResult)
}

@MainActor @Observable
final class RecitationCoordinator {
    let appState = AppState.shared
    let repository = QuranRepository()
    let engine = SherpaEngine()
    let audio = AudioProcessor()
    let voiceSearch = VoiceSearchController()
    private(set) var tracking: TrackingViewModel
    private(set) var surahMetadata: [QuranVerse] = []
    private(set) var isReady = false
    private(set) var isRecording = false
    private(set) var isVoiceSearching = false
    private(set) var voiceText = ""
    private(set) var voiceSearchHeardWords = ""
    private(set) var voiceSearchFeedback: VoiceSearchFeedback = .idle
    private(set) var voiceSearchResolved: AnchorResult?
    private(set) var status = ""
    var errorMessage: String?
    var autoScroll = false
    private var audioTask: Task<Void, Never>?
    private var toggling = false

    init() { tracking = TrackingViewModel(repository: repository) }

    func initialize() async {
        guard !isReady else { return }
        status = L10n.text(.loading, language: appState.language)
        do {
            try FontRegistrar.register()
            try await repository.load()
            await voiceSearch.configure(verses: await repository.verses())
            surahMetadata = await repository.surahMetadata()
            await tracking.setSurah(1)
            try audio.initializeVAD()
            Task.detached { [engine, voiceSearch] in
                try? await engine.initialize()
                try? await voiceSearch.preload()
            }
            isReady = true
        } catch { errorMessage = error.localizedDescription }
    }

    func selectSurah(_ surah: Int, ayah: Int = 1) async {
        if isRecording { await toggleRecording() }
        audio.resetForNavigation()
        await engine.reset()
        voiceText = ""
        isVoiceSearching = false
        autoScroll = false
        await tracking.setSurah(surah, ayah: ayah)
    }

    func selectAyah(_ ayah: Int) async {
        guard !toggling else { return }
        toggling = true
        defer { toggling = false }

        let resumeRecording = isRecording
        if resumeRecording {
            audio.stop(finalize: false)
            audioTask?.cancel()
            audioTask = nil
            isRecording = false
        }

        audio.resetForNavigation()
        await engine.reset()
        voiceText = ""
        await tracking.setManualAyah(ayah)

        guard resumeRecording else { return }
        do {
            let events = try await audio.start()
            isRecording = true
            UIApplication.shared.isIdleTimerDisabled = true
            beginAudioLoop(events: events)
            RQLog.write("FLOW", "recording restarted with clean buffers after manual ayah selection")
        } catch {
            tracking.stopTracking()
            UIApplication.shared.isIdleTimerDisabled = false
            errorMessage = error.localizedDescription
            RQLog.write("ERROR", "failed to restart recording after ayah selection: \(error)")
        }
    }

    func toggleRecording() async {
        guard !toggling else { return }; toggling = true; defer { toggling = false }
        if isRecording {
            let wasVoiceSearching = isVoiceSearching
            RQLog.write("AUDIO", "stop requested")
            audio.stop()
            audioTask?.cancel(); audioTask = nil
            await engine.reset()
            isRecording = false; isVoiceSearching = false
            if !wasVoiceSearching { tracking.stopTracking() }
            UIApplication.shared.isIdleTimerDisabled = false
            RQLog.write("AUDIO", "recording stopped; recognizer reset for the next session")
            return
        }
        do {
            RQLog.write("AUDIO", "start requested")
            try await engine.initialize()
            let events = try await audio.start()
            isRecording = true
            if !isVoiceSearching { tracking.startTracking() }
            UIApplication.shared.isIdleTimerDisabled = true
            beginAudioLoop(events: events)
            RQLog.write("AUDIO", "recording started; audio event loop active")
        } catch { RQLog.write("ERROR", "recording start failed: \(error)"); errorMessage = error.localizedDescription }
    }

    func startVoiceSearch() async {
        if isRecording { await toggleRecording() }
        voiceText = ""
        voiceSearchHeardWords = ""
        voiceSearchFeedback = .listening
        voiceSearchResolved = nil
        do {
            try await voiceSearch.startSession()
        } catch {
            voiceSearchFeedback = .idle
            errorMessage = error.localizedDescription
            RQLog.write("ERROR", "voice search index failed to load: \(error)")
            return
        }
        isVoiceSearching = true
        await engine.reset()
        await toggleRecording()
        if !isRecording {
            isVoiceSearching = false
            voiceSearchFeedback = .idle
        }
    }

    func cancelVoiceSearch() async {
        guard isVoiceSearching else { return }
        if isRecording { await toggleRecording() }
        isVoiceSearching = false
        voiceText = ""
        voiceSearchHeardWords = ""
        voiceSearchFeedback = .idle
        RQLog.write("VOICE-SEARCH", "cancelled without navigation")
    }

    func toggleTajweed() async {
        appState.mode = appState.mode == .tajweed ? .wordChecker : .tajweed
        await tracking.setTajweed(appState.mode == .tajweed)
    }

    private func beginAudioLoop(events: AsyncStream<AudioEvent>) {
        audioTask?.cancel()
        audioTask = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                if Task.isCancelled { break }
                do {
                    let result: TranscriptionResult
                    switch event {
                    case .samples(let samples): result = try await engine.transcribe(samples)
                    case .endpoint:
                        RQLog.write("AUDIO", "VAD endpoint received; finalizing ASR segment")
                        result = try await engine.transcribe([], isFinal: true)
                    }
                    if isVoiceSearching {
                        voiceText = result.text
                        let assessment = try await voiceSearch.assess(result.text, isFinal: result.isFinal)
                        voiceSearchHeardWords = await voiceSearch.heardWords().joined(separator: " ")
                        switch assessment {
                        case .needsMoreAudio:
                            voiceSearchFeedback = .needsMoreAudio
                        case .noExactMatch:
                            voiceSearchFeedback = .noExactMatch
                        case .ambiguous(let count):
                            voiceSearchFeedback = .ambiguous(uniqueAyahs: count)
                        case .confirming(let match):
                            voiceSearchFeedback = .confirming(match)
                        case .unique(let match):
                            voiceSearchFeedback = .confirmed(match)
                            if isRecording { await toggleRecording() }
                            await selectSurah(match.surah, ayah: match.ayah)
                            voiceSearchResolved = match
                            break
                        }
                    } else { await tracking.handle(result, tajweed: appState.mode == .tajweed) }
                } catch { RQLog.write("ERROR", "audio/ASR loop failed: \(error)"); errorMessage = error.localizedDescription }
            }
        }
    }
}
