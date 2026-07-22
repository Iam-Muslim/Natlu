import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: AppState
    var body: some View {
        @Bindable var state = state
        VStack(spacing: 24) {
            Capsule().fill(state.colors.muted.opacity(0.35)).frame(width: 42, height: 5).padding(.top, 10)
            HStack {
                Button(L10n.text(.done, language: state.language)) { dismiss() }
                Spacer()
                Text(L10n.text(.settings, language: state.language)).font(.title3.bold())
            }
            settingTitle(.fontSize)
            HStack { Text("16"); Slider(value: $state.fontSize, in: 16...42, step: 1).tint(state.colors.gold); Text("42") }
            settingTitle(.scrollSpeed)
            pillRow(values: ["0.5x", "1x", "1.5x", "2x", "2.5x"], selection: state.autoScrollSpeed) { state.autoScrollSpeed = $0 }
            settingTitle(.language)
            HStack {
                choice("عربي", active: state.language == .ar) { state.language = .ar }
                choice("English", active: state.language == .en) { state.language = .en }
            }
            settingTitle(.theme)
            HStack {
                choice(L10n.text(.light, language: state.language), active: state.theme == .light) { state.theme = .light }
                choice(L10n.text(.dark, language: state.language), active: state.theme == .dark) { state.theme = .dark }
            }
            Spacer()
            Text("رَبِّ زِدْنِي عِلْمًا").font(.custom(FontRegistrar.fontName, size: 25)).foregroundStyle(state.colors.gold)
        }
        .padding(.horizontal, 22).padding(.bottom, 26)
        .background(state.colors.background)
    }
    private func settingTitle(_ key: L10n.Key) -> some View {
        Text(L10n.text(key, language: state.language)).font(.headline).frame(maxWidth: .infinity, alignment: .trailing)
    }
    private func choice(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(active ? state.colors.gold : state.colors.surfaceHigh, in: .capsule)
            .foregroundStyle(active ? .white : state.colors.text)
    }
    private func pillRow(values: [String], selection: Int, action: @escaping (Int) -> Void) -> some View {
        HStack { ForEach(values.indices, id: \.self) { index in choice(values[index], active: selection == index, action: { action(index) }) } }
    }
}
