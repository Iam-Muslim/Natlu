import Foundation

enum TajweedDurations {
    static let harakah = 0.25
    static let shaddah = 1.0 * harakah
    static let normalMadd = 1.5 * harakah
    static let ghunnah = 2.0 * harakah
    static let groupFourMadd = 4.0 * harakah
    static let lazimMadd = 6.0 * harakah
}

struct TajweedTimingProfile: Sendable, Equatable {
    let harakah: Double
    let graceFraction: Double
    let timestampAllowance: Double
    let sampleCount: Int
    let isAdaptive: Bool

    static let fixed = TajweedTimingProfile(
        harakah: TajweedDurations.harakah,
        graceFraction: 0,
        timestampAllowance: 0,
        sampleCount: 0,
        isAdaptive: false
    )

    func targetDuration(for kind: TajweedRuleKind) -> Double {
        let multiplier: Double
        switch kind {
        case .shaddah: multiplier = 1.0
        case .normalMadd: multiplier = 1.5
        case .ghunnah: multiplier = 2.0
        case .separatedMadd, .connectedMadd, .temporaryMadd, .leenMadd: multiplier = 4.0
        case .lazimMadd: multiplier = 6.0
        }
        return multiplier * harakah
    }

    func minimumDuration(for kind: TajweedRuleKind) -> Double {
        let generalMinimum = targetDuration(for: kind) * (1 - graceFraction) - timestampAllowance
        if kind == .normalMadd {
            // Keep 1.5 harakah as the teaching target, but accept one measured
            // harakah minus the timestamp allowance. Natural Madd is common
            // and short enough that
            // applying the generic long-rule threshold makes normal recitation
            // feel artificially strict (0.16s pace previously requested 0.19s).
            return max(0.04, min(harakah - timestampAllowance, generalMinimum))
        }
        return max(0.04, generalMinimum)
    }
}

enum TajweedRuleKind: String, Sendable {
    case shaddah
    case normalMadd
    case separatedMadd
    case connectedMadd
    case temporaryMadd
    case leenMadd
    case lazimMadd
    case ghunnah
}

struct TajweedRule: Sendable, Equatable {
    let kind: TajweedRuleKind
    let nameArabic: String
    let nameEnglish: String
    let targetDuration: Double
    let requiredDuration: Double
    let tag: String?
}

enum TajweedRules {
    private static let alif: Unicode.Scalar = "ا"
    private static let smallWaw: Unicode.Scalar = "ۥ"
    private static let smallYaa: Unicode.Scalar = "ۦ"
    private static let noon: Unicode.Scalar = "ن"
    private static let yaa: Unicode.Scalar = "ي"
    private static let waw: Unicode.Scalar = "و"
    private static let meem: Unicode.Scalar = "م"
    private static let hiddenNoon: Unicode.Scalar = "ں"
    private static let hiddenMeem: Unicode.Scalar = "۾"
    private static let hamza = Set("ءأإؤئآ".unicodeScalars)

    static func rules(for chunk: String, isLastWord: Bool,
                      nextChunk: String = "", isNextChunkInNextWord: Bool = false,
                      timing: TajweedTimingProfile = .fixed) -> [TajweedRule] {
        guard let base = chunk.unicodeScalars.first else { return [] }
        let count = chunk.unicodeScalars.reduce(into: 0) { result, scalar in
            if scalar == base { result += 1 }
        }
        var result: [TajweedRule] = []

        let pureMadd = base == alif || base == smallWaw || base == smallYaa
        let leenOrRepeatedWawYaa = (base == waw || base == yaa) && count >= 2
        if pureMadd || leenOrRepeatedWawYaa {
            result.append(maddRule(base: base, count: count, isLastWord: isLastWord,
                                   isLeen: leenOrRepeatedWawYaa,
                                   nextChunk: nextChunk,
                                   isNextChunkInNextWord: isNextChunkInNextWord,
                                   timing: timing))
        }

        let isYaaOrWaw = base == yaa || base == waw
        let nextBase = nextChunk.unicodeScalars.first
        let crossWordIdgham = isYaaOrWaw && count >= 2 && isNextChunkInNextWord && nextBase == base
        if (!isYaaOrWaw || crossWordIdgham),
           let ghunnah = ghunnahRule(base: base, repeatCount: count, timing: timing) {
            result.append(ghunnah)
        }

        if let shaddah = shaddahRule(base: base, repeatCount: count, timing: timing) {
            result.append(shaddah)
        }
        return result
    }

