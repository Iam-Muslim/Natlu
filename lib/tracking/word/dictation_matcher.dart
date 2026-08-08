import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';
import 'phoneme_matrix.dart';

/// The edit operation chosen in the DP trellis at cell (i, j).
enum AlignmentOp {
  /// Exact phonetic match between ASR and reference.
  match,

  /// Phonetic substitution error.
  replace,

  /// Extra sound inserted.
  insert,

  /// Expected sound omitted/swallowed.
  delete,
}

/// Parameters configuring the strictness and multi-tier search behavior of the DP alignment engine.
class AlignmentConfig {
  /// Maximum normalized penalty threshold allowed for a valid match.
  final double threshold;

  /// Penalty cost for omitting a reference phoneme (Deletions).
  final double costDel;

  /// Penalty cost for hallucinating an extra phoneme (Insertions).
  final double costIns;

  /// Whether forward lookahead (word skip detection) is enabled (Tier 2).
  /// Note: Explicitly disabled in easy mode.
  final bool enableLookahead;

  /// Maximum words ahead to search for a skip in Tier 2 (typically 1, i.e., W+1).
  final int maxLookaheadWords;

  /// Relative threshold multiplier for lookahead acceptance (e.g. 0.95).
  final double lookaheadThresholdFactor;

  /// Whether multi-word span fallback (Tier 3) is enabled.
  /// Note: Explicitly disabled in easy mode.
  final bool enableSpanFallback;

  /// Relative threshold multiplier for span fallback (e.g. 1.15).
  final double spanThresholdFactor;

  /// Minimum unconsumed chunks required in buffer before attempting span fallback.
  final int minSpanBufferChunks;

  /// Unconsumed chunks threshold to trigger stalled recovery scan (Tier 4).
  final int stalledRecoveryBufferChunks;

  /// Max words to search ahead during stalled recovery scan.
  final int stalledRecoveryMaxWords;

  /// Score margin differential required for lookahead when chained confirmation is not available.
  final double lookaheadMarginDifferential;

  /// Penalty added per skipped ASR chunk during Lookahead (Tier 2).
  final double lookaheadJumpPenalty;

  /// Minimum phonetic chunks of word W+2 required for chained confirmation window.
  final int chainedConfirmationPrefixChunks;

  const AlignmentConfig({
    required this.threshold,
    this.costDel = 1.0,
    this.costIns = 1.0,
    this.enableLookahead = true,
    this.maxLookaheadWords = 1,
    this.lookaheadThresholdFactor = 0.95,
    this.enableSpanFallback = true,
    this.spanThresholdFactor = 1.15,
    this.minSpanBufferChunks = 3,
    this.stalledRecoveryBufferChunks = 8,
    this.stalledRecoveryMaxWords = 3,
    this.lookaheadMarginDifferential = 0.10,
    this.lookaheadJumpPenalty = 0.015,
    this.chainedConfirmationPrefixChunks = 2,
  });

  /// Factory helper for standard reciting strictness modes.
  factory AlignmentConfig.fromStrictness(
    String strictness, {
    bool isTajweed = false,
  }) {
    final bool isEasy = strictness == 'easy';
    final bool isStrict = strictness == 'strict';

    final double threshold = isEasy ? 0.30 : (isStrict ? 0.15 : 0.25);

    final double costDel = isEasy ? 0.65 : 1.0;
    final double costIns = isEasy ? 0.65 : 1.0;

    // Easy mode has NO lookahead or span fallback (moves strictly sequentially)
    final bool enableLookahead = !isEasy;
    final bool enableSpanFallback = !isEasy;

    return AlignmentConfig(
      threshold: threshold,
      costDel: costDel,
      costIns: costIns,
      enableLookahead: enableLookahead,
      maxLookaheadWords: 1,
      lookaheadThresholdFactor: isStrict ? 0.85 : 0.95,
      enableSpanFallback: enableSpanFallback,
      spanThresholdFactor: isStrict ? 1.05 : 1.15,
      minSpanBufferChunks: 3,
      stalledRecoveryBufferChunks: isStrict ? 16 : 12,
      stalledRecoveryMaxWords: isStrict ? 2 : 3,
      lookaheadMarginDifferential: isStrict ? 0.15 : 0.10,
      lookaheadJumpPenalty: isStrict ? 0.025 : 0.005,
      chainedConfirmationPrefixChunks: 2,
    );
  }

