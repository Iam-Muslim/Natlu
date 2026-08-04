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
  String trackingStrictness = 'normal';

  // ---------------------------------------------------------------------------
  // ASR State
  // ---------------------------------------------------------------------------
  String currentSegmentAsr = '';
  List<double> currentSegmentTimestamps = [];
  List<double> currentSegmentYsProbs = [];
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
      DebugLogEvent(
        message: message,
        asrBuffer: currentSegmentAsr,
      ).toMap(),
    );
  }

  /// Sets up a new continuous Surah reference in the background thread.
  void setSurahReference(SetSurahReferenceCommand cmd) {
    currentSurahNumber = cmd.surahNumber;
    final String expectedPhonemes = cmd.fullPhonemes.replaceAll(' ', '');
    wordBoundaries = cmd.boundaries;
    isTajweed = cmd.isTajweed;
    trackingStrictness = cmd.trackingStrictness;

    refChunks = QuranNormalizer.chunkPhonemes(expectedPhonemes);
    chunkToWordMap = [];

    int charCursor = 0;
    for (final chunk in refChunks) {
      int wIdx = 0;
      for (int i = 0; i < wordBoundaries.length - 1; i++) {
        if (charCursor >= wordBoundaries[i] &&
            charCursor < wordBoundaries[i + 1]) {
          wIdx = i;
          break;
        }
      }
      chunkToWordMap.add(wIdx);
      charCursor += chunk.length;
    }

    final int wordCount = wordBoundaries.length - 1;
    wordStartChunk = List.filled(wordCount, 0);
    wordEndChunk = List.filled(wordCount, 0);

    for (int j = 0; j < refChunks.length; j++) {
      final int w = chunkToWordMap[j];
      if (w < wordCount) {
        if (j == 0 || chunkToWordMap[j - 1] != w) {
          wordStartChunk[w] = j;
        }
        wordEndChunk[w] = j + 1;
      }
    }

    refEncodedIds = Int32List(refChunks.length);
    for (int i = 0; i < refChunks.length; i++) {
      refEncodedIds[i] = PhonemeMatrix.encode(refChunks[i]);
    }

    if (cmd.forceClear) {
      currentSegmentAsr = '';
      currentSegmentTimestamps = [];
      currentSegmentYsProbs = [];
      asrConsumedTokenCount = 0;
      targetWordCursor = cmd.startGlobalWord.clamp(0, wordCount);
    } else {
      targetWordCursor = cmd.startGlobalWord.clamp(0, wordCount);
    }

    acceptedWordsAsr = List.filled(wordCount, '');
    acceptedWordsTimestamps = List.generate(wordCount, (_) => []);
    lastMatchedPhoneme = null;

    debugLog(
      '📖 [SURAH SET] Surah: $currentSurahNumber | Words: $wordCount | StartWord: $targetWordCursor | Tajweed: $isTajweed | Strict: $trackingStrictness',
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
    currentSegmentYsProbs = [];
    asrConsumedTokenCount = 0;
    lastMatchedPhoneme = null;

    debugLog(
      '🎯 [JUMP TO WORD] Cursor jumped to global word $targetWordCursor (ASR state cleared)',
    );
  }

  /// Ingests streaming ASR audio data and triggers monotonic sequence evaluation.
  void syncStream(SyncStreamCommand cmd) {
    if (cmd.isNewSegment) {
      asrConsumedTokenCount = 0;
      debugLog(
        '🔄 [SYNC] New ASR segment started. Consumed tokens reset to 0.',
      );
    }

    currentSegmentAsr = cmd.asrText;
    currentSegmentTimestamps = cmd.timestamps;
    currentSegmentYsProbs = cmd.ysProbs;

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
              t.text.trim().isNotEmpty &&
              t.text != '<blank>' &&
              t.text != 'ؙ',
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

      final List<String> targetWindow = refChunks.sublist(
        winStartChunk,
        winEndChunk,
      );

      // Dynamic recitation strictness
      double averagePhonemeDuration = 0.15;
      final int unconsumedCharStart = _getCharIndexForToken(
        cleanTokens,
        asrConsumedTokenCount,
      );
      if (unconsumedCharStart < currentSegmentTimestamps.length) {
        double totalDur = 0;
        int durCount = 0;
        for (
          int c = unconsumedCharStart;
          c < currentSegmentTimestamps.length;
          c++
        ) {
          totalDur += currentSegmentTimestamps[c];
          durCount++;
        }
        if (durCount > 0) {
          averagePhonemeDuration = totalDur / durCount;
        }
      }

      final alignmentConfig = AlignmentConfig.fromStrictness(
        trackingStrictness,
        isTajweed: isTajweed,
        averagePhonemeDuration: averagePhonemeDuration,
      );

      final List<String> unconsumedStrings =
          unconsumedTokens.map((t) => t.text).toList();

      final AlignmentResult? result = _matcher.align(
        currentAsrChunks: unconsumedStrings,
        targetWindow: targetWindow,
        expectedWord: targetWordCursor,
        config: alignmentConfig,
        targetEncodedIds: Int32List.sublistView(
          refEncodedIds,
          winStartChunk,
          winEndChunk,
        ),
        asrYsProbs: _getUnconsumedYsProbs(cleanTokens, asrConsumedTokenCount),
        debugLog: debugLog,
      );

      if (result != null) {
        _commitMatch(
          result,
          unconsumedTokens,
          cleanTokens,
          targetWindow,
          winStartChunk,
        );
        matchedSomething = true;
      }
    } while (matchedSomething);
  }

  void _commitMatch(
    AlignmentResult result,
    List<PhonemeToken> unconsumedTokens,
    List<PhonemeToken> fullCleanTokens,
    List<String> targetWindow,
    int winStartChunk,
  ) {
    final int w = targetWordCursor;

    final List<String> matchedAsrSlice = unconsumedTokens
        .sublist(result.bestStartI, result.bestI)
        .map((t) => t.text)
        .toList();
    final List<String> matchedRefSlice = targetWindow.sublist(
      result.bestStartJ,
      result.bestJ,
    );

    final List<PhonemeGroupAlignment> localAlignments = result.trace;

    final List<PhonemeGroupAlignment> globalAlignments = localAlignments.map((
      a,
    ) {
      return PhonemeGroupAlignment(
        opType: a.opType,
        refIdx: a.refIdx >= 0
            ? winStartChunk + result.bestStartJ + a.refIdx
            : -1,
        predIdx: a.predIdx >= 0 ? a.predIdx : -1,
      );
    }).toList();

    String wordPredStr = '';
    final List<double> wordPredTs = [];

    for (final align in localAlignments) {
      if (align.refIdx < 0 || align.predIdx < 0) continue;
      final int absRefIdx = winStartChunk + result.bestStartJ + align.refIdx;
      if (absRefIdx >= chunkToWordMap.length) continue;

      final int wId = chunkToWordMap[absRefIdx];
      if (wId != w) continue;

      final int absPredIdx = result.bestStartI + align.predIdx;
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

    acceptedWordsAsr[w] = wordPredStr;
    acceptedWordsTimestamps[w] = wordPredTs;

    Map<int, List<ReciterError>>? tajweedErrors;
    if (isTajweed) {
      final int globalStartIdx = asrConsumedTokenCount + result.bestStartI;
      final int charStart = _getCharIndexForToken(
        fullCleanTokens,
        globalStartIdx,
      );
      final int safeStartIdx = min(
        charStart,
        currentSegmentTimestamps.length,
      );

      tajweedErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: globalAlignments,
        globalRefChunks: refChunks,
        refChunkToWordMap: chunkToWordMap,
        currentAsrChunks: matchedAsrSlice,
        trackingTimestamps: currentSegmentTimestamps.sublist(safeStartIdx),
        bestAsrStartIdx: 0,
        targetChunkCursor: 0,
        startWordId: w,
        nextWordId: w + 1,
        totalAyahWords: wordBoundaries.length - 1,
        matchScore: result.pureAcousticScore,
        previousWordTail: lastMatchedPhoneme,
        trackingStrictness: trackingStrictness,
      );
    }

    List<Map<String, dynamic>>? serializedErrors;
    if (tajweedErrors != null && tajweedErrors.containsKey(w)) {
      serializedErrors = tajweedErrors[w]!.map((e) => e.toMap()).toList();
    }

    mainSendPort.send(
      WordMatchedEvent(
        wordId: w,
        cleanAsr: acceptedWordsAsr[w],
        tajweedErrors: serializedErrors,
        isRed: false,
      ).toMap(),
    );

    targetWordCursor++;
    asrConsumedTokenCount += result.bestI;

    if (matchedRefSlice.isNotEmpty) {
      lastMatchedPhoneme = matchedRefSlice.last;
    }
  }

  int _getCharIndexForToken(List<PhonemeToken> tokens, int tokenIndex) {
    if (tokenIndex >= tokens.length) return currentSegmentAsr.length;
    return tokens[tokenIndex].originalIndex;
  }

  List<double> _getUnconsumedYsProbs(
    List<PhonemeToken> cleanTokens,
    int consumedCount,
  ) {
    final int charStart = _getCharIndexForToken(cleanTokens, consumedCount);
    if (charStart < currentSegmentYsProbs.length) {
      return currentSegmentYsProbs.sublist(charStart);
    }
    return const [];
  }
}
