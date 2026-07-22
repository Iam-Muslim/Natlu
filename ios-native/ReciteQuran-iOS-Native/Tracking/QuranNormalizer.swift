import Foundation

enum QuranNormalizer {
    private static let tashkeel = Set("ًٌٍَُِّْ۫".unicodeScalars)
    private static let residuals = Set("َُِڇؙۣ۪ٞۜـ".unicodeScalars)

    static func normalize(_ text: String, removeSpaces: Bool = true,
                          removeTashkeel: Bool = true,
                          ignoreAlefMaksura: Bool = true,
                          removeSmallAlef: Bool = true,
                          normalizeHamzatWasl: Bool = true) -> String {
        var scalars: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            if removeSpaces, CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            if removeSmallAlef, scalar == "ٰ" { continue }
            if removeTashkeel, tashkeel.contains(scalar) { continue }
            if ignoreAlefMaksura, scalar == "ى" { scalars.append("ا"); continue }
            if normalizeHamzatWasl, scalar == "ٱ" { scalars.append("ا"); continue }
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func normalizeWithTashkeel(_ text: String) -> String {
        normalize(text, removeTashkeel: false)
    }

    static func chunkPhonemes(_ value: String) -> [String] {
        let scalars = Array(value.unicodeScalars)
        var output: [String] = []
        var index = 0
        while index < scalars.count {
            let base = scalars[index]
            if residuals.contains(base) { index += 1; continue }
            var chunk: [Unicode.Scalar] = [base]
            index += 1
            while index < scalars.count, scalars[index] == base {
                chunk.append(scalars[index]); index += 1
            }
            while index < scalars.count, residuals.contains(scalars[index]) {
                chunk.append(scalars[index]); index += 1
            }
            output.append(String(String.UnicodeScalarView(chunk)))
        }
        return output
    }
}
