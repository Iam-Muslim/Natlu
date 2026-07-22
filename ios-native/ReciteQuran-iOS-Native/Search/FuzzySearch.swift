import Foundation

struct FuzzyMatch: Sendable, Equatable {
    let start: Int
    let end: Int
    let distance: Int
}

enum FuzzySearch {
    static func nearMatches(query: String, in text: String, maxDistance: Int) -> [FuzzyMatch] {
        let query = Array(query.utf16), text = Array(text.utf16)
        guard !query.isEmpty, !text.isEmpty else { return [] }
        let n = query.count
        var previousDistance = Array(0...n), previousStart = Array(repeating: 0, count: n + 1)
        var currentDistance = Array(repeating: 0, count: n + 1)
        var currentStart = Array(repeating: 0, count: n + 1)
        var matches: [FuzzyMatch] = []
        for j in 1...text.count {
            currentDistance[0] = 0; currentStart[0] = j
            for i in 1...n {
                let replacement = previousDistance[i - 1] + (query[i - 1] == text[j - 1] ? 0 : 1)
                var bestDistance = replacement, bestStart = previousStart[i - 1]
                let deletion = previousDistance[i] + 1
                if deletion < bestDistance || (deletion == bestDistance && previousStart[i] > bestStart) {
                    bestDistance = deletion; bestStart = previousStart[i]
                }
                let insertion = currentDistance[i - 1] + 1
                if insertion < bestDistance || (insertion == bestDistance && currentStart[i - 1] > bestStart) {
                    bestDistance = insertion; bestStart = currentStart[i - 1]
                }
                currentDistance[i] = bestDistance; currentStart[i] = bestStart
            }
            if currentDistance[n] <= maxDistance {
                matches.append(.init(start: currentStart[n], end: j, distance: currentDistance[n]))
            }
            swap(&previousDistance, &currentDistance); swap(&previousStart, &currentStart)
        }
        return filterOverlapping(matches)
    }

    private static func filterOverlapping(_ source: [FuzzyMatch]) -> [FuzzyMatch] {
        let matches = source.sorted { ($0.start, $0.end, $0.distance) < ($1.start, $1.end, $1.distance) }
        guard var current = matches.first else { return [] }
        var output: [FuzzyMatch] = []
        for next in matches.dropFirst() {
            if next.start < current.end {
                let nextLength = next.end - next.start, currentLength = current.end - current.start
                if next.distance < current.distance || (next.distance == current.distance && nextLength < currentLength) { current = next }
            } else { output.append(current); current = next }
        }
        output.append(current); return output
    }
}