    private static func maddRule(base: Unicode.Scalar, count: Int, isLastWord: Bool,
                                 isLeen: Bool, nextChunk: String,
                                 isNextChunkInNextWord: Bool,
                                 timing: TajweedTimingProfile) -> TajweedRule {
        if count >= 6 {
            return rule(.lazimMadd, "المد اللازم", "Lazim Madd", timing: timing)
        }
        if isLastWord, isLeen {
            return rule(.leenMadd, "مد اللين", "Leen Madd", timing: timing)
        }
        if isLastWord, count >= 4 {
            return rule(.temporaryMadd, "المد العارض للسكون", "Temporary Madd", timing: timing)
        }
        if count == 4 || count == 5 {
            let nextIsHamza = nextChunk.unicodeScalars.first.map { hamza.contains($0) } == true
            if isNextChunkInNextWord, nextIsHamza {
                return rule(.separatedMadd, "المد المنفصل", "Separated Madd", timing: timing)
            }
            return rule(.connectedMadd, "المد المتصل", "Connected Madd", timing: timing)
        }
        let tag = base == alif ? "alif" : base == smallWaw || base == waw ? "waw" : "yaa"
        return rule(.normalMadd, "المد الطبيعي", "Natural Madd", timing: timing, tag: tag)
    }

    private static func ghunnahRule(base: Unicode.Scalar, repeatCount: Int,
                                    timing: TajweedTimingProfile) -> TajweedRule? {
        switch base {
        case noon where repeatCount >= 2:
            return rule(.ghunnah, "النون المشددة أو المدغمة", "Shaddah/Idgham Noon",
                        timing: timing, tag: "noon")
        case meem where repeatCount >= 2:
            return rule(.ghunnah, "الميم المشددة", "Shaddah Meem",
                        timing: timing, tag: "meem")
        case yaa where repeatCount >= 2:
            return rule(.ghunnah, "إدغام النون في الياء", "Noon-Yaa Idgham",
                        timing: timing, tag: "noon_yaa")
        case waw where repeatCount >= 2:
            return rule(.ghunnah, "إدغام النون في الواو", "Noon-Waw Idgham",
                        timing: timing, tag: "noon_waw")
        case hiddenNoon:
            return rule(.ghunnah, "إخفاء النون", "Hidden Noon Ghunnah",
                        timing: timing, tag: "hidden_noon")
        case hiddenMeem:
            return rule(.ghunnah, "الإقلاب أو الإخفاء الشفوي", "Iqlab/Ikhfa Shafawi Ghunnah",
                        timing: timing, tag: "hidden_meem")
        default:
            return nil
        }
    }

    private static func shaddahRule(base: Unicode.Scalar, repeatCount: Int,
                                    timing: TajweedTimingProfile) -> TajweedRule? {
        guard repeatCount >= 2,
              base != alif, base != smallWaw, base != smallYaa,
              base != noon, base != meem else { return nil }
        return rule(.shaddah, "الشدة", "Shaddah", timing: timing)
    }

    private static func rule(_ kind: TajweedRuleKind, _ arabic: String, _ english: String,
                             timing: TajweedTimingProfile, tag: String? = nil) -> TajweedRule {
        let target = timing.targetDuration(for: kind)
        return .init(kind: kind, nameArabic: arabic, nameEnglish: english,
                     targetDuration: target,
                     requiredDuration: timing.minimumDuration(for: kind), tag: tag)
    }
}