  /// Creates a copy of this config with updated fields.
  AlignmentConfig copyWith({
    double? threshold,
    double? costDel,
    double? costIns,
    bool? enableLookahead,
    int? maxLookaheadWords,
    double? lookaheadThresholdFactor,
    bool? enableSpanFallback,
    double? spanThresholdFactor,
    int? minSpanBufferChunks,
    int? stalledRecoveryBufferChunks,
    int? stalledRecoveryMaxWords,
    double? lookaheadMarginDifferential,
    double? lookaheadJumpPenalty,
    int? chainedConfirmationPrefixChunks,
  }) {
    return AlignmentConfig(
      threshold: threshold ?? this.threshold,
      costDel: costDel ?? this.costDel,
      costIns: costIns ?? this.costIns,
      enableLookahead: enableLookahead ?? this.enableLookahead,
      maxLookaheadWords: maxLookaheadWords ?? this.maxLookaheadWords,
      lookaheadThresholdFactor:
          lookaheadThresholdFactor ?? this.lookaheadThresholdFactor,
      enableSpanFallback: enableSpanFallback ?? this.enableSpanFallback,
      spanThresholdFactor: spanThresholdFactor ?? this.spanThresholdFactor,
      minSpanBufferChunks: minSpanBufferChunks ?? this.minSpanBufferChunks,
      stalledRecoveryBufferChunks:
          stalledRecoveryBufferChunks ?? this.stalledRecoveryBufferChunks,
      stalledRecoveryMaxWords:
          stalledRecoveryMaxWords ?? this.stalledRecoveryMaxWords,
      lookaheadMarginDifferential:
          lookaheadMarginDifferential ?? this.lookaheadMarginDifferential,
      lookaheadJumpPenalty: lookaheadJumpPenalty ?? this.lookaheadJumpPenalty,
      chainedConfirmationPrefixChunks:
          chainedConfirmationPrefixChunks ??
          this.chainedConfirmationPrefixChunks,
    );
  }
}

/// Complete output payload returned by the forward DP matcher.
class AlignmentResult {
  final int bestI;
  final int bestJ;
  final int bestStartI;
  final int bestStartJ;
  final double bestScore;
  final double pureAcousticScore;
  final List<PhonemeGroupAlignment> trace;

  const AlignmentResult({
    required this.bestI,
    required this.bestJ,
    required this.bestStartI,
    required this.bestStartJ,
    required this.bestScore,
    required this.pureAcousticScore,
    required this.trace,
  });

  @override
  String toString() =>
      'AlignmentResult(score: ${bestScore.toStringAsFixed(3)}, asr: [$bestStartI..$bestI], ref: [$bestStartJ..$bestJ])';
}

/// ────────────────────────────────────────────────────────────────────────────
/// [ForwardDictationMatcher] - The Mathematical Brain
/// ────────────────────────────────────────────────────────────────────────────
/// Computes optimal monotonic phonetic alignment using a Smith-Waterman / Levenshtein
/// dynamic programming trellis over pre-encoded integer phoneme identifiers.
///
/// Computational Complexity:
/// - Time: O(M * N) operations, where M = ASR length, N = Reference word length.
/// - Memory: O(N) heap allocations (reusable typed scratch buffers, zero GC pressure).
class ForwardDictationMatcher {
  Float64List _prevCost = Float64List(256);
  Float64List _currCost = Float64List(256);
  Int32List _prevStartI = Int32List(256);
  Int32List _currStartI = Int32List(256);
  Uint8List _op = Uint8List(256 * 256);
  Int32List _pIds = Int32List(256);
  Int32List _rIds = Int32List(256);

