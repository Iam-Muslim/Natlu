import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../common/quran_normalizer.dart';
import '../tajweed/error_explainer.dart';
import 'dictation_matcher.dart';
import 'phoneme_alignment_isolate.dart';
import 'phoneme_matrix.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Forward Dictation Sequencer
//
// Per-word sequential matching with anchored consumption:
// 1. Slice the ASR buffer at the anchor (drop consumed tokens).
// 2. Try matching the current word. If GREEN → commit, advance anchor & cursor.
// 3. If current word fails, try skip+1 and skip+2 (omission detection).
// 4. If nothing matches → stay NEUTRAL, wait for more tokens.
// 5. Loop: after each commit, immediately try the next word.
// ═══════════════════════════════════════════════════════════════════════════════

class DictationSequencer {
  final SendPort mainSendPort;

  // ── Reference ──
  List<int> wordBoundaries = [];
  List<String> refChunks = [];
  List<int> chunkToWordMap = [];
  List<int> wordStartChunk = [];
  List<int> wordEndChunk = [];
  Int32List refEncodedIds = Int32List(0);
  bool isTajweed = false;
  int currentSurahNumber = 0;

  // ── ASR Stream ──
  List<String> currentSegmentAsrTokens = [];
  List<double> currentSegmentTimestamps = [];
  int asrTokenAnchor = 0;

  // ── Tracking ──
  int targetWordCursor = 0;
  final Set<int> committedGreenWords = {};
  final Set<int> committedRedWords = {};
  String? lastMatchedPhoneme;

  final QuranDictationMatcher _matcher = QuranDictationMatcher();
  final AlignmentConfig config = const AlignmentConfig();

  DictationSequencer(this.mainSendPort);

  int get _wordCount => max(0, wordBoundaries.length - 1);

