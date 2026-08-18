import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';
import 'phoneme_matrix.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Per-Word Semi-Global DTW Matcher
//
// Each word is matched independently against the unconsumed ASR buffer.
// Free-start: leading noise tokens are free (handles Wasl and CTC jitter).
// First-valid-endpoint: consumes the minimum number of ASR tokens.
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of aligning ASR tokens against a single word's reference.
class WordMatchResult {
  /// Total edit cost normalized by reference length.
  final double pathCost;

  /// How many ASR tokens this match consumed from the buffer.
  final int tokensConsumed;

  /// Joined ASR phonemes that aligned to the word (match/replace ops only).
  final String cleanAsr;

  /// Timestamps of the aligned ASR tokens.
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

  const AlignmentConfig({
    this.maxPathCost = 0.28,
    this.maxSkipWords = 2,
    this.costDel = 1.0,
    this.costIns = 1.0,
  });

  factory AlignmentConfig.defaultConfig({bool isTajweed = false}) =>
      const AlignmentConfig();
}

/// Per-word semi-global DTW matcher.
class QuranDictationMatcher {
  Float64List _dp = Float64List(1024);
  Uint8List _bt = Uint8List(1024);
  Int32List _pIds = Int32List(256);

  /// Aligns [asrTokens] against the reference chunk slice [refStart, refEnd).
  ///
  /// Returns the best match or null if no alignment meets the threshold.
  WordMatchResult? matchWord({
    required List<String> asrTokens,
    required List<double> asrTimestamps,
    required List<String> refChunks,
    required int refStart,
    required int refEnd,
    Int32List? refEncodedIds,
    required AlignmentConfig config,
  }) {
    final int m = asrTokens.length;
    final int n = refEnd - refStart;
    if (m == 0 || n <= 0) return null;

    // ── Buffer management ──
    final int stride = n + 1;
    final int cells = (m + 1) * stride;
    if (_dp.length < cells) {
      final int sz = max(cells, _dp.length * 2);
      _dp = Float64List(sz);
      _bt = Uint8List(sz);
    }
    if (_pIds.length < m) {
      _pIds = Int32List(max(m, _pIds.length * 2));
    }
    for (int i = 0; i < m; i++) {
      _pIds[i] = PhonemeMatrix.encode(asrTokens[i]);
    }

    final dp = _dp;
    final bt = _bt;
    final double costDel = config.costDel;
    final double costIns = config.costIns;

    // ── Row 0: reference deletions (word phonemes with no ASR) ──
    dp[0] = 0.0;
    bt[0] = 0;
    for (int j = 1; j <= n; j++) {
      dp[j] = j * costDel;
      bt[j] = 1; // delete
    }

    // ── Column 0: FREE START (skip leading ASR tokens at zero cost) ──
    for (int i = 1; i <= m; i++) {
      dp[i * stride] = 0.0;
      bt[i * stride] = 2; // free insert
    }

    // ── Core DP fill ──
    for (int i = 1; i <= m; i++) {
      final int pId = _pIds[i - 1];
      final int row = i * stride;
      final int prev = (i - 1) * stride;

      for (int j = 1; j <= n; j++) {
        final int rIdx = refStart + j - 1;
        final int rId = (refEncodedIds != null && rIdx < refEncodedIds.length)
            ? refEncodedIds[rIdx]
            : PhonemeMatrix.encode(refChunks[rIdx]);

        final double sub = dp[prev + j - 1] + PhonemeMatrix.getCost(pId, rId);
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

    // ── Endpoint: first row i where dp[i][n]/n <= threshold ──
    int bestI = -1;
    double bestCost = double.infinity;
    for (int i = 1; i <= m; i++) {
      final double norm = dp[i * stride + n] / n;
      if (norm <= config.maxPathCost) {
        bestI = i;
        bestCost = norm;
        break; // first valid = minimum token consumption
      }
    }

    if (bestI < 0) {
      // ── Check for Partial Match ──
      // If the word isn't fully matched yet, check if a prefix of the reference
      // strongly aligns with the END of the current ASR buffer (row m).
      // If so, the reciter is likely still speaking the word, and we should WAIT
      // rather than skipping ahead to the next word.
      bool isPartial = false;
      int minJ = n > 2 ? 2 : 1; // Require at least 2 phonemes (or 1 for tiny words)
      for (int j = minJ; j < n; j++) {
        final double norm = dp[m * stride + j] / j;
        if (norm <= config.maxPathCost) {
          isPartial = true;
          break;
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
      return null;
    }

    // ── Traceback from (bestI, n) ──
    int ci = bestI, cj = n;
    final List<PhonemeGroupAlignment> rawTrace = [];
    final List<String> asrChars = [];
    final List<double> ts = [];

    while (cj > 0) {
      if (ci == 0) {
        // Remaining reference deletions at the start
        rawTrace.add(PhonemeGroupAlignment(
            opType: 'delete', refIdx: refStart + cj - 1, predIdx: -1));
        cj--;
        continue;
      }

      final int op = bt[ci * stride + cj];
      final int gRef = refStart + cj - 1;

      if (op == 0) {
        // Match or substitution
        final int rId = (refEncodedIds != null && gRef < refEncodedIds.length)
            ? refEncodedIds[gRef]
            : PhonemeMatrix.encode(refChunks[gRef]);
        final double sc = PhonemeMatrix.getCost(_pIds[ci - 1], rId);
        rawTrace.add(PhonemeGroupAlignment(
            opType: sc == 0.0 ? 'match' : 'replace',
            refIdx: gRef,
            predIdx: ci - 1));
        asrChars.add(asrTokens[ci - 1]);
        if (ci - 1 < asrTimestamps.length) ts.add(asrTimestamps[ci - 1]);
        ci--;
        cj--;
      } else if (op == 1) {
        // Reference deletion
        rawTrace.add(PhonemeGroupAlignment(
            opType: 'delete', refIdx: gRef, predIdx: -1));
        cj--;
      } else {
        // ASR insertion (noise within the alignment)
        rawTrace.add(PhonemeGroupAlignment(
            opType: 'insert', refIdx: -1, predIdx: ci - 1));
        ci--;
      }
    }
    // ci > 0 here = free leading tokens. Not traced.

    return WordMatchResult(
      pathCost: bestCost,
      tokensConsumed: bestI,
      cleanAsr: asrChars.reversed.join(''),
      timestamps: ts.reversed.toList(),
      trace: rawTrace.reversed.toList(),
    );
  }
}

// Legacy aliases for backward compatibility
typedef FullAyahDictationMatcher = QuranDictationMatcher;
typedef ForwardDictationMatcher = QuranDictationMatcher;
