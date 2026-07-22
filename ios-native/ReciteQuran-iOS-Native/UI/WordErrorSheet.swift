import SwiftUI

struct WordErrorSheet: View {
    let selection: ErrorSelection
    let state: AppState
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(state.colors.muted.opacity(0.35)).frame(width: 42, height: 5)
                Text(selection.word).font(.custom(FontRegistrar.fontName, size: 38)).foregroundStyle(state.colors.currentWord)
                    .padding().frame(maxWidth: .infinity).background(state.colors.surfaceHigh, in: .rect(cornerRadius: 18))
                Text("\(L10n.text(.errorDetails, language: state.language)) (\(selection.errors.count))").font(.headline)
                ForEach(selection.errors) { error in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: icon(error.category))
                            Text(title(error)).font(.headline)
                            Spacer()
                            Text(action(error)).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(accent(error.category).opacity(0.14), in: .capsule)
                        }
                        if let expected = error.expectedDuration, let actual = error.actualDuration {
                            Text(durationExplanation(actual: actual, expected: expected))
                                .font(.subheadline).foregroundStyle(state.colors.muted)
                            ProgressView(value: min(actual / expected, 1)).tint(accent(error.category))
                            Text("\(actual, format: .number.precision(.fractionLength(2)))s / \(expected, format: .number.precision(.fractionLength(2)))s").font(.caption)
                        }
                        if isSameDurationPhoneme(error) {
                            HStack {
                                Text(state.isArabic ? "الصوت" : "Sound").foregroundStyle(state.colors.muted)
                                Spacer()
                                Text(PhoneticDisplay.baseLetter(error.expected))
                                    .foregroundStyle(state.colors.text)
                                    .environment(\.layoutDirection, .rightToLeft)
                            }.font(.system(size: 24, weight: .semibold))
                        } else {
                            HStack {
                                Text(displayPhoneme(error.expected)).foregroundStyle(state.colors.green)
                                Image(systemName: "arrow.left")
                                Text(displayPhoneme(error.predicted)).foregroundStyle(state.colors.red)
                            }
                            .font(.system(size: 25, weight: .semibold))
                            .environment(\.layoutDirection, .rightToLeft)
                        }
                    }.padding().background(state.colors.surface, in: .rect(cornerRadius: 16))
                }
            }.padding(22)
        }
        .background(state.colors.background)
        .task { logDisplayedPayload() }
    }
    private func accent(_ category: ErrorCategory) -> Color { category == .tajweed ? state.colors.gold : category == .tashkeel ? Color(hex: 0x5B8DEF) : state.colors.red }
    private func icon(_ category: ErrorCategory) -> String { category == .tajweed ? "waveform" : category == .tashkeel ? "textformat" : "exclamationmark.triangle" }
    private func title(_ error: ReciterError) -> String { error.rule.map { state.isArabic ? $0.nameArabic : $0.nameEnglish } ?? (error.category == .tashkeel ? (state.isArabic ? "خطأ في التشكيل" : "Vowel error") : (state.isArabic ? "خطأ في النطق" : "Pronunciation error")) }
    private func action(_ error: ReciterError) -> String {
        if let expected = error.expectedDuration, let actual = error.actualDuration {
            return actual < expected
                ? (state.isArabic ? "أطِل الصوت" : "Hold Longer")
                : (state.isArabic ? "قصّر الصوت" : "Too Long")
        }
        switch error.action {
        case .delete: return state.isArabic ? "حذف" : "Missing"
        case .insert: return state.isArabic ? "زيادة" : "Extra"
        case .replace: return state.isArabic ? "تبديل" : "Replace"
        }
    }

    private func durationExplanation(actual: Double, expected: Double) -> String {
        if actual < expected {
            return state.isArabic
                ? "الحروف متطابقة، لكن مدة الصوت المقدّرة أقصر من المطلوب."
                : "The phonemes match. Only the estimated sound duration was shorter than required."
        }
        return state.isArabic
            ? "الحروف متطابقة، لكن مدة الصوت المقدّرة أطول من المطلوب."
            : "The phonemes match. Only the estimated sound duration was longer than required."
    }

    private func displayPhoneme(_ value: String) -> String {
        value.isEmpty ? "—" : PhoneticDisplay.readable(value)
    }

    private func isSameDurationPhoneme(_ error: ReciterError) -> Bool {
        error.expectedDuration != nil && error.actualDuration != nil &&
            PhoneticDisplay.readable(error.expected) == PhoneticDisplay.readable(error.predicted)
    }

    private func logDisplayedPayload() {
        let details = selection.errors.enumerated().map { index, error in
            "error[\(index)] category=\(error.category.rawValue) action=\(action(error)) expected={\(PhoneticDisplay.diagnostic(error.expected))} predicted={\(PhoneticDisplay.diagnostic(error.predicted))}"
        }
        RQLog.block("UI-RESULT", "Opened error sheet for \(selection.word)", rows: [
            ("errors", "\(selection.errors.count)"),
            ("font policy", "Quran word uses Hafs; diagnostic phonemes use system Arabic font")
        ], details: details, verdict: "UI DISPLAY — special model symbol ں is presented as readable Arabic ن")
    }
}
