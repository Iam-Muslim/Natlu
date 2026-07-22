import SwiftUI

struct ErrorSelection: Identifiable {
    let id = UUID(), word: String
    let errors: [ReciterError]
}

struct VerseRow: View {
    let verse: QuranVerse
    let tracking: TrackingViewModel
    let colors: ThemeColors
    let fontSize: Double
    let blurUnread: Bool
    let isActive: Bool
    let onSelect: () -> Void
    let onError: (ErrorSelection) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            RTLFlowLayout(horizontalSpacing: 14, verticalSpacing: fontSize * 0.7) {
                ForEach(Array(verse.uthmaniWords.enumerated()), id: \.offset) { index, word in
                    let phonemeIndex = verse.wordMap.indices.contains(index) ? verse.wordMap[index] : index
                    Button {
                        let errors = tracking.wordErrors(ayah: verse.ayah, word: phonemeIndex)
                        if errors.isEmpty { onSelect() }
                        else { onError(.init(word: word, errors: errors)) }
                    } label: {
                        Text(word)
                            .font(.custom(FontRegistrar.fontName, size: fontSize))
                            .foregroundStyle(wordColor(index: phonemeIndex))
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(currentWordBackground(index: phonemeIndex), in: .rect(cornerRadius: 8))
                            .overlay {
                                if isCurrentWord(index: phonemeIndex) {
                                    RoundedRectangle(cornerRadius: 8).stroke(colors.listeningWordBorder, lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(word)
                    .accessibilityValue(accessibilityValue(index: phonemeIndex))
                }
                Button(action: onSelect) {
                    Text(verse.ayahMarker.isEmpty ? arabicDigits(verse.ayah) : verse.ayahMarker)
                        .font(.custom(FontRegistrar.fontName, size: fontSize * 0.9))
                        .foregroundStyle(colors.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ayah \(verse.ayah)")
                    .accessibilityHint("Select this ayah for recitation")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 18)
        .background {
            Button(action: onSelect) {
                Rectangle().fill(.clear).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select Ayah \(verse.ayah)")
        }
        .background(isActive ? colors.gold.opacity(0.07) : Color.clear,
                    in: .rect(cornerRadius: 20))
        .overlay { if isActive { RoundedRectangle(cornerRadius: 20).stroke(colors.gold.opacity(0.18)) } }
    }

    private func wordColor(index: Int) -> Color {
        if tracking.isRed(ayah: verse.ayah, word: index) { return colors.red }
        if tracking.isGreen(ayah: verse.ayah, word: index) { return colors.green }
        if tracking.isYellow(ayah: verse.ayah, word: index) { return colors.currentWord }
        if tracking.isUncertain(ayah: verse.ayah, word: index) { return colors.text }
        if isCurrentWord(index: index) { return colors.text }
        if blurUnread, verse.ayah >= tracking.activeAyah { return .clear }
        return colors.text
    }

    private func isCurrentWord(index: Int) -> Bool {
        tracking.currentWord(in: verse) == index &&
            !tracking.isRed(ayah: verse.ayah, word: index) &&
            !tracking.isGreen(ayah: verse.ayah, word: index) &&
            !tracking.isYellow(ayah: verse.ayah, word: index)
    }

    private func currentWordBackground(index: Int) -> Color {
        isCurrentWord(index: index) ? colors.listeningWordBackground : .clear
    }

    private func accessibilityValue(index: Int) -> String {
        if tracking.isRed(ayah: verse.ayah, word: index) { return "Incorrect" }
        if tracking.isGreen(ayah: verse.ayah, word: index) { return "Correct" }
        if tracking.isYellow(ayah: verse.ayah, word: index) { return "Review needed" }
        if tracking.isUncertain(ayah: verse.ayah, word: index) { return "Not graded; recognition uncertain" }
        return "Unread"
    }
}

struct RTLFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    struct Cache { var sizes: [CGSize] = [] }
    func makeCache(subviews: Subviews) -> Cache { Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) }) }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) } }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 320
        var x = width, height: CGFloat = 0, rowHeight: CGFloat = 0
        for size in cache.sizes {
            if x < width, x - size.width < 0 { height += rowHeight + verticalSpacing; x = width; rowHeight = 0 }
            x -= size.width + horizontalSpacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: height + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var x = bounds.maxX, y = bounds.minY, rowHeight: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = cache.sizes[index]
            if x < bounds.maxX, x - size.width < bounds.minX { y += rowHeight + verticalSpacing; x = bounds.maxX; rowHeight = 0 }
            x -= size.width
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x -= horizontalSpacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

func arabicDigits(_ number: Int) -> String {
    let digits: [Character: Character] = ["0":"٠", "1":"١", "2":"٢", "3":"٣", "4":"٤", "5":"٥", "6":"٦", "7":"٧", "8":"٨", "9":"٩"]
    return String(String(number).map { digits[$0] ?? $0 })
}
