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

/// Parameters configuring the behavior of the DP alignment engine.
class AlignmentConfig {
  /// Maximum normalized penalty threshold allowed for a valid match.
  final double threshold;

  /// Penalty cost for omitting a reference phoneme (Deletions).
  final double costDel;

  /// Penalty cost for hallucinating an extra phoneme (Insertions).
  final double costIns;

  const AlignmentConfig({
    required this.threshold,
    this.costDel = 1.0,
    this.costIns = 1.0,
  });

  /// Factory helper for standard reciting mode.
  factory AlignmentConfig.defaultConfig({
    bool isTajweed = false,
  }) {
    return AlignmentConfig(
      threshold: 0.25,
      costDel: 1.0,
      costIns: 1.0,
    );
  }

  /// Creates a copy of this config with updated fields.
  AlignmentConfig copyWith({
    double? threshold,
    double? costDel,
    double? costIns,
  }) {
    return AlignmentConfig(
      threshold: threshold ?? this.threshold,
      costDel: costDel ?? this.costDel,
      costIns: costIns ?? this.costIns,
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
  final List<PhonemeGroupAlignment> trace;

  const AlignmentResult({
    required this.bestI,
    required this.bestJ,
    required this.bestStartI,
    required this.bestStartJ,
    required this.bestScore,
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
  Int32List _prevStartJ = Int32List(256);
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
    Set<int>? validStartChunks,
    Set<int>? validEndChunks,
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
      _prevStartJ = Int32List(newCap);
      _currStartJ = Int32List(newCap);
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
    final Int32List prevStartJ = _prevStartJ;
    final Int32List currStartJ = _currStartJ;
    final Uint8List op = _op;
    final int opStride = n + 1;

    double currentDelCost = 0.0;
    int currentStartJ = 0;
    for (int j = 0; j <= n; j++) {
      bool isBoundary = validStartChunks != null ? validStartChunks.contains(j) : (j == 0);
      if (isBoundary) {
        currentDelCost = 0.0;
        currentStartJ = j;
      }
      prevCost[j] = currentDelCost;
      prevStartI[j] = 0;
      prevStartJ[j] = currentStartJ;
      
      currentDelCost += costDel;
    }

    double bestNormDist = double.infinity;
    int bestI = -1;
    int bestJ = -1;
    int bestStartI = 0;
    int bestStartJ = 0;

    for (int i = 1; i <= m; i++) {
      currCost[0] = 0.0;
      currStartI[0] = 0;
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
        int sI = (j == 1) ? (i - 1) : prevStartI[j - 1];
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

        if (validStartChunks != null && validStartChunks.contains(j - 1)) {
          double restartCost = matchCost;
          if (restartCost < minVal) {
            minVal = restartCost;
            choice = AlignmentOp.replace.index;
            sI = i - 1;
            sJ = j - 1;
          }
        }

        currCost[j] = minVal;
        currStartI[j] = sI;
        currStartJ[j] = sJ;
        op[i * opStride + j] = choice;

        bool isBoundary = false;
        if (validEndChunks != null) {
          isBoundary = validEndChunks.contains(j);
        } else {
          isBoundary = (j == n);
        }

        if (isBoundary) {
          final int lengthAsr = i - sI;
          final int lengthRef = j - sJ;
          final int denom = max(lengthRef, lengthAsr);
          if (denom > 0) {
            final double normDist = minVal / denom;

            // Forward skips (sJ > 0) require robust evidence to prevent trailing syllables
            // of the previous word from triggering false jumps over the cursor word:
            // - For multi-word skips (wordsSkipped >= 2): strictly require >= 3 reference chunks.
            // - For single-word skips (wordsSkipped <= 1): allow 2 reference chunks if buffer has >= 3 tokens (preceding speech) and exact/near-exact match (normDist <= 0.05).
            final bool isForwardJump = (sJ > 0);
            int wordsSkipped = 0;
            if (validStartChunks != null && isForwardJump) {
              wordsSkipped = validStartChunks.where((start) => start < sJ).length;
            }
            final bool hasValidEvidence = !isForwardJump ||
                (lengthRef >= 3 && lengthAsr >= 3) ||
                (lengthRef == 2 && lengthAsr >= 2 && wordsSkipped <= 1 && m >= 3 && normDist <= 0.05);

            final bool hasPotentialCoverage = (lengthRef <= 1) || (lengthAsr >= (lengthRef * 0.50).floor());

            if (hasValidEvidence && hasPotentialCoverage) {
              final double skipPenalty = isForwardJump ? (wordsSkipped * 0.050) : 0.0;
              final double effectiveNormDist = normDist + skipPenalty;

              bool shouldUpdate = false;
              if (bestI == -1) {
                shouldUpdate = isForwardJump
                    ? (effectiveNormDist <= threshold * 0.80)
                    : (effectiveNormDist <= threshold);
              } else if (sJ == bestStartJ) {
                // Same starting anchor: prefer lower normalized distance,
                // or if tied, prefer ASR length closest to reference length (minimal insertion parsimony)
                if (effectiveNormDist < bestNormDist - 0.001) {
                  shouldUpdate = true;
                } else if ((effectiveNormDist - bestNormDist).abs() <= 0.001) {
                  final int currDiff = (lengthAsr - lengthRef).abs();
                  final int bestDiff = ((bestI - bestStartI) - (bestJ - bestStartJ)).abs();
                  shouldUpdate = (currDiff < bestDiff);
                }
              } else if (sJ == 0) {
                shouldUpdate = (effectiveNormDist <= threshold);
              } else if (bestStartJ == 0 && bestNormDist <= threshold) {
                shouldUpdate = false;
              } else if (sJ < bestStartJ) {
                shouldUpdate = (effectiveNormDist <= bestNormDist + 0.05 && effectiveNormDist <= threshold);
              } else {
                shouldUpdate = (bestNormDist > threshold && effectiveNormDist <= threshold * 0.90);
              }

              if (shouldUpdate) {
                bestNormDist = effectiveNormDist;
                bestI = i;
                bestJ = j;
                bestStartI = sI;
                bestStartJ = sJ;
              }
            }
          }
        }
      }

      // Fast block transfer from curr to prev
      prevCost.setRange(0, n + 1, currCost);
      prevStartI.setRange(0, n + 1, currStartI);
      prevStartJ.setRange(0, n + 1, currStartJ);
    }

    final int firstWordEndChunk = (validEndChunks != null && validEndChunks.isNotEmpty)
        ? validEndChunks.first
        : n;

    if (debugLog != null && bestI != -1 && bestStartJ > 0) {
      debugLog('🔍 [ALIGN CANDIDATE] bestI=$bestI, bestJ=$bestJ, bestStartI=$bestStartI, bestStartJ=$bestStartJ, firstWordEndChunk=$firstWordEndChunk, m=$m');
    }

    // If candidate is a forward jump, verify that the unconsumed stream is NOT
    // an in-flight prefix of the current cursor word.
    if (bestI != -1 && bestStartJ > 0 && firstWordEndChunk > 1) {
      for (int j = 1; j < firstWordEndChunk; j++) {
        if (prevStartJ[j] == 0) {
          final double prefixScore = prevCost[j] / j;
          if (prefixScore <= threshold) {
            if (debugLog != null) {
              debugLog('🚫 [PREFIX GUARD] Blocking forward jump (bestStartJ=$bestStartJ) because cursor prefix j=$j is active (prefixScore=$prefixScore <= $threshold)');
            }
            return null;
          }
        }
      }
    }

    if (bestI != -1 && bestNormDist <= threshold) {
      int currI = bestI;
      int currJ = bestJ;
      final List<PhonemeGroupAlignment> trace = [];

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
            rIds[bestStartJ + align.refIdx],
          );
          totalPenalty += exactCost;
        }
      }

      final int matchLengthRef = bestJ - bestStartJ;
      final int denom = max(asrLen, max(matchLengthRef, 1));
      final double wordScore = totalPenalty / denom;

      final double coverage = matchLengthRef > 0 ? (matchedRefChunks / matchLengthRef) : 0.0;
      final bool hasSufficientCoverage = matchLengthRef <= 1
          ? (matchedRefChunks >= 1)
          : (matchLengthRef == 2 ? matchedRefChunks >= 2 : coverage >= 0.60);

      final String refWordStr = targetWindow.sublist(bestStartJ, bestJ).join('');

      // Pillar IV: Adaptive Length Scoring (Bayesian Length-Normalized Scoring)
      // Relax the threshold for shorter words where a single penalty creates a huge average cost.
      final int effectiveRefLen = max(matchLengthRef, 1);
      final double adaptiveThreshold = threshold * (1.0 + (1.5 / sqrt(effectiveRefLen)));

      if (wordScore <= adaptiveThreshold && hasSufficientCoverage) {
        debugLog?.call(
          '✅ ALIGN MATCH: ref word is "$refWordStr", heard word is "$heardWordStr" | Score: ${wordScore.toStringAsFixed(3)} <= ${adaptiveThreshold.toStringAsFixed(3)} (Coverage: ${(coverage * 100).toInt()}%)',
        );
        return AlignmentResult(
          bestI: bestI,
          bestJ: bestJ,
          bestStartI: bestStartI,
          bestStartJ: bestStartJ,
          bestScore: wordScore,
          trace: finalTrace,
        );
      }

      final String reason = wordScore > adaptiveThreshold
          ? '(Score: ${wordScore.toStringAsFixed(3)} > ${adaptiveThreshold.toStringAsFixed(3)})'
          : (!hasSufficientCoverage
                ? '(Insufficient Coverage: matched=$matchedRefChunks/$bestJ)'
                : '(Failed Threshold)');

      debugLog?.call(
        '⏳ PENDING: ref word is "$refWordStr", heard word is "$heardWordStr" $reason',
      );
    }

    return null;
  }
}
