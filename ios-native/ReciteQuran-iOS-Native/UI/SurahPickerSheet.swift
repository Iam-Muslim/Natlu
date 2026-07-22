import SwiftUI

struct SurahPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let metadata: [QuranVerse]
    let selected: Int
    let state: AppState
    let onSelect: (Int) -> Void
    let onVoice: () -> Void
    private var filtered: [QuranVerse] {
        guard !query.isEmpty else { return metadata }
        return metadata.filter { $0.surahName.localizedCaseInsensitiveContains(query) ||
            $0.surahNameEn.localizedCaseInsensitiveContains(query) || String($0.surah).contains(query) }
    }
    var body: some View {
        NavigationStack {
            List(filtered) { verse in
                Button {
                    onSelect(verse.surah); dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(arabicDigits(verse.surah)).frame(width: 42, height: 42)
                            .background(state.colors.gold.opacity(0.12), in: .circle)
                        VStack(alignment: .leading) {
                            Text(verse.surahName).font(.custom(FontRegistrar.fontName, size: 22))
                            Text(verse.surahNameEn).font(.caption).foregroundStyle(state.colors.muted)
                        }
                        Spacer()
                        if verse.surah == selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(state.colors.gold) }
                    }.foregroundStyle(state.colors.text)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(state.colors.background)
            .searchable(text: $query, prompt: L10n.text(.searchSurah, language: state.language))
            .navigationTitle(L10n.text(.chooseSurah, language: state.language))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onVoice(); dismiss() } label: { Image(systemName: "waveform.circle.fill").font(.title2) }
                        .accessibilityLabel(L10n.text(.voiceSearch, language: state.language))
                }
            }
        }
    }
}
