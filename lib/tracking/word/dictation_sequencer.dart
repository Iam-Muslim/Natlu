import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../common/quran_normalizer.dart';
import '../tajweed/error_explainer.dart';
import 'dictation_matcher.dart';
import 'phoneme_alignment_isolate.dart';
import 'phoneme_matrix.dart';

/// Orchestrates incoming speech recognition audio against the active Surah reference.
///
/// Runs entirely inside the background alignment isolate:
/// - Manages the monotonic `targetWordCursor`.
/// - Slices active expected words for the DP alignment engine.
/// - Commits verified word matches and bridges phoneme tails for Tajweed checking.
/// - Emits typed [WordMatchedEvent] and [DebugLogEvent] back to the main UI thread.
class DictationSequencer {
  final SendPort mainSendPort;

  // ---------------------------------------------------------------------------
  // Reference State
  // ---------------------------------------------------------------------------
  List<int> wordBoundaries = [];
  List<String> refChunks = [];
  List<int> chunkToWordMap = [];

  bool isTajweed = false;

  // ---------------------------------------------------------------------------
  // ASR State
  // ---------------------------------------------------------------------------
  String currentSegmentAsr = '';
  List<double> currentSegmentTimestamps = [];
  int asrConsumedTokenCount = 0;

  // ---------------------------------------------------------------------------
  // Tracking Progress State
  // ---------------------------------------------------------------------------
  List<String> acceptedWordsAsr = [];
  List<List<double>> acceptedWordsTimestamps = [];

  /// Pointer to the active Word ID being tracked.
  int targetWordCursor = 0;

  /// Tail phoneme of the previous match for Tajweed assimilation rules.
  String? lastMatchedPhoneme;

  int currentSurahNumber = 0;
  int currentAyahNumber = 0;

  List<int> wordStartChunk = [];
  List<int> wordEndChunk = [];
  Int32List refEncodedIds = Int32List(0);

  final ForwardDictationMatcher _matcher = ForwardDictationMatcher();

  DictationSequencer(this.mainSendPort);

  void debugLog(String message) {
    mainSendPort.send(
      DebugLogEvent(message: message, asrBuffer: currentSegmentAsr).toMap(),
    );
  }

