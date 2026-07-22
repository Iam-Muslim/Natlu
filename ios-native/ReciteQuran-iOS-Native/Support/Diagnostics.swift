import Foundation

enum RQLog {
    static func write(_ category: String, _ message: @autoclosure () -> String) {
        let uptime = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        print("[RQ][\(uptime)][\(category)] \(message())")
    }

    static func preview(_ text: String, limit: Int = 80) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > limit else { return text }
        return String(String.UnicodeScalarView(scalars.prefix(limit))) + "…"
    }

    static func block(_ category: String, _ title: String,
                      rows: [(String, String)], details: [String] = [],
                      verdict: String? = nil) {
        let uptime = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let prefix = "[RQ][\(uptime)][\(category)]"
        var output = ["\(prefix) ┌─ \(title)"]
        for (key, value) in rows {
            output.append("\(prefix) │ \(key): \(value)")
        }
        for detail in details {
            output.append("\(prefix) │   \(detail)")
        }
        if let verdict {
            output.append("\(prefix) │ VERDICT: \(verdict)")
        }
        output.append("\(prefix) └────────────────────────────────────────")
        print(output.joined(separator: "\n"))
    }

    static func codepoints(_ text: String, limit: Int = 32) -> String {
        let scalars = Array(text.unicodeScalars)
        let values = scalars.prefix(limit).map { String(format: "U+%04X", $0.value) }
        return values.joined(separator: " ") + (scalars.count > limit ? " …" : "")
    }

    static func durationSummary(_ durations: [Double], limit: Int = 16) -> String {
        guard !durations.isEmpty else { return "none (duration grading unavailable)" }
        let shown = durations.prefix(limit).map {
            $0.isFinite ? String(format: "%.0fms", $0 * 1_000) : "?"
        }.joined(separator: "+")
        let known = durations.filter(\.isFinite)
        let total = known.reduce(0, +)
        let unknown = durations.count - known.count
        return "count=\(durations.count) knownTotal=\(String(format: "%.3fs", total)) unknown=\(unknown) parts=[\(shown)\(durations.count > limit ? "+…" : "")]"
    }
}

enum PhoneticDisplay {
    static func readable(_ input: String) -> String {
        var output: [Unicode.Scalar] = []
        for scalar in input.unicodeScalars {
            switch scalar.value {
            case 0x06E5: output.append("و")
            case 0x06E6: output.append("ي")
            case 0x06BA: output.append("ن")
            case 0x06FE: output.append("م")
            case 0x0672: output.append("أ")
            case 0x0687, 0x06DC, 0x06EA, 0x0619, 0x0640: continue
            default: output.append(scalar)
            }
        }
        return String(String.UnicodeScalarView(output))
    }

    static func baseLetter(_ input: String) -> String {
        let cleaned = readable(input)
        guard let first = cleaned.unicodeScalars.first else { return "" }
        return String(first)
    }

    static func diagnostic(_ input: String) -> String {
        "readable=\"\(readable(input))\" raw=\"\(input)\" unicode=[\(RQLog.codepoints(input))]"
    }
}
