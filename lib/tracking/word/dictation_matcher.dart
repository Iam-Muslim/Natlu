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
    this.maxPathCost = 0.28,
    this.maxSkipWords = 2,
    this.costDel = 1.0,
    this.costIns = 1.0,
    this.isTajweedEnabled = true,
  });

  factory AlignmentConfig.defaultConfig({bool isTajweed = false}) =>
      const AlignmentConfig();
}

/// Per-word semi-global DTW matcher operating directly on character strings.
class QuranDictationMatcher {
  Float64List _dp = Float64List(2048);
  Uint8List _bt = Uint8List(2048);

  void reset() {}

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
    final double costDel = config.costDel;
    final double costIns = config.costIns;

    // ═════════════════════════════════════════════════════════════════════════
    // 2. MATRIX INITIALIZATION
    // ═════════════════════════════════════════════════════════════════════════
    // Row 0: reference deletions (word phonemes with no ASR)
    dp[0] = 0.0;
    bt[0] = 0;
    for (int j = 1; j <= n; j++) {
      dp[j] = j * costDel;
      bt[j] = 1; // delete
    }

    // Column 0: FREE START (skip leading ASR noise characters at zero cost)
    for (int i = 1; i <= m; i++) {
      dp[i * stride] = 0.0;
      bt[i * stride] = 2; // free insert
    }

    // ═════════════════════════════════════════════════════════════════════════
    // 3. CORE DP FILL (DYNAMIC TIME WARPING WITH DIRECT CODE UNITS)
    // ═════════════════════════════════════════════════════════════════════════
    for (int i = 1; i <= m; i++) {
      final int aCode = asrText.codeUnitAt(i - 1);
      final int row = i * stride;
      final int prev = (i - 1) * stride;

      for (int j = 1; j <= n; j++) {
        final int rCode = fullPhonemes.codeUnitAt(refStart + j - 1);

        final double sub = dp[prev + j - 1] + (aCode == rCode ? 0.0 : 1.0);
        final double del = dp[row + j - 1] + costDel;
        final double ins = dp[prev + j] + costIns;

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
    // 4. ENDPOINT DETECTION
    // ═════════════════════════════════════════════════════════════════════════
    int bestI = -1;
    double bestCost = double.infinity;

    // Dynamic threshold: short words require higher confidence to prevent false positives from noise.
    double threshold = config.maxPathCost;
    if (n <= 2) {
      threshold = min(threshold, 0.10);
    } else if (n <= 4) {
      threshold = min(threshold, 0.20);
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
          if (dp[i * stride + j] / j <= config.maxPathCost) {
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
          if (asrText.codeUnitAt(ci - 1) != fullPhonemes.codeUnitAt(refStart + cj - 1)) {
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
        final bool isMatch = (asrText.codeUnitAt(ci - 1) == fullPhonemes.codeUnitAt(gRef));
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

// Legacy aliases for backward compatibility
typedef FullAyahDictationMatcher = QuranDictationMatcher;
typedef ForwardDictationMatcher = QuranDictationMatcher;