  /// Sets up a new continuous Surah reference in the background thread.
  void setSurahReference(SetSurahReferenceCommand cmd) {
    PhonemeMatrix.reset();
    currentSurahNumber = cmd.surahNumber;
    final String expectedPhonemes = cmd.fullPhonemes.replaceAll(' ', '');
    wordBoundaries = cmd.boundaries;
    isTajweed = cmd.isTajweed;

    final int wordCount = max(0, wordBoundaries.length - 1);
    refChunks = [];
    chunkToWordMap = [];
    wordStartChunk = List.filled(wordCount, 0);
    wordEndChunk = List.filled(wordCount, 0);

    for (int w = 0; w < wordCount; w++) {
      final int startChar = wordBoundaries[w];
      final int endChar = (w + 1 < wordBoundaries.length)
          ? wordBoundaries[w + 1]
          : expectedPhonemes.length;
      if (startChar >= expectedPhonemes.length) break;
      final int safeEnd = min(endChar, expectedPhonemes.length);
      final String wordStr = expectedPhonemes.substring(startChar, safeEnd);
      final List<String> wChunks = QuranNormalizer.chunkPhonemes(wordStr);

      wordStartChunk[w] = refChunks.length;
      for (final ch in wChunks) {
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

    if (cmd.forceClear) {
      currentSegmentAsr = '';
      currentSegmentTimestamps = [];
      asrConsumedTokenCount = 0;
      targetWordCursor = cmd.startGlobalWord.clamp(0, wordCount);
    } else {
      targetWordCursor = cmd.startGlobalWord.clamp(0, wordCount);
    }

    acceptedWordsAsr = List.filled(wordCount, '');
    acceptedWordsTimestamps = List.generate(wordCount, (_) => []);
    lastMatchedPhoneme = null;

    debugLog(
      '📖 [SURAH SET] Surah: $currentSurahNumber | Words: $wordCount | StartWord: $targetWordCursor | Tajweed: $isTajweed | Strict: normal',
    );

    if (!cmd.forceClear && currentSegmentAsr.isNotEmpty) {
      _processSequence();
    }
  }

  /// Jumps the tracking cursor to a specific global word index (e.g. manual Ayah selection).
  void jumpToWord(JumpToWordCommand cmd) {
    final int wordCount = wordBoundaries.length - 1;
    targetWordCursor = cmd.globalWordIndex.clamp(0, max(0, wordCount));

    currentSegmentAsr = '';
    currentSegmentTimestamps = [];
    asrConsumedTokenCount = 0;
    lastMatchedPhoneme = null;

    debugLog(
      '🎯 [JUMP TO WORD] Cursor jumped to global word $targetWordCursor (ASR state cleared)',
    );
  }

  /// Ingests streaming ASR audio data and triggers monotonic sequence evaluation.
  void syncStream(SyncStreamCommand cmd) {
    if (cmd.isNewSegment || cmd.asrText.length < currentSegmentAsr.length) {
      asrConsumedTokenCount = 0;
      debugLog(
        '🔄 [SYNC] New ASR segment started. Consumed tokens reset to 0.',
      );
    }

    currentSegmentAsr = cmd.asrText;
    currentSegmentTimestamps = cmd.timestamps;

    _processSequence();
  }

  /// Core alignment loop: matches unconsumed ASR tokens against the active expected word.
  void _processSequence() {
    if (currentSegmentAsr.isEmpty) return;

    final List<PhonemeToken> rawTokens =
        QuranNormalizer.chunkPhonemesWithIndices(currentSegmentAsr);
    final List<PhonemeToken> cleanTokens = rawTokens
        .where(
          (t) =>
              t.text.trim().isNotEmpty && t.text != '<blank>' && t.text != 'ؙ',
        )
        .toList();

    bool matchedSomething;
    do {
      matchedSomething = false;

      if (targetWordCursor >= wordBoundaries.length - 1) break;

      // Handle rollbacks in streaming ASR text
      if (cleanTokens.length < asrConsumedTokenCount) {
        asrConsumedTokenCount = cleanTokens.length;
      }

      List<PhonemeToken> unconsumedTokens = cleanTokens.sublist(
        asrConsumedTokenCount,
      );

      if (unconsumedTokens.isEmpty) break;

      int m = unconsumedTokens.length;

      // Buffer GC: prevent latency buildup if buffer exceeds ~6 seconds
      const int maxAsrChunks = 150;
      if (m > maxAsrChunks) {
        final int chunksToDrop = m - maxAsrChunks;
        asrConsumedTokenCount += chunksToDrop;
        unconsumedTokens = unconsumedTokens.sublist(chunksToDrop);
        m = unconsumedTokens.length;
        debugLog(
          '🗑️ [BUFFER GC] Dropped $chunksToDrop oldest tokens to prevent lag (Max $maxAsrChunks reached)',
        );
      }

      final int wordCount = wordBoundaries.length - 1;
      if (targetWordCursor >= wordCount ||
          targetWordCursor >= wordStartChunk.length ||
          targetWordCursor >= wordEndChunk.length) {
        break;
      }

      final int winStartChunk = wordStartChunk[targetWordCursor];
      final int winEndChunk = wordEndChunk[targetWordCursor];

      if (winStartChunk >= winEndChunk) break;

      final alignmentConfig = AlignmentConfig.defaultConfig(
        isTajweed: isTajweed,
      );

      final List<String> unconsumedStrings = unconsumedTokens
          .map((t) => t.text)
          .toList();

      // ── THE HOLY GRAIL: Single Full-Ayah Subsequence DTW ─────────
      // Tests the current word and any skips or connections up to the end of the Ayah.
      final int continuousEndChunk = wordEndChunk[wordCount - 1];

      final Set<int> validEnds = {};
      for (int w = targetWordCursor; w < wordCount; w++) {
        validEnds.add(wordEndChunk[w] - winStartChunk);
      }

      AlignmentResult? result = _alignWindow(
        asrStrings: unconsumedStrings,
        startChunk: winStartChunk,
        endChunk: continuousEndChunk,
        expectedWord: targetWordCursor,
        config: alignmentConfig,
        validEndChunks: validEnds,
      );

      if (result != null) {
        int matchedWordIdx = targetWordCursor;
        for (int w = targetWordCursor; w < wordCount; w++) {
          if (result.bestJ == (wordEndChunk[w] - winStartChunk)) {
            matchedWordIdx = w;
            break;
          }
        }

        // Emit skipped words for anything between targetWordCursor and matchedWordIdx (exclusive of the matched sequence)
        // Since Subsequence DTW naturaly traces the whole span, _commitMatch will handle it. 
        // But to properly trigger `_emitSkippedWord` UI events for skips, we can do it here if needed, 
        // or just rely on `_commitMatch`'s loop. However, `_commitMatch` emits `isRed: false`.
        // The rule says "Word status (GREEN/RED/NEUTRAL) is derived from traceback coverage analysis".
        // Let's rely on _commitMatch but we will need to update `_commitMatch` to check coverage.
        
        _commitMatch(
          result: result,
          unconsumedTokens: unconsumedTokens,
          fullCleanTokens: cleanTokens,
          targetWindow: refChunks.sublist(
            winStartChunk,
            wordEndChunk[matchedWordIdx],
          ),
          winStartChunk: winStartChunk,
          startWordId: targetWordCursor,
          endWordId: matchedWordIdx + 1,
        );
        matchedSomething = true;
        continue;
      }
    } while (matchedSomething);
  }



  /// Evaluates alignment for a specific reference window slice.
  AlignmentResult? _alignWindow({
    required List<String> asrStrings,
    required int startChunk,
    required int endChunk,
    required int expectedWord,
    required AlignmentConfig config,
    Set<int>? validEndChunks,
    bool suppressLogs = false,
  }) {
    return _matcher.align(
      currentAsrChunks: asrStrings,
      targetWindow: refChunks.sublist(startChunk, endChunk),
      expectedWord: expectedWord,
      config: config,
      validEndChunks: validEndChunks,
      targetEncodedIds: Int32List.sublistView(
        refEncodedIds,
        startChunk,
        endChunk,
      ),
      debugLog: suppressLogs ? null : debugLog,
    );
  }

  /// Emits a skipped (RED) or neutral word event to the UI thread.


  void _commitMatch({
    required AlignmentResult result,
    required List<PhonemeToken> unconsumedTokens,
    required List<PhonemeToken> fullCleanTokens,
    required List<String> targetWindow,
    required int winStartChunk,
    required int startWordId,
    int? endWordId,
  }) {
    final int endW = endWordId ?? (startWordId + 1);

    final int safeStartI = result.bestStartI.clamp(0, unconsumedTokens.length);
    final int safeEndI = result.bestI.clamp(
      safeStartI,
      unconsumedTokens.length,
    );
    final List<String> matchedAsrSlice = unconsumedTokens
        .sublist(safeStartI, safeEndI)
        .map((t) => t.text)
        .toList();

    final int safeStartJ = result.bestStartJ.clamp(0, targetWindow.length);
    final int safeEndJ = result.bestJ.clamp(safeStartJ, targetWindow.length);
    final List<String> matchedRefSlice = targetWindow.sublist(
      safeStartJ,
      safeEndJ,
    );

    final String heardStr = matchedAsrSlice.join('');
    final String refStr = matchedRefSlice.join('');
    debugLog(
      '✅ COMMITTED (GREEN): ref word is "$refStr", heard word is "$heardStr"',
    );

    final List<PhonemeGroupAlignment> localAlignments = result.trace;

    for (int w = startWordId; w < endW; w++) {
      String wordPredStr = '';
      final List<double> wordPredTs = [];

      for (final align in localAlignments) {
        if (align.refIdx < 0 && align.predIdx >= 0) continue; // Insertion
        if (align.refIdx >= 0 && align.predIdx < 0) continue; // Deletion

        if (align.refIdx < 0 || align.predIdx < 0) continue;
        
        final int absRefIdx = winStartChunk + safeStartJ + align.refIdx;
        if (absRefIdx >= chunkToWordMap.length) continue;

        final int wId = chunkToWordMap[absRefIdx];
        if (wId != w) continue;

        final int absPredIdx = safeStartI + align.predIdx;
        if (absPredIdx >= unconsumedTokens.length) continue;

        final String chunk = unconsumedTokens[absPredIdx].text;
        wordPredStr += chunk;

        final int globalTokenIdx = asrConsumedTokenCount + absPredIdx;
        final int charStart = _getCharIndexForToken(
          fullCleanTokens,
          globalTokenIdx,
        );

        for (int c = 0; c < chunk.length; c++) {
          if (charStart + c < currentSegmentTimestamps.length) {
            wordPredTs.add(currentSegmentTimestamps[charStart + c]);
          }
        }
      }

      if (w < acceptedWordsAsr.length) {
        acceptedWordsAsr[w] = wordPredStr;
      }
      if (w < acceptedWordsTimestamps.length) {
        acceptedWordsTimestamps[w] = wordPredTs;
      }
    }

    Map<int, List<ReciterError>>? tajweedErrors;
    if (isTajweed) {
      final int globalStartIdx = asrConsumedTokenCount + safeStartI;
      final int charStart = _getCharIndexForToken(
        fullCleanTokens,
        globalStartIdx,
      );
      final int safeCharIdx = min(charStart, currentSegmentTimestamps.length);

      tajweedErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: localAlignments,
        globalRefChunks: refChunks,
        refChunkToWordMap: chunkToWordMap,
        currentAsrChunks: matchedAsrSlice,
        trackingTimestamps: currentSegmentTimestamps.sublist(safeCharIdx),
        bestAsrStartIdx: 0,
        targetChunkCursor: winStartChunk + safeStartJ,
        startWordId: startWordId,
        nextWordId: endW,
        totalAyahWords: max(1, wordBoundaries.length - 1),
        previousWordTail: lastMatchedPhoneme,
      );
    }

    for (int w = startWordId; w < endW; w++) {
      List<Map<String, dynamic>>? serializedErrors;
      if (tajweedErrors != null && tajweedErrors.containsKey(w)) {
        serializedErrors = tajweedErrors[w]!.map((e) => e.toMap()).toList();
      }

      int matchedRefChunks = 0;
      for (final align in localAlignments) {
        if (align.refIdx < 0 || align.predIdx < 0) continue;
        final int absRefIdx = winStartChunk + safeStartJ + align.refIdx;
        if (absRefIdx >= chunkToWordMap.length) continue;
        if (chunkToWordMap[absRefIdx] != w) continue;
        if (align.opType == 'match' || align.opType == 'replace') {
          matchedRefChunks++;
        }
      }
      final int totalRefChunks = wordEndChunk[w] - wordStartChunk[w];
      final bool hasSufficientCoverage = totalRefChunks <= 0 || (matchedRefChunks / totalRefChunks) >= 0.50;
      final bool isRed = !hasSufficientCoverage;

      mainSendPort.send(
        WordMatchedEvent(
          wordId: w,
          cleanAsr: w < acceptedWordsAsr.length ? acceptedWordsAsr[w] : '',
          tajweedErrors: serializedErrors,
          isRed: isRed,
        ).toMap(),
      );
    }

    targetWordCursor = endW;
    asrConsumedTokenCount += result.bestI;

    if (matchedRefSlice.isNotEmpty) {
      lastMatchedPhoneme = matchedRefSlice.last;
    }
  }

  int _getCharIndexForToken(List<PhonemeToken> tokens, int tokenIndex) {
    if (tokenIndex >= tokens.length) return currentSegmentAsr.length;
    return tokens[tokenIndex].originalIndex;
  }
}
