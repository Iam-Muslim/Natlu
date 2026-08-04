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

/// Parameters configuring the strictness of the DP alignment engine.
class AlignmentConfig {
  /// Maximum normalized penalty threshold allowed for a valid match.
  final double threshold;

  /// Penalty cost for omitting a reference phoneme (Deletions).
  final double costDel;

  /// Penalty cost for hallucinating an extra phoneme (Insertions).
  final double costIns;

  /// When true, enforces that the final reference phoneme has 0.0 penalty.
  final bool requireStableTail;

  const AlignmentConfig({
    required this.threshold,
    this.costDel = 1.0,
    this.costIns = 1.0,
    this.requireStableTail = false,
  });

  /// Factory helper for standard reciting strictness modes.
  factory AlignmentConfig.fromStrictness(
    String strictness, {
    bool isTajweed = false,
    double averagePhonemeDuration = 0.15,
  }) {
    double threshold = strictness == 'easy'
        ? 0.35
        : (strictness == 'strict' ? 0.15 : 0.25);

    double costDel = strictness == 'easy' ? 0.65 : 1.0;
    double costIns = strictness == 'easy' ? 0.65 : 1.0;

    // Fast Hadr recitation forgiveness
    if (averagePhonemeDuration < 0.08 && strictness != 'easy') {
      costDel = 0.75;
    }

    return AlignmentConfig(
      threshold: threshold,
      costDel: costDel,
      costIns: costIns,
      requireStableTail: isTajweed,
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
  Int32List _prevStartJ = Int32List(256);
  Int32List _currStartI = Int32List(256);
  Int32List _currStartJ = Int32List(256);
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
    final bool requireStableTail = config.requireStableTail;

    final int m = currentAsrChunks.length;
    final int n = targetWindow.length;

    if (m == 0 || n == 0) return null;

    final int requiredN = n + 1;
    if (_prevCost.length < requiredN) {
      int newCap = max(requiredN, _prevCost.length * 2);
      _prevCost = Float64List(newCap);
      _currCost = Float64List(newCap);
      _prevStartI = Int32List(newCap);
      _prevStartJ = Int32List(newCap);
      _currStartI = Int32List(newCap);
      _currStartJ = Int32List(newCap);
    }

    final int requiredOp = (m + 1) * (n + 1);
    if (_op.length < requiredOp) {
      int newCap = max(requiredOp, _op.length * 2);
      _op = Uint8List(newCap);
    }

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
    final Int32List prevStartJ = _prevStartJ;
    final Int32List currStartI = _currStartI;
    final Int32List currStartJ = _currStartJ;
    final Uint8List op = _op;
    final int opStride = n + 1;

    for (int j = 0; j <= n; j++) {
      prevCost[j] = j * costDel;
      prevStartI[j] = 0;
      prevStartJ[j] = 0;
    }

    double bestNormDist = double.infinity;
    int bestI = -1;
    int bestJ = -1;
    int bestStartI = 0;
    int bestStartJ = 0;

    for (int i = 1; i <= m; i++) {
      currCost[0] = 0.0;
      currStartI[0] = i;
      currStartJ[0] = 0;

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
        int sJ = prevStartJ[j - 1];

        if (delCost < minVal) {
          minVal = delCost;
          choice = AlignmentOp.insert.index;
          sI = prevStartI[j];
          sJ = prevStartJ[j];
        }

        if (insCost < minVal) {
          minVal = insCost;
          choice = AlignmentOp.delete.index;
          sI = currStartI[j - 1];
          sJ = currStartJ[j - 1];
        }

        currCost[j] = minVal;
        currStartI[j] = sI;
        currStartJ[j] = sJ;
        op[i * opStride + j] = choice;

        if (j == n) {
          final int lengthRef = j - sJ;
          final int lengthAsr = i - sI;
          final int denom = max(lengthRef, lengthAsr);

          if (denom > 0) {
            final double normDist = minVal / denom;
            if (normDist <= bestNormDist) {
              bestNormDist = normDist;
              bestI = i;
              bestJ = j;
              bestStartI = sI;
              bestStartJ = sJ;
            }
          }
        }
      }

      for (int k = 0; k <= n; k++) {
        prevCost[k] = currCost[k];
        prevStartI[k] = currStartI[k];
        prevStartJ[k] = currStartJ[k];
      }
    }

    if (bestI != -1 && bestNormDist <= (threshold + 0.35)) {
      int currI = bestI;
      int currJ = bestJ;
      final List<PhonemeGroupAlignment> trace = [];
      final List<double> wordConfs = [];

      while (currI > bestStartI || currJ > bestStartJ) {
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
        if (currJ == bestStartJ) {
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

          if (asrYsProbs != null && currI - 1 < asrYsProbs.length) {
            wordConfs.add(exp(asrYsProbs[currI - 1]));
          }

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
          refIdx: a.refIdx >= 0 ? a.refIdx - bestStartJ : -1,
          predIdx: a.predIdx >= 0 ? a.predIdx - bestStartI : -1,
        );
      }).toList();

      double totalPenalty = 0.0;
      int asrLen = 0;
      int refLen = 0;
      String heardWordStr = '';
      double wordTailCost = 0.0;

      for (int aIdx = 0; aIdx < finalTrace.length; aIdx++) {
        final align = finalTrace[aIdx];

        if (align.opType == 'delete') {
          wordTailCost = costDel;
        } else if (align.predIdx >= 0 && align.opType != 'insert') {
          wordTailCost = PhonemeMatrix.getCost(
            pIds[bestStartI + align.predIdx],
            rIds[bestStartJ + align.refIdx],
          );
        }

        if (align.predIdx >= 0) {
          asrLen++;
          heardWordStr += currentAsrChunks[bestStartI + align.predIdx];
        }
        if (align.refIdx >= 0) {
          refLen++;
        }

        if (align.opType == 'insert') {
          totalPenalty += costIns;
        } else if (align.opType == 'delete') {
          totalPenalty += costDel;
        } else if (align.opType == 'replace') {
          final double exactCost = PhonemeMatrix.getCost(
            pIds[bestStartI + align.predIdx],
            rIds[bestStartJ + align.refIdx],
          );
          totalPenalty += exactCost;
        }
      }

      int denom = max(asrLen, max(refLen, 1));
      if (denom < 4) denom = 4;
      final double wordScore = totalPenalty / denom;
      final bool passesTailAnchor =
          !requireStableTail || wordTailCost == 0.0;
      final String refWordStr = targetWindow.join('');

      if (wordScore <= threshold && passesTailAnchor) {
        debugLog?.call(
          '✅ COMMIT: ref word is "$refWordStr", heard word is "$heardWordStr" | Score: ${wordScore.toStringAsFixed(3)} <= $threshold (Threshold)',
        );
        return AlignmentResult(
          bestI: bestI,
          bestJ: bestJ,
          bestStartI: bestStartI,
          bestStartJ: bestStartJ,
          bestScore: wordScore,
          pureAcousticScore: bestNormDist,
          trace: finalTrace,
        );
      }

      // Acoustic Shielding
      if (wordScore <= 0.65) {
        double minConf = 1.0;
        if (wordConfs.isNotEmpty) {
          minConf = wordConfs.reduce((a, b) => a < b ? a : b);
        }

        if (minConf < 0.80 && wordScore <= 0.45 && passesTailAnchor) {
          debugLog?.call(
            '✅ SHIELD-PROMOTE: ref word is "$refWordStr", heard word is "$heardWordStr" | '
            'Score: ${wordScore.toStringAsFixed(3)} ≤ 0.45 with low ASR conf (${(minConf * 100).toStringAsFixed(1)}%) → GREEN',
          );
          return AlignmentResult(
            bestI: bestI,
            bestJ: bestJ,
            bestStartI: bestStartI,
            bestStartJ: bestStartJ,
            bestScore: wordScore,
            pureAcousticScore: bestNormDist,
            trace: finalTrace,
          );
        }
      }

      final String reason = wordScore > threshold
          ? '(Score: ${wordScore.toStringAsFixed(3)} > $threshold)'
          : '(Failed Tail Anchor: TailCost=$wordTailCost)';
      debugLog?.call(
        '❌ REFUSE: ref word is "$refWordStr", heard word is "$heardWordStr" | $reason',
      );
      return null;
    }

    return null;
  }
}
