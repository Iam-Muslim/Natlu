import Foundation

struct QuranVerse: Identifiable, Sendable, Equatable {
    var id: String { "\(surah):\(ayah)" }
    let surah: Int
    let ayah: Int
    let textUthmani: String
    let surahName: String
    let surahNameEn: String
    let uthmaniWords: [String]
    let readableWords: [String]
    let ayahMarker: String
    let textPhoneme: String
    let phonemeWords: [String]
    let wordMap: [Int]
}

actor QuranRepository {
    private var allVerses: [QuranVerse] = []
    private var bySurah: [Int: [QuranVerse]] = [:]

    func load() throws {
        guard allVerses.isEmpty else { return }
        let url = try BundleResources.requiredURL("ordered_quran_phonemes", extension: "json")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DataError.invalidJSON
        }
        var parsed: [QuranVerse] = []
        parsed.reserveCapacity(root.count)
        for (key, raw) in root {
            let keyParts = key.split(separator: ":")
            guard keyParts.count == 2, let surah = Int(keyParts[0]), let ayah = Int(keyParts[1]),
                  let json = raw as? [String: Any] else { continue }
            var words = (json["aya_ui"] as? String ?? "")
                .split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let ayahMarker = words.count > 1 ? words.removeLast() : ""
            words = words.map { $0.replacingOccurrences(of: "[۞۩]", with: "", options: .regularExpression) }
                .filter { !$0.isEmpty }
            let readableWords = (json["aya_text"] as? String ?? "")
                .split(whereSeparator: { $0.isWhitespace }).map(String.init)
            var phonemeWords = json["aya_phonemes_list"] as? [String] ?? Array(repeating: "", count: words.count)
            if phonemeWords.count < words.count {
                phonemeWords += Array(repeating: "", count: words.count - phonemeWords.count)
            }
            parsed.append(QuranVerse(
                surah: surah, ayah: ayah, textUthmani: words.joined(separator: " "),
                surahName: json["suraname_ar"] as? String ?? "",
                surahNameEn: json["suraname_en"] as? String ?? "",
                uthmaniWords: words, readableWords: readableWords, ayahMarker: ayahMarker,
                textPhoneme: json["aya_phoneme"] as? String ?? "",
                phonemeWords: phonemeWords,
                wordMap: Array(words.indices).map { min($0, max(0, phonemeWords.count - 1)) }
            ))
        }
        parsed.sort { ($0.surah, $0.ayah) < ($1.surah, $1.ayah) }
        allVerses = parsed
        bySurah = Dictionary(grouping: parsed, by: \.surah)
    }

    func verses() -> [QuranVerse] { allVerses }
    func surah(_ number: Int) -> [QuranVerse] { bySurah[number] ?? [] }
    func verse(surah: Int, ayah: Int) -> QuranVerse? { bySurah[surah]?.first { $0.ayah == ayah } }
    func nextVerse(surah: Int, ayah: Int) -> QuranVerse? {
        if let next = bySurah[surah]?.first(where: { $0.ayah == ayah + 1 }) { return next }
        return bySurah[surah + 1]?.first
    }
    func surahMetadata() -> [QuranVerse] { (1...114).compactMap { bySurah[$0]?.first } }

    enum DataError: Error { case invalidJSON }
}
