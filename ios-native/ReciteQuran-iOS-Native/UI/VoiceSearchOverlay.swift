import SwiftUI

struct VoiceSearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    let coordinator: RecitationCoordinator

    var body: some View {
        let state = coordinator.appState
        let colors = state.colors
        NavigationStack {
            ZStack {
                colors.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(colors.gold.opacity(0.13))
                            .frame(width: 132, height: 132)
                        Circle()
                            .stroke(colors.gold.opacity(0.28), lineWidth: 1)
                            .frame(width: 164, height: 164)
                        Image(systemName: coordinator.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 46, weight: .medium))
                            .foregroundStyle(colors.gold)
                            .symbolEffect(.variableColor.iterative, options: .repeating,
                                          isActive: coordinator.isRecording)
                    }

                    ScrollView {
                        Text(verbatim: coordinator.voiceSearchHeardWords)
                            .font(.system(size: 38, weight: .semibold, design: .serif))
                            .foregroundStyle(colors.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .environment(\.layoutDirection, .rightToLeft)

                    Spacer()
                    Button {
                        Task {
                            await coordinator.cancelVoiceSearch()
                            dismiss()
                        }
                    } label: {
                        Label(L10n.text(.cancel, language: state.language), systemImage: "xmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(colors.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle(L10n.text(.voiceSearch, language: state.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text(.cancel, language: state.language)) {
                        Task {
                            await coordinator.cancelVoiceSearch()
                            dismiss()
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, state.isArabic ? .rightToLeft : .leftToRight)
        .task { await coordinator.startVoiceSearch() }
        .onChange(of: coordinator.voiceSearchResolved) {
            if coordinator.voiceSearchResolved != nil { dismiss() }
        }
        .onDisappear {
            guard coordinator.isVoiceSearching else { return }
            Task { await coordinator.cancelVoiceSearch() }
        }
    }

}
