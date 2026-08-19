import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Per-Word Semi-Global DTW Matcher (Direct Character-Level Alignment)
//
// Each word is matched independently against the unconsumed ASR buffer.
// Free-start: leading noise characters are free (handles Wasl and CTC jitter).
// First-valid-endpoint: consumes the minimum number of ASR characters.
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of aligning ASR characters against a single word's reference.
class WordMatchResult {
  /// Total edit cost normalized by reference length.
  final double pathCost;

  /// How many ASR characters this match consumed from the buffer.
  final int tokensConsumed;

  /// Substring of ASR phonemes that aligned to the word.
  final String cleanAsr;

  /// Timestamps of the aligned ASR characters.
  final List<double> timestamps;

  /// Full alignment trace for Tajweed evaluation.
  final List<PhonemeGroupAlignment> trace;

  /// Indicates if this is a partial match (word is still being spoken).
  final bool isPartial;

  const WordMatchResult({
    required this.pathCost,
    required this.tokensConsumed,
    required this.cleanAsr,
    required this.timestamps,
    required this.trace,
    this.isPartial = false,
  });
}

/// Matcher configuration.
// ═══════════════════════════════════════════════════════════════════════════════
// Matcher configuration.
// ═══════════════════════════════════════════════════════════════════════════════

class AlignmentConfig {
  /// Max normalized path cost to accept a word as GREEN.
  final double maxPathCost;

  /// Max words to skip when detecting omissions (lookahead = 1 + maxSkipWords).
  final int maxSkipWords;

  /// Cost of a reference deletion (expected phoneme not spoken).
  final double costDel;

  /// Cost of an ASR insertion (extra phoneme in stream).
  final double costIns;

  /// Whether Tajweed mode is on. If false, massive word partial checking is skipped for speed.
  final bool isTajweedEnabled;

  const AlignmentConfig({
    this.maxPathCost = 0.30,
    this.maxSkipWords = 2,
    this.costDel = 1.0,
    this.costIns = 1.0,
    this.isTajweedEnabled = true,
  });

  factory AlignmentConfig.defaultConfig({bool isTajweed = false}) =>
      const AlignmentConfig();
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHONETIC & TAJWEED COST ENGINE (MODEL-SPECIFIC ACOUSTIC MATRIX)
// ═══════════════════════════════════════════════════════════════════════════════

class PhoneticCostEngine {
  // ── 1. Zero-Cost Tajweed & Auxiliary Markers ──
  static bool _isZeroCostMarker(int codeUnit) {
    return codeUnit == 0x0686 || // 'ڇ' - Qalqalah release burst
           codeUnit == 0x06DC || // 'ۜ' - Sakt
           codeUnit == 0x0619 || // 'ؙ' - Ishmam
           codeUnit == 0x06EA || // '۪' - Imalah
           codeUnit == 0x0640;   // 'ـ' - Tatweel
  }

  // ── 2. Interchangeable Quranic Glyphs (Cost = 0.0) ──
  static bool isEquivalentGlyph(int asrCode, int refCode) {
    if (asrCode == refCode) return true;

    // Swap to ensure 'asrCode' is always the smaller code unit
    if (asrCode > refCode) {
      final int temp = asrCode;
      asrCode = refCode;
      refCode = temp;
    }

    if (asrCode == 0x0645 && refCode == 0x06FE) return true; // م <-> ۾ (Iqlab)
    if (asrCode == 0x0646 && refCode == 0x06BA) return true; // ن <-> ں (Ikhfaa)
    if (asrCode == 0x0648 && refCode == 0x06E5) return true; // و <-> ۥ (Waw)
    if (asrCode == 0x064A && refCode == 0x06E6) return true; // ي <-> ۦ (Yaa)

    if (_isHamzaVariant(asrCode) && _isHamzaVariant(refCode)) return true;
    
    // Ta-Marbuta (ة) can sound like Haa (ه) or Taa (ت), but Haa and Taa cannot match each other!
    if (asrCode == 0x0629 && refCode == 0x0647) return true; // ة <-> ه
    if (asrCode == 0x062A && refCode == 0x0629) return true; // ت <-> ة

    return false;
  }

