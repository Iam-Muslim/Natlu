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

      // Try current word → skip+1 → skip+2
      for (int skip = 0;
          skip <= config.maxSkipWords &&
              targetWordCursor + skip < wordCount;
          skip++) {
        final int w = targetWordCursor + skip;
        if (w >= wordStartChunk.length || w >= wordEndChunk.length) break;

        final result = _matcher.matchWord(
          asrTokens: unconsumed,
          asrTimestamps: unconsumedTs,
          refChunks: refChunks,
          refStart: wordStartChunk[w],
          refEnd: wordEndChunk[w],
          refEncodedIds: refEncodedIds,
          config: config,
        );

        if (result != null) {
          if (result.isPartial) {
            // The word is partially matched (still being spoken).
            // We MUST wait for more audio to prevent jumping ahead prematurely.
            if (skip == 0) {
              matched = false;
              break; // Stop looking ahead, wait for next segment
            } else {
              continue; // A future word is partially matched, ignore for now
            }
          }

          if (result.tokensConsumed > 0) {
            // Mark skipped words RED
            for (int s = 0; s < skip; s++) {
              _commitRed(targetWordCursor + s, w);
            }
            // Mark matched word GREEN
            _commitGreen(w, result, unconsumed, unconsumedTs);

          asrTokenAnchor += result.tokensConsumed;
          targetWordCursor = w + 1;
          matched = true;
          break;
        }
        }
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
}
