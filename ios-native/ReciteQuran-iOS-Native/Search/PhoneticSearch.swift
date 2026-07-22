import Foundation

struct PhonemesSearchSpan: Sendable, Equatable {
    let surah: Int, ayah: Int, uthmaniWord: Int, uthmaniCharacter: Int, phoneme: Int
}
struct PhonemesSearchResult: Sendable, Equatable {
    let start: PhonemesSearchSpan, end: PhonemesSearchSpan, distance: Int
}

actor PhoneticSearch {
    private var index: [UInt16] = []
    private var reference = ""
    private(set) var headerLength = 0
    private(set) var dataOffset = 0

    func load() throws {
        guard index.isEmpty else { return }
        reference = try String(contentsOf: BundleResources.requiredURL("ref_norm_ph", extension: "txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try Data(contentsOf: BundleResources.requiredURL("ph_index", extension: "npy"), options: .mappedIfSafe)
        let bytes = [UInt8](data)
        guard bytes.count > 10, Array(bytes[0..<6]) == [0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59] else { throw SearchError.invalidNPY }
        let major = bytes[6]
        var cursor: Int
        if major == 1 {
            headerLength = Int(bytes[8]) | Int(bytes[9]) << 8; cursor = 10
        } else if major == 2 || major == 3 {
            headerLength = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24; cursor = 12
        } else { throw SearchError.invalidNPY }
        dataOffset = cursor + headerLength
        guard dataOffset <= bytes.count, (bytes.count - dataOffset).isMultiple(of: 2) else { throw SearchError.invalidNPY }
        index.reserveCapacity((bytes.count - dataOffset) / 2)
        for offset in stride(from: dataOffset, to: bytes.count, by: 2) {
            index.append(UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)
        }
        guard index.count / 7 == reference.utf16.count else { throw SearchError.inconsistentIndex }
    }

    func rowCount() -> Int { index.count / 7 }

    func search(_ query: String, errorRatio: Double = 0.1) throws -> [PhonemesSearchResult] {
        if index.isEmpty { try load() }
        let normalized = Self.normalizedQuery(query)
        guard !normalized.isEmpty else { return [] }
        let maxEdits = Int(Double(normalized.utf16.count) * errorRatio)
        return FuzzySearch.nearMatches(query: normalized, in: reference, maxDistance: maxEdits).map {
            .init(start: span(at: $0.start, end: false), end: span(at: $0.end - 1, end: true), distance: $0.distance)
        }.sorted { $0.distance < $1.distance }
    }

    static func normalizedQuery(_ query: String) -> String {
        let core = Set("ءبتثجحخدذرزسشصضطظعغفقكلمنهوياۥۦ۾ںـٲ".unicodeScalars)
        let residual = Set("َُِڇؙ۪ۜ".unicodeScalars)
        var output: [Unicode.Scalar] = [], previous: Unicode.Scalar?
        for scalar in query.unicodeScalars {
            if residual.contains(scalar) { continue }
            guard core.contains(scalar) else { previous = nil; continue }
            if scalar != previous { output.append(scalar) }
            previous = scalar
        }
        return String(String.UnicodeScalarView(output))
    }

    private func span(at referenceIndex: Int, end: Bool) -> PhonemesSearchSpan {
        let offset = referenceIndex * 7
        return .init(surah: Int(index[offset]), ayah: Int(index[offset + 1]),
                     uthmaniWord: Int(index[offset + 2]),
                     uthmaniCharacter: Int(index[offset + (end ? 4 : 3)]),
                     phoneme: Int(index[offset + (end ? 6 : 5)]))
    }

    enum SearchError: Error { case invalidNPY, inconsistentIndex }
}