  static bool _isHamzaVariant(int code) =>
      code == 0x0621 || code == 0x0622 || code == 0x0623 || code == 0x0625 || code == 0x0672;

  // ── 3. Model Acoustic Confusion Matrix (Cost = 0.25) ──
  static bool _isAcousticConfusion(int asrCode, int refCode) {
    if (asrCode > refCode) {
      final int temp = asrCode;
      asrCode = refCode;
      refCode = temp;
    }

    switch (asrCode) {
      // Vowels vs Harakat (Short vs Long vowel duration confusion)
      case 0x0627: // ا (Alif)
        return refCode == 0x064E; // َ (Fatha)
      case 0x0648: // و (Waw)
        return refCode == 0x064F; // ُ (Damma)
      case 0x064F: // ُ (Damma) (smaller than Small Waw 0x06E5)
        return refCode == 0x06E5; // ۥ (Small Waw)
      case 0x064A: // ي (Yaa)
        return refCode == 0x0650; // ِ (Kasra)
      case 0x0650: // ِ (Kasra) (smaller than Small Yaa 0x06E6)
        return refCode == 0x06E6; // ۦ (Small Yaa)

      // Consonant acoustic confusions
      case 0x062A: // ت
        return refCode == 0x0637; // ط
      case 0x062C: // ج
        return refCode == 0x0632; // ز
      case 0x062E: // خ
        return refCode == 0x063A; // غ
      case 0x062F: // د
        return refCode == 0x0636; // ض
      case 0x0630: // ذ
        return refCode == 0x0632 || refCode == 0x0638; // ز, ظ
      case 0x0633: // س
        return refCode == 0x0635; // ص
      case 0x0642: // ق
        return refCode == 0x0643; // ك
      default:
        return false;
    }
  }

  // ── 4. Tashkeel / Short Vowel Detection (Cost = 1.0) ──
  static bool isTashkeel(int code) =>
      code == 0x064E || code == 0x064F || code == 0x0650; // Fatha, Damma, Kasra

  // ── 5. Substitution Cost Evaluation ──
  static double getSubstitutionCost(int asrCodeUnit, int refCodeUnit) {
    if (asrCodeUnit == refCodeUnit) return 0.0;

    if (isEquivalentGlyph(asrCodeUnit, refCodeUnit)) {
      return 0.0;
    }

    // CHECK CONFUSIONS FIRST: (Allows Fatha <-> Alif to pass as 0.25)
    if (_isAcousticConfusion(asrCodeUnit, refCodeUnit)) {
      return 0.25;
    }

    // STRICT HARAKAT PENALTY: (If it involves a Harakat but wasn't in the matrix above, it's a 1.0 error)
    if (isTashkeel(asrCodeUnit) || isTashkeel(refCodeUnit)) {
      return 1.00;
    }

    return 1.00;
  }

  // ── 6. Deletion Cost (Expected phoneme missing from stream) ──
  static double getDeletionCost(String fullPhonemes, int gRefIdx) {
    if (gRefIdx < 0 || gRefIdx >= fullPhonemes.length) return 1.0;
    final int code = fullPhonemes.codeUnitAt(gRefIdx);

    if (_isZeroCostMarker(code)) return 0.0;

    if (gRefIdx > 0 && code == fullPhonemes.codeUnitAt(gRefIdx - 1)) {
      // Limit the 0.25 repeated discount ONLY to vowels/Madd. 
      // Deleting a repeated hard consonant (Shaddah) costs 1.0 to prevent abuse.
      if (code == 0x0627 || code == 0x0648 || code == 0x064A || code == 0x06E5 || code == 0x06E6) {
        return 0.25;
      }
    }

    return 1.00;
  }

