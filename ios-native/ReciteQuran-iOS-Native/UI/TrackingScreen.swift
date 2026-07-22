import SwiftUI

struct TrackingScreen: View {
    let coordinator: RecitationCoordinator
    @State private var showSurahs = false
    @State private var showSettings = false
    @State private var showVoiceSearch = false
    @State private var errorSelection: ErrorSelection?
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        let state = coordinator.appState
        let colors = state.colors
        ZStack {
            colors.background.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        Color.clear.frame(height: coordinator.isRecording ? 138 : coordinator.autoScroll ? 12 : 82)
                        ForEach(coordinator.tracking.verses) { verse in
                            VerseRow(verse: verse, tracking: coordinator.tracking, colors: colors,
                                     fontSize: state.fontSize, blurUnread: state.blurMode,
                                     isActive: verse.ayah == coordinator.tracking.activeAyah,
                                     onSelect: { Task { await coordinator.selectAyah(verse.ayah) } },
                                     onError: { errorSelection = $0 })
                            .id(verse.id)
                        }
                        Color.clear.frame(height: 100)
                    }.padding(.horizontal, 10)
                }
                .scrollIndicators(.hidden)
                .onChange(of: coordinator.tracking.activeAyah) {
                    guard let verse = coordinator.tracking.currentVerse else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(verse.id, anchor: .center) }
                }
                .overlay(alignment: .top) {
                    if coordinator.isRecording {
                        RecitationStatusBanner(tracking: coordinator.tracking, colors: colors)
                            .padding(.horizontal, 12).padding(.top, 6)
                    } else if !coordinator.autoScroll {
                        header(proxy: proxy, colors: colors)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    MicBar(isRecording: coordinator.isRecording, isVoiceSearching: coordinator.isVoiceSearching,
                           colors: colors) { Task { await coordinator.toggleRecording() } }
                    .padding(.leading, 22).padding(.bottom, 14)
                }
            }
        }
        .environment(\.layoutDirection, state.isArabic ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showSurahs) {
            SurahPickerSheet(metadata: coordinator.surahMetadata, selected: coordinator.tracking.targetSurah,
                             state: state, onSelect: { surah in Task { await coordinator.selectSurah(surah) } },
                             onVoice: {
                                 showSurahs = false
                                 Task { @MainActor in
                                     try? await Task.sleep(for: .milliseconds(200))
                                     showVoiceSearch = true
                                 }
                             })
                .presentationDetents([.fraction(0.8), .large])
        }
        .fullScreenCover(isPresented: $showVoiceSearch) {
            VoiceSearchScreen(coordinator: coordinator)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(state: state).presentationDetents([.large]) }
        .sheet(item: $errorSelection) { WordErrorSheet(selection: $0, state: state).presentationDetents([.medium, .large]) }
        .alert("Recite Quran", isPresented: Binding(
            get: { coordinator.errorMessage != nil },
            set: { if !$0 { coordinator.errorMessage = nil } }
        )) { Button("OK") { coordinator.errorMessage = nil } } message: { Text(coordinator.errorMessage ?? "") }
    }

    private func header(proxy: ScrollViewProxy, colors: ThemeColors) -> some View {
        HStack(spacing: 9) {
            Button { showSurahs = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "book.closed.fill")
                    Text(currentSurahName).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption)
                }.padding(.horizontal, 14).padding(.vertical, 11)
            }
            Spacer(minLength: 4)
            headerButton(icon: "magnifyingglass", label: .voiceSearch) {
                showVoiceSearch = true
            }
            headerButton(icon: coordinator.appState.blurMode ? "eye.fill" : "eye.slash.fill", label: .hide) {
                coordinator.appState.blurMode.toggle()
            }
            headerButton(icon: coordinator.appState.mode == .tajweed ? "waveform.badge.checkmark" : "waveform", label: .tajweed) {
                Task { await coordinator.toggleTajweed() }
            }
            headerButton(icon: "text.line.first.and.arrowtriangle.forward", label: .read) {
                toggleAutoScroll(proxy: proxy)
            }
            headerButton(icon: "gearshape.fill", label: .settings) { showSettings = true }
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(colors.text)
        .padding(8).background(.ultraThinMaterial, in: .capsule).padding(.horizontal, 12).padding(.top, 6)
    }

    private func headerButton(icon: String, label: L10n.Key, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 34, height: 34) }
            .accessibilityLabel(L10n.text(label, language: coordinator.appState.language))
    }

    private var currentSurahName: String {
        guard let verse = coordinator.tracking.verses.first else { return "" }
        return coordinator.appState.isArabic ? verse.surahName : verse.surahNameEn
    }

    private func toggleAutoScroll(proxy: ScrollViewProxy) {
        coordinator.autoScroll.toggle(); scrollTask?.cancel()
        guard coordinator.autoScroll else { return }
        let verses = coordinator.tracking.verses
        let speed = [0.5, 1, 1.5, 2, 2.5][min(4, max(0, coordinator.appState.autoScrollSpeed))]
        scrollTask = Task {
            for verse in verses {
                if Task.isCancelled { return }
                await MainActor.run { withAnimation(.linear(duration: 1.2 / speed)) { proxy.scrollTo(verse.id, anchor: .center) } }
                try? await Task.sleep(for: .seconds(2.2 / speed))
            }
            await MainActor.run { coordinator.autoScroll = false }
        }
    }
}

private struct RecitationStatusBanner: View {
    let tracking: TrackingViewModel
    let colors: ThemeColors

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.13), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(tracking.guidanceTitle)
                        .font(.subheadline.weight(.bold))
                    if !tracking.guidanceTargetWord.isEmpty {
                        Text(tracking.guidanceTargetWord)
                            .font(.custom(FontRegistrar.fontName, size: 21, relativeTo: .title3))
                            .environment(\.layoutDirection, .rightToLeft)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                Text(tracking.guidanceDetail)
                    .font(.caption)
                    .foregroundStyle(colors.muted).lineLimit(2)
                if !tracking.guidanceHeardWords.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tracking.guidanceHeardLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(colors.muted)
                        Text(tracking.guidanceHeardWords)
                            .font(.custom(FontRegistrar.fontName, size: 18, relativeTo: .body))
                            .environment(\.layoutDirection, .rightToLeft)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(colors.text)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.22)) }
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        switch tracking.guidanceTone {
        case .listening: colors.gold
        case .success: colors.green
        case .warning: colors.red
        }
    }
    private var icon: String {
        switch tracking.guidanceTone {
        case .listening: "waveform"
        case .success: "checkmark.circle.fill"
        case .warning: "arrow.counterclockwise.circle.fill"
        }
    }
}