  void debugLog(String message) {
    final buf = (asrTokenAnchor < currentSegmentAsrTokens.length)
        ? currentSegmentAsrTokens.sublist(asrTokenAnchor).join('')
        : '';
    mainSendPort
        .send(DebugLogEvent(message: message, asrBuffer: buf).toMap());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Public API (called from Isolate message handler)
  // ─────────────────────────────────────────────────────────────────────────────

  void setSurahReference(SetSurahReferenceCommand cmd) {
    PhonemeMatrix.reset();
    currentSurahNumber = cmd.surahNumber;
    final phonemes = cmd.fullPhonemes.replaceAll(' ', '');
    wordBoundaries = cmd.boundaries;
    isTajweed = cmd.isTajweed;

    final int wordCount = _wordCount;
    refChunks = [];
    chunkToWordMap = [];
    wordStartChunk = List.filled(wordCount, 0);
    wordEndChunk = List.filled(wordCount, 0);

    for (int w = 0; w < wordCount; w++) {
      final int start = wordBoundaries[w];
      final int end = (w + 1 < wordBoundaries.length)
          ? wordBoundaries[w + 1]
          : phonemes.length;
      if (start >= phonemes.length) break;
      final int safeEnd = min(end, phonemes.length);
      final chunks =
          QuranNormalizer.chunkPhonemes(phonemes.substring(start, safeEnd));

      wordStartChunk[w] = refChunks.length;
      for (final ch in chunks) {
        chunkToWordMap.add(w);
        refChunks.add(ch);
      }
      wordEndChunk[w] = refChunks.length;
    }

    PhonemeMatrix.preheat(refChunks);
    refEncodedIds = Int32List(refChunks.length);
    for (int i = 0; i < refChunks.length; i++) {
      refEncodedIds[i] = PhonemeMatrix.encode(refChunks[i]);
    }

    committedGreenWords.clear();
    committedRedWords.clear();
    asrTokenAnchor = 0;

    if (cmd.forceClear) {
      currentSegmentAsrTokens = [];
      currentSegmentTimestamps = [];
    }

    targetWordCursor = cmd.startGlobalWord.clamp(0, wordCount);
    lastMatchedPhoneme = null;

    debugLog(
        '📖 Surah $currentSurahNumber | $wordCount words | cursor=$targetWordCursor | tajweed=$isTajweed');

    if (!cmd.forceClear && currentSegmentAsrTokens.isNotEmpty) {
      _processSequence();
    }
  }

  void jumpToWord(JumpToWordCommand cmd) {
    targetWordCursor = cmd.globalWordIndex.clamp(0, _wordCount);
    currentSegmentAsrTokens = [];
    currentSegmentTimestamps = [];
    asrTokenAnchor = 0;
    lastMatchedPhoneme = null;
    committedGreenWords.removeWhere((w) => w >= targetWordCursor);
    committedRedWords.removeWhere((w) => w >= targetWordCursor);
    debugLog('🎯 Jumped to word $targetWordCursor');
  }

  void syncStream(SyncStreamCommand cmd) {
    if (cmd.isNewSegment) {
      currentSegmentAsrTokens = [];
      currentSegmentTimestamps = [];
      asrTokenAnchor = 0;
      debugLog('🔄 New segment');
    }
    currentSegmentAsrTokens = cmd.asrTokens;
    currentSegmentTimestamps = cmd.timestamps;
    _processSequence();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Core Tracking Loop
  // ─────────────────────────────────────────────────────────────────────────────

  void _processSequence() {
    final int wordCount = _wordCount;

    while (asrTokenAnchor < currentSegmentAsrTokens.length &&
        targetWordCursor < wordCount) {
      final unconsumed = currentSegmentAsrTokens.sublist(asrTokenAnchor);
      final int tsStart =
          min(asrTokenAnchor, currentSegmentTimestamps.length);
      final unconsumedTs = currentSegmentTimestamps.sublist(tsStart);

      bool matched = false;
      bool waitingForPartial = false;

      // Outer loop: how many words to SKIP (0 = no skip, 1 = skip W, etc.)
      for (int skip = 0; skip <= config.maxSkipWords && targetWordCursor + skip < wordCount; skip++) {
        final int startW = targetWordCursor + skip;
        
        // Inner loop: try single word first, then try merging with the next word (Wasl handling)
        for (int merge = 1; merge <= 2; merge++) {
          final int endW = startW + merge - 1;
          if (endW >= wordCount) break;

          final result = _matcher.matchWord(
            asrTokens: unconsumed,
            asrTimestamps: unconsumedTs,
            refChunks: refChunks,
            refStart: wordStartChunk[startW],
            refEnd: wordEndChunk[endW],
            refEncodedIds: refEncodedIds,
            config: config,
          );

          if (result != null) {
            if (result.isPartial) {
              if (skip == 0) {
                waitingForPartial = true;
                break; // Stop looking ahead, wait for next segment
              } else {
                continue; // A future word is partially matched, ignore for now
              }
            }

            if (result.tokensConsumed > 0) {
              // Ensure that merged words are actually legitimate boundary-merges (Wasl/Idgham)
              // and not just a hallucinated word hiding behind a perfect word.
              if (merge > 1 && !_isValidMerge(result, startW, endW, unconsumed)) {
                continue; // Reject this merge and try another combination
              }

              // 1. Mark skipped words RED
              for (int s = 0; s < skip; s++) {
                _commitRed(targetWordCursor + s, startW);
              }
              // 2. Mark the matched (or merged) words GREEN
              for (int m = 0; m < merge; m++) {
                final w = startW + m;
                _commitGreen(w, result, unconsumed, unconsumedTs);
              }

              asrTokenAnchor += result.tokensConsumed;
              targetWordCursor = endW + 1;
              matched = true;
              break;
            }
          }
        }
        
        if (matched || waitingForPartial) break;
      }

      if (!matched) break; // Wait for more ASR tokens
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Commit Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  void _commitGreen(int w, WordMatchResult result, List<String> slicedTokens,
      List<double> slicedTs) {
    if (committedGreenWords.contains(w)) return;
    committedGreenWords.add(w);
    committedRedWords.remove(w);

    // Tajweed evaluation
    List<Map<String, dynamic>>? tajweedErrors;
    if (isTajweed && result.trace.isNotEmpty) {
      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: result.trace,
        globalRefChunks: refChunks,
        refChunkToWordMap: chunkToWordMap,
        currentAsrChunks: slicedTokens,
        trackingTimestamps: slicedTs,
        bestAsrStartIdx: 0,
        targetChunkCursor: 0,
        startWordId: w,
        nextWordId: w + 1,
        totalAyahWords: max(1, _wordCount),
        previousWordTail: lastMatchedPhoneme,
      );
      if (errors.containsKey(w)) {
        tajweedErrors = errors[w]!.map((e) => e.toMap()).toList();
      }
    }

    final String refText = _getWordReference(w);
    debugLog(
        '✅ [GREEN] Word $w (Ref: "$refText") -> ASR: "${result.cleanAsr}" (cost=${result.pathCost.toStringAsFixed(2)})');

    mainSendPort.send(WordMatchedEvent(
      wordId: w,
      score: max(0.0, 1.0 - result.pathCost),
      cleanAsr: result.cleanAsr,
      isRed: false,
      isNeutral: false,
      tajweedErrors: tajweedErrors,
    ).toMap());

    if (w < wordEndChunk.length && wordEndChunk[w] - 1 < refChunks.length) {
      lastMatchedPhoneme = refChunks[wordEndChunk[w] - 1];
    }
  }

  void _commitRed(int w, int matchedWordIndex) {
    if (committedRedWords.contains(w) || committedGreenWords.contains(w)) {
      return;
    }
    committedRedWords.add(w);

    final String refText = _getWordReference(w);
    final String matchedRefText = _getWordReference(matchedWordIndex);
    
    debugLog('❌ [RED] Word $w (Ref: "$refText") skipped because lookahead matched Word $matchedWordIndex (Ref: "$matchedRefText")');

    mainSendPort.send(WordMatchedEvent(
      wordId: w,
      score: 0.0,
      cleanAsr: '',
      isRed: true,
      isNeutral: false,
    ).toMap());
  }

  String _getWordReference(int w) {
    if (w < 0 || w >= wordStartChunk.length || w >= wordEndChunk.length) return "";
    return refChunks.sublist(wordStartChunk[w], wordEndChunk[w]).join('');
  }

  bool _isValidMerge(WordMatchResult result, int startW, int endW, List<String> asrTokens) {
    if (startW == endW) return true;

    // The merge feature is specifically for Idgham, Iqlab, Wasl, etc., which happen at the BOUNDARIES.
    // To prevent a completely wrong word (e.g. "المبين") from piggybacking on a correct word,
    // we must verify that the "Core" (the middle) of EVERY word in the merge is highly accurate.
    for (int w = startW; w <= endW; w++) {
      final int refStart = wordStartChunk[w];
      final int refEnd = wordEndChunk[w];
      final int wordLen = refEnd - refStart;
      
      // We forgive up to 2 phonemes at the junction (Idgham/Wasl zones).
      final int forgiveStart = (w > startW) ? min(2, wordLen ~/ 3) : 0;
      final int forgiveEnd = (w < endW) ? min(2, wordLen ~/ 3) : 0;
      
      final int coreStart = refStart + forgiveStart;
      final int coreEnd = refEnd - forgiveEnd;
      final int coreLen = coreEnd - coreStart;
      
      if (coreLen <= 0) continue; // Word too short to have a distinct core

      double coreCost = 0.0;

      for (final align in result.trace) {
        if (align.refIdx >= coreStart && align.refIdx < coreEnd) {
          if (align.opType == 'delete') {
            coreCost += config.costDel;
          } else if (align.opType == 'replace') {
             if (align.predIdx >= 0 && align.refIdx >= 0 && align.predIdx < asrTokens.length) {
                final rId = refEncodedIds[align.refIdx];
                final pId = PhonemeMatrix.encode(asrTokens[align.predIdx]);
                coreCost += PhonemeMatrix.getCost(pId, rId);
             } else {
                coreCost += config.costIns; // Fallback
             }
          }
        }
      }
      
      // If the core of any individual word exceeds the threshold, the whole merge is INVALID.
      // This stops "المبين" from hiding behind "أكان".
      if ((coreCost / coreLen) > config.maxPathCost) {
        return false;
      }
    }
    return true;
  }
}