  /// Performs monotonic phonetic alignment of the incoming ASR stream against the target word.
  AlignmentResult? align({
    required List<String> currentAsrChunks,
    required List<String> targetWindow,
    required int expectedWord,
    required AlignmentConfig config,
    Int32List? targetEncodedIds,
    List<double>? asrYsProbs,
    void Function(String)? debugLog,
  }) {
    final double threshold = config.threshold;
    final double costDel = config.costDel;
    final double costIns = config.costIns;

    final int m = currentAsrChunks.length;
    final int n = targetWindow.length;

    if (m == 0 || n == 0) return null;

    final int requiredN = n + 1;
    if (_prevCost.length < requiredN) {
      int newCap = max(requiredN, _prevCost.length * 2);
      _prevCost = Float64List(newCap);
      _currCost = Float64List(newCap);
      _prevStartI = Int32List(newCap);
      _currStartI = Int32List(newCap);
    }

    final int requiredOp = (m + 1) * (n + 1);
    if (_op.length < requiredOp) {
      int newCap = max(requiredOp, _op.length * 2);
      _op = Uint8List(newCap);
    }
    _op.fillRange(0, requiredOp, 0);

    if (_pIds.length < m) {
      _pIds = Int32List(max(m, _pIds.length * 2));
    }
    final Int32List pIds = _pIds;
    for (int i = 0; i < m; i++) {
      pIds[i] = PhonemeMatrix.encode(currentAsrChunks[i]);
    }

    final Int32List rIds;
    if (targetEncodedIds != null && targetEncodedIds.length == n) {
      rIds = targetEncodedIds;
    } else {
      if (_rIds.length < n) {
        _rIds = Int32List(max(n, _rIds.length * 2));
      }
      for (int j = 0; j < n; j++) {
        _rIds[j] = PhonemeMatrix.encode(targetWindow[j]);
      }
      rIds = _rIds;
    }

    final Float64List prevCost = _prevCost;
    final Float64List currCost = _currCost;
    final Int32List prevStartI = _prevStartI;
    final Int32List currStartI = _currStartI;
    final Uint8List op = _op;
    final int opStride = n + 1;

    for (int j = 0; j <= n; j++) {
      prevCost[j] = j * costDel;
      prevStartI[j] = 0;
    }

    double bestNormDist = double.infinity;
    int bestI = -1;
    int bestStartI = 0;

    for (int i = 1; i <= m; i++) {
      currCost[0] = 0.0;
      currStartI[0] = i;

      final int pId = pIds[i - 1];

      for (int j = 1; j <= n; j++) {
        final int rId = rIds[j - 1];

        final double delCost = prevCost[j] + costIns;
        final double insCost = currCost[j - 1] + costDel;

        final double matchCost = PhonemeMatrix.getCost(pId, rId);
        final double replCost = prevCost[j - 1] + matchCost;

        double minVal = replCost;
        int choice = AlignmentOp.replace.index;
        int sI = prevStartI[j - 1];

        if (delCost < minVal) {
          minVal = delCost;
          choice = AlignmentOp.insert.index;
          sI = prevStartI[j];
        }

        if (insCost < minVal) {
          minVal = insCost;
          choice = AlignmentOp.delete.index;
          sI = currStartI[j - 1];
        }

        currCost[j] = minVal;
        currStartI[j] = sI;
        op[i * opStride + j] = choice;

        if (j == n) {
          final int lengthAsr = i - sI;
          final int denom = max(n, lengthAsr);

          if (denom > 0) {
            final double normDist = minVal / denom;
            if (normDist <= bestNormDist) {
              bestNormDist = normDist;
              bestI = i;
              bestStartI = sI;
            }
          }
        }
      }

      // Fast block transfer from curr to prev
      prevCost.setRange(0, n + 1, currCost);
      prevStartI.setRange(0, n + 1, currStartI);
    }

    if (bestI != -1 && bestNormDist <= threshold) {
      int currI = bestI;
      int currJ = n;
      final List<PhonemeGroupAlignment> trace = [];

      while (currI > bestStartI || currJ > 0) {
        if (currI == bestStartI) {
          trace.add(
            PhonemeGroupAlignment(
              opType: 'delete',
              refIdx: currJ - 1,
              predIdx: -1,
            ),
          );
          currJ--;
          continue;
        }
        if (currJ == 0) {
          trace.add(
            PhonemeGroupAlignment(
              opType: 'insert',
              refIdx: -1,
              predIdx: currI - 1,
            ),
          );
          currI--;
          continue;
        }

        final int actionVal = op[currI * opStride + currJ];
        final AlignmentOp action = AlignmentOp.values[actionVal];

        if (action == AlignmentOp.insert) {
          trace.add(
            PhonemeGroupAlignment(
              opType: 'insert',
              refIdx: -1,
              predIdx: currI - 1,
            ),
          );
          currI--;
        } else if (action == AlignmentOp.delete) {
          trace.add(
            PhonemeGroupAlignment(
              opType: 'delete',
              refIdx: currJ - 1,
              predIdx: -1,
            ),
          );
          currJ--;
        } else {
          final double sc = PhonemeMatrix.getCost(
            pIds[currI - 1],
            rIds[currJ - 1],
          );
          final String opName = sc == 0.0 ? 'match' : 'replace';

          trace.add(
            PhonemeGroupAlignment(
              opType: opName,
              refIdx: currJ - 1,
              predIdx: currI - 1,
            ),
          );
          currI--;
          currJ--;
        }
      }

      final List<PhonemeGroupAlignment> finalTrace = trace.reversed.map((a) {
        return PhonemeGroupAlignment(
          opType: a.opType,
          refIdx: a.refIdx >= 0 ? a.refIdx : -1,
          predIdx: a.predIdx >= 0 ? a.predIdx - bestStartI : -1,
        );
      }).toList();

      double totalPenalty = 0.0;
      int asrLen = 0;
      String heardWordStr = '';
      int matchedRefChunks = 0;

      for (int aIdx = 0; aIdx < finalTrace.length; aIdx++) {
        final align = finalTrace[aIdx];

        if (align.predIdx >= 0) {
          asrLen++;
          heardWordStr += currentAsrChunks[bestStartI + align.predIdx];
        }
        if (align.refIdx >= 0) {
          if (align.opType == 'match' || align.opType == 'replace') {
            matchedRefChunks++;
          }
        }

        if (align.opType == 'insert') {
          totalPenalty += costIns;
        } else if (align.opType == 'delete') {
          totalPenalty += costDel;
        } else if (align.opType == 'replace') {
          final double exactCost = PhonemeMatrix.getCost(
            pIds[bestStartI + align.predIdx],
            rIds[align.refIdx],
          );
          totalPenalty += exactCost;
        }
      }

      final int denom = max(asrLen, max(n, 1));
      final double wordScore = totalPenalty / denom;

      final double coverage = n > 0 ? (matchedRefChunks / n) : 0.0;
      final bool hasSufficientCoverage = n <= 1
          ? (matchedRefChunks >= 1)
          : (n == 2 ? matchedRefChunks >= 2 : coverage >= 0.60);

      final String refWordStr = targetWindow.join('');

      if (wordScore <= threshold && hasSufficientCoverage) {
        debugLog?.call(
          '✅ ALIGN MATCH: ref word is "$refWordStr", heard word is "$heardWordStr" | Score: ${wordScore.toStringAsFixed(3)} <= $threshold (Coverage: ${(coverage * 100).toInt()}%)',
        );
        return AlignmentResult(
          bestI: bestI,
          bestJ: n,
          bestStartI: bestStartI,
          bestStartJ: 0,
          bestScore: wordScore,
          pureAcousticScore: bestNormDist,
          trace: finalTrace,
        );
      }

      final String reason = wordScore > threshold
          ? '(Score: ${wordScore.toStringAsFixed(3)} > $threshold)'
          : (!hasSufficientCoverage
                ? '(Insufficient Coverage: matched=$matchedRefChunks/$n)'
                : '(Failed Threshold)');

      debugLog?.call(
        '⏳ PENDING: ref word is "$refWordStr", heard word is "$heardWordStr" $reason',
      );
    }

    return null;
  }
}