  // ── 7. Insertion Cost (Extra phoneme in ASR stream) ──
  static double getInsertionCost(String asrText, int asrIdx) {
    if (asrIdx < 0 || asrIdx >= asrText.length) return 1.0;
    final int code = asrText.codeUnitAt(asrIdx);

    if (_isZeroCostMarker(code)) return 0.0;

    if (asrIdx > 0 && code == asrText.codeUnitAt(asrIdx - 1)) {
      if (code == 0x0627 || code == 0x0648 || code == 0x064A || code == 0x06E5 || code == 0x06E6) {
        return 0.25;
      }
    }

    return 1.00;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Per-word semi-global DTW matcher operating directly on character strings.
// ═══════════════════════════════════════════════════════════════════════════════

class QuranDictationMatcher {
  Float64List _dp = Float64List(2048);
  Uint8List _bt = Uint8List(2048);

  /// Aligns [asrText] against the reference slice [refStart, refEnd) in [fullPhonemes].
  ///
  /// Returns the best match or null if no alignment meets the threshold.
  WordMatchResult? matchWord({
    required String asrText,
    required List<double> asrTimestamps,
    required String fullPhonemes,
    required int refStart,
    required int refEnd,
    required AlignmentConfig config,
  }) {
    final int m = asrText.length;
    final int n = refEnd - refStart;
    if (m == 0 || n <= 0) return null;

    // ═════════════════════════════════════════════════════════════════════════
    // 1. BUFFER MANAGEMENT
    // ═════════════════════════════════════════════════════════════════════════
    final int stride = n + 1;
    final int cells = (m + 1) * stride;
    if (_dp.length < cells) {
      final int sz = max(cells, _dp.length * 2);
      _dp = Float64List(sz);
      _bt = Uint8List(sz);
    }

    final dp = _dp;
    final bt = _bt;

    // ═════════════════════════════════════════════════════════════════════════
    // 2. MATRIX INITIALIZATION
    // ═════════════════════════════════════════════════════════════════════════
    // Row 0: reference deletions (word phonemes with no ASR)
    dp[0] = 0.0;
    bt[0] = 0;
    for (int j = 1; j <= n; j++) {
      final double delCost = PhoneticCostEngine.getDeletionCost(
        fullPhonemes,
        refStart + j - 1,
      );
      dp[j] = dp[j - 1] + delCost;
      bt[j] = 1; // delete
    }

    // Column 0: FREE START (skip leading ASR noise characters at zero cost)
    for (int i = 1; i <= m; i++) {
      dp[i * stride] = 0.0;
      bt[i * stride] = 2; // free insert
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 3. CORE DP FILL (DYNAMIC TIME WARPING WITH PHONETIC COST MATRIX)
    // ═════════════════════════════════════════════════════════════════════════
    for (int i = 1; i <= m; i++) {
      final int aCode = asrText.codeUnitAt(i - 1);
      final int row = i * stride;
      final int prev = (i - 1) * stride;
      final double insCost = PhoneticCostEngine.getInsertionCost(asrText, i - 1);

      for (int j = 1; j <= n; j++) {
        final int rRef = refStart + j - 1;
        final int rCode = fullPhonemes.codeUnitAt(rRef);

        final double subCost = PhoneticCostEngine.getSubstitutionCost(aCode, rCode);
        final double delCost = PhoneticCostEngine.getDeletionCost(fullPhonemes, rRef);

        final double sub = dp[prev + j - 1] + subCost;
        final double del = dp[row + j - 1] + delCost;
        final double ins = dp[prev + j] + insCost;

        if (sub <= del && sub <= ins) {
          dp[row + j] = sub;
          bt[row + j] = 0; // match/sub
        } else if (del <= ins) {
          dp[row + j] = del;
          bt[row + j] = 1; // delete
        } else {
          dp[row + j] = ins;
          bt[row + j] = 2; // insert
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 4. ENDPOINT DETECTION (CALIBRATED DYNAMIC THRESHOLD)
    // ═════════════════════════════════════════════════════════════════════════
    int bestI = -1;
    double bestCost = double.infinity;

    // Dynamic threshold: scaled to guarantee matching at >= 70% accuracy (up to 30% error)
    // while preventing random acoustic noise from triggering false greens on short words.
    double threshold = config.maxPathCost;
    if (n <= 3) {
      threshold = min(threshold, 0.25);
    } else if (n <= 5) {
      threshold = min(threshold, 0.28);
    } else {
      threshold = min(threshold, 0.30);
    }

    for (int i = 1; i <= m; i++) {
      final double norm = dp[i * stride + n] / n;
      if (norm <= threshold) {
        if (norm < bestCost) {
          bestI = i;
          bestCost = norm;
        }
      }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 5. PARTIAL MATCHING LOGIC
    // ═════════════════════════════════════════════════════════════════════════
    bool isPartial = false;

    if (bestI < 0) {
      // ── 1. Prefix Match (For words that failed the full cost threshold) ──
      int minJ = n > 2 ? 2 : 1;
      int startI = max(1, m - 2);
      for (int i = startI; i <= m; i++) {
        for (int j = minJ; j < n; j++) {
          if (dp[i * stride + j] / j <= threshold) {
            isPartial = true;
            break;
          }
        }
        if (isPartial) break;
      }
    } else if (config.isTajweedEnabled && (m - bestI) <= 3) {
      // ── 2. Massive Word Check (For long words that mathematically passed) ──
      int trailingErrors = 0;
      int ci = bestI, cj = n;

      while (ci > 0 && cj > 0) {
        int op = bt[ci * stride + cj];
        if (op == 1) { // Deletion
          trailingErrors++;
          cj--;
        } else if (op == 2) { // Insertion
          trailingErrors++;
          ci--;
        } else { // Match or Sub
          final int asrCode = asrText.codeUnitAt(ci - 1);
          final int refCode = fullPhonemes.codeUnitAt(refStart + cj - 1);
          if (PhoneticCostEngine.getSubstitutionCost(asrCode, refCode) > 0.0) {
            trailingErrors++;
            ci--;
            cj--;
          } else {
            break;
          }
        }
      }

      if (trailingErrors >= 3) {
        isPartial = true;
      }
    }

    if (isPartial) {
      return const WordMatchResult(
        pathCost: 0.0,
        tokensConsumed: 0,
        cleanAsr: '',
        timestamps: [],
        trace: [],
        isPartial: true,
      );
    }

    if (bestI < 0) return null;

    // ═════════════════════════════════════════════════════════════════════════
    // 6. TRACEBACK & RESULTS
    // ═════════════════════════════════════════════════════════════════════════
    int ci = bestI, cj = n;
    final List<PhonemeGroupAlignment> rawTrace = [];
    final List<double> ts = [];

    while (cj > 0) {
      if (ci == 0) {
        rawTrace.add(
          PhonemeGroupAlignment(
            opType: 'delete',
            refIdx: refStart + cj - 1,
            predIdx: -1,
          ),
        );
        cj--;
        continue;
      }

      final int op = bt[ci * stride + cj];
      final int gRef = refStart + cj - 1;

      if (op == 0) {
        final int asrCode = asrText.codeUnitAt(ci - 1);
        final int refCode = fullPhonemes.codeUnitAt(gRef);
        final bool isMatch = PhoneticCostEngine.getSubstitutionCost(asrCode, refCode) == 0.0;
        rawTrace.add(
          PhonemeGroupAlignment(
            opType: isMatch ? 'match' : 'replace',
            refIdx: gRef,
            predIdx: ci - 1,
          ),
        );
        if (ci - 1 < asrTimestamps.length) ts.add(asrTimestamps[ci - 1]);
        ci--;
        cj--;
      } else if (op == 1) {
        rawTrace.add(
          PhonemeGroupAlignment(opType: 'delete', refIdx: gRef, predIdx: -1),
        );
        cj--;
      } else {
        rawTrace.add(
          PhonemeGroupAlignment(opType: 'insert', refIdx: -1, predIdx: ci - 1),
        );
        ci--;
      }
    }

    return WordMatchResult(
      pathCost: bestCost,
      tokensConsumed: bestI,
      cleanAsr: asrText.substring(0, bestI),
      timestamps: ts.reversed.toList(),
      trace: rawTrace.reversed.toList(),
    );
  }
}
