import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';
import 'models/alignment_models.dart';
import 'phoneme_matrix.dart';

export 'models/alignment_models.dart';

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
    /// Incoming phonetic tokens from the speech recognizer.
    required List<String> currentAsrChunks,

    /// Target reference phonemes for the expected word.
    required List<String> targetWindow,

    /// The active Word ID being evaluated.
    required int expectedWord,

    /// Tuning parameters, thresholds, and penalty weights.
    required AlignmentConfig config,

    /// Optional pre-encoded integer IDs for the target window (skips encoding string phonemes in hot loop).
    Int32List? targetEncodedIds,

    /// Optional acoustic log probabilities for ASR fault mitigation.
    List<double>? asrYsProbs,

    /// Callback for diagnostic isolate logging.
    void Function(String)? debugLog,
  }) {
    final double threshold = config.threshold;
    final double costDel = config.costDel;
    final double costIns = config.costIns;
    final bool requireStableTail = config.requireStableTail;
    // -------------------------------------------------------------------------
    // Dimension Setup
    // m = Length of ASR string.
    // n = Length of Reference string (current expected word).
    // The DP matrix will theoretically be (m) rows by (n) columns.
    // -------------------------------------------------------------------------
    int m = currentAsrChunks.length;
    int n = targetWindow.length;

    // -------------------------------------------------------------------------
    // Reusable Scratchpad Buffer Management (Zero Allocations)
    // -------------------------------------------------------------------------
    if (_prevCost.length <= n + 1) {
      int newSize = max(n + 10, _prevCost.length * 2);
      _prevCost = Float64List(newSize);
      _currCost = Float64List(newSize);
      _prevStartI = Int32List(newSize);
      _prevStartJ = Int32List(newSize);
      _currStartI = Int32List(newSize);
      _currStartJ = Int32List(newSize);
    }
    if (_pIds.length <= m) {
      _pIds = Int32List(max(m + 10, _pIds.length * 2));
    }
    int opSize = (m + 1) * (n + 1);
    if (_op.length < opSize) {
      _op = Uint8List(max(opSize + 100, _op.length * 2));
    }

    // -------------------------------------------------------------------------
    // Instant Integer Encoding
    // -------------------------------------------------------------------------
    Int32List pIds = _pIds;
    for (int i = 0; i < m; i++) {
      pIds[i] = PhonemeMatrix.encode(currentAsrChunks[i]);
    }

    Int32List rIds;
    if (targetEncodedIds != null) {
      rIds = targetEncodedIds;
    } else {
      if (_rIds.length <= n) {
        _rIds = Int32List(max(n + 10, _rIds.length * 2));
      }
      rIds = _rIds;
      for (int j = 0; j < n; j++) {
        rIds[j] = PhonemeMatrix.encode(targetWindow[j]);
      }
    }

    Float64List prevCost = _prevCost;
    Float64List currCost = _currCost;
    Int32List prevStartI = _prevStartI;
    Int32List prevStartJ = _prevStartJ;
    Int32List currStartI = _currStartI;
    Int32List currStartJ = _currStartJ;
    Uint8List op = _op;

    // -------------------------------------------------------------------------
    // Initialization: Row 0
    // -------------------------------------------------------------------------
    // Top-left origin starts at 0.0 cost.
    prevCost[0] = 0.0;
    prevStartI[0] = 0;
    prevStartJ[0] = 0;

    for (int j = 1; j <= n; j++) {
      // Allow horizontal moves (Insertions / user dropped leading phoneme)
      if (prevCost[j - 1] < double.infinity) {
        prevCost[j] = prevCost[j - 1] + costIns;
        prevStartI[j] = prevStartI[j - 1];
        prevStartJ[j] = prevStartJ[j - 1];
        op[j] = 2; // Insertion
      } else {
        prevCost[j] = double.infinity;
        prevStartI[j] = -1;
        prevStartJ[j] = -1;
      }
    }

    // Trackers for the absolute best path found in the entire matrix.
    int bestI = -1;
    int bestJ = -1;
    int bestStartI = -1;
    int bestStartJ = -1;
    double bestScore = double.infinity;
    double bestNormDist = double.infinity;

    // -------------------------------------------------------------------------
    // THE CORE DP LOOP
    // -------------------------------------------------------------------------
    // We iterate over every incoming ASR chunk (i).
    for (int i = 1; i <= m; i++) {
      // Initialize the first column: allow matching to start at any incoming ASR audio chunk,
      // naturally skipping any preceding background noise or speech.
      currCost[0] = 0.0;
      currStartI[0] = i;
      currStartJ[0] = 0;

      // Grab the Integer ID of the current ASR phoneme.
      int pId = pIds[i - 1];

      // Inner loop: Iterate over every reference chunk (j).
      for (int j = 1; j <= n; j++) {
        int rId = rIds[j - 1];
        double matchCost = PhonemeMatrix.getCost(pId, rId);

        // Path 1: Substitution / Match
        double subCost = prevCost[j - 1] + matchCost;
        int subStartI = prevStartI[j - 1];
        int subStartJ = prevStartJ[j - 1];

        // Fresh word start at ASR chunk (i-1)
        if (j == 1 && matchCost < subCost) {
          subCost = matchCost;
          subStartI = i - 1;
          subStartJ = 0;
        }

        // Path 2: Deletion (ASR hallucinated an extra sound)
        double delCost = prevCost[j] + costDel;
        int delStartI = prevStartI[j];
        int delStartJ = prevStartJ[j];

        // Path 3: Insertion (ASR missed a reference sound)
        double insCost = currCost[j - 1] + costIns;
        int insStartI = currStartI[j - 1];
        int insStartJ = currStartJ[j - 1];

        if (j == 1 && costIns < insCost) {
          insCost = costIns;
          insStartI = i;
          insStartJ = 0;
        }

        // Decision Making: Pick the cheapest path
        if (subCost <= delCost && subCost <= insCost) {
          currCost[j] = subCost;
          currStartI[j] = subStartI;
          currStartJ[j] = subStartJ;
          op[i * (n + 1) + j] = 0;
        } else if (delCost <= insCost) {
          currCost[j] = delCost;
          currStartI[j] = delStartI;
          currStartJ[j] = delStartJ;
          op[i * (n + 1) + j] = 1;
        } else {
          currCost[j] = insCost;
          currStartI[j] = insStartI;
          currStartJ[j] = insStartJ;
          op[i * (n + 1) + j] = 2;
        }
      }

      // -----------------------------------------------------------------------
      // End-of-Row Scoring Evaluation (Strict Word End at j = n)
      // -----------------------------------------------------------------------
      if (currCost[n] < double.infinity) {
        int stI = currStartI[n];
        int stJ = currStartJ[n];

        if (stI >= 0 && stJ == 0) {
          int refLen = n - stJ;
          int asrLen = i - stI;

          if (refLen > 0) {
            int denom = max(asrLen, max(refLen, 1));
            if (denom < 4) denom = 4;

            double normDist = currCost[n] / denom;

            if (normDist <= threshold) {
              // [EDGE-BOUND TAIL STABILITY RULE]
              bool isStable = true;
              if (requireStableTail && i == m && op[i * (n + 1) + n] == 2) {
                isStable = false;
              }

              if (isStable && (bestI == -1 || normDist < bestScore)) {
                bestScore = normDist;
                bestNormDist = normDist;
                bestI = i;
                bestJ = n;
                bestStartI = stI;
                bestStartJ = stJ;
              }
            }
          }
        }
      }

      // -----------------------------------------------------------------------
      // Row Swapping (O(n) Memory)
      // -----------------------------------------------------------------------
      final tmpC = prevCost;
      prevCost = currCost;
      currCost = tmpC;

      final tmpSI = prevStartI;
      prevStartI = currStartI;
      currStartI = tmpSI;

      final tmpSJ = prevStartJ;
      prevStartJ = currStartJ;
      currStartJ = tmpSJ;
    }

    // -------------------------------------------------------------------------
    // Matrix Finished. Traceback Extraction.
    // -------------------------------------------------------------------------
    if (bestI != -1) {
      if (debugLog != null) {
        String matchedAsr = currentAsrChunks.sublist(bestStartI, bestI).join('');
        String matchedRef = targetWindow.sublist(bestStartJ, bestJ).join('');
        debugLog(
          '✅ [DP SUCCESS] Matched: "$matchedAsr" ➔ "$matchedRef" | Score: ${bestScore.toStringAsFixed(3)} <= $threshold',
        );
      }

      List<PhonemeGroupAlignment> trace = [];
      int currI = bestI;
      int currJ = bestJ;

      // Traceback from the 1-byte array
      while (currI > bestStartI || currJ > bestStartJ) {
        int opType = op[currI * (n + 1) + currJ];

        if (currI > bestStartI && currJ > bestStartJ && opType == 0) {
          double sc = PhonemeMatrix.getCost(pIds[currI - 1], rIds[currJ - 1]);
          trace.add(
            PhonemeGroupAlignment(
              opType: sc <= 0.25 ? 'equal' : 'replace',
              refIdx: (currJ - 1) - bestStartJ,
              predIdx: (currI - 1) - bestStartI,
            ),
          );
          currI--;
          currJ--;
        } else if (currI > bestStartI && opType == 1) {
          trace.add(
            PhonemeGroupAlignment(
              opType: 'insert',
              refIdx: currJ > bestStartJ ? (currJ - 1) - bestStartJ : -1,
              predIdx: (currI - 1) - bestStartI,
            ),
          );
          currI--;
        } else if (currJ > bestStartJ) {
          trace.add(
            PhonemeGroupAlignment(
              opType: 'delete',
              refIdx: (currJ - 1) - bestStartJ,
              predIdx: currI > bestStartI ? (currI - 1) - bestStartI : -1,
            ),
          );
          currJ--;
        } else {
          break;
        }
      }

      List<PhonemeGroupAlignment> finalTrace = trace.reversed.toList();

      String pathStr = finalTrace
          .map((a) {
            if (a.opType == 'equal') return 'M';
            if (a.opType == 'replace') return 'S';
            if (a.opType == 'insert') return 'I';
            if (a.opType == 'delete') return 'D';
            return '?';
          })
          .join('-');
      debugLog?.call('🗺️ [DP PATH] $pathStr');

      // ═════════════════════════════════════════════════════════════════════════
      // [POST-PROCESSING] ZERO-ALLOCATION SCALAR WORD EVALUATION
      // ═════════════════════════════════════════════════════════════════════════
      int asrLen = 0;
      int refLen = 0;
      double totalPenalty = 0.0;
      double wordTailCost = 1.0;
      String heardWordStr = '';
      List<double> wordConfs = [];

      for (var align in finalTrace) {
        if (align.predIdx >= 0 &&
            asrYsProbs != null &&
            (bestStartI + align.predIdx) < asrYsProbs.length) {
          int globalIndex = bestStartI + align.predIdx;
          double confidencePercentage = exp(asrYsProbs[globalIndex]);
          wordConfs.add(confidencePercentage);
        }

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
          double exactCost = PhonemeMatrix.getCost(
            pIds[bestStartI + align.predIdx],
            rIds[bestStartJ + align.refIdx],
          );
          totalPenalty += exactCost;
        }
      }

      int denom = max(asrLen, max(refLen, 1));
      if (denom < 4) denom = 4;
      double wordScore = totalPenalty / denom;
      bool passesTailAnchor = !requireStableTail || wordTailCost == 0.0;
      String refWordStr = targetWindow.join('');

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
          words: [WordMatch(wordId: expectedWord, score: wordScore)],
          shieldedWords: const [],
        );
      }

      // [CASE 2 ACOUSTIC SHIELDING]
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
            words: [WordMatch(wordId: expectedWord, score: wordScore)],
            shieldedWords: const [],
          );
        }
      }

      String reason = wordScore > threshold
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
