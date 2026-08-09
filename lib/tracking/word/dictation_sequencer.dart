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
      final int endChar = (w + 1 < wordBoundaries.length) ? wordBoundaries[w + 1] : expectedPhonemes.length;
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
    currentSegmentYsProbs = [];
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

      final alignmentConfig = AlignmentConfig.defaultConfig(
        isTajweed: isTajweed,
      );

      final List<String> unconsumedStrings =
          unconsumedTokens.map((t) => t.text).toList();
      final List<double> unconsumedYsProbs =
          _getUnconsumedYsProbs(cleanTokens, asrConsumedTokenCount);

      // ── TIER 1: Standard Sequential Match (Word W) ─────────────────────────
      AlignmentResult? result = _alignWindow(
        asrStrings: unconsumedStrings,
        asrYsProbs: unconsumedYsProbs,
        startChunk: winStartChunk,
        endChunk: winEndChunk,
        expectedWord: targetWordCursor,
        config: alignmentConfig,
      );

      if (result != null) {
        _commitMatch(
          result: result,
          unconsumedTokens: unconsumedTokens,
          fullCleanTokens: cleanTokens,
          targetWindow: targetWindow,
          winStartChunk: winStartChunk,
          startWordId: targetWordCursor,
        );
        matchedSomething = true;
        continue;
      }

      // ── TIER 3: Multi-Word Span Fallback (W + W+1 Continuous Wasl) ─────────
      if (alignmentConfig.enableSpanFallback &&
          targetWordCursor + 1 < wordCount &&
          unconsumedStrings.length >= alignmentConfig.minSpanBufferChunks) {
        final int spanEnd = wordEndChunk[targetWordCursor + 1];
        if (winStartChunk < spanEnd) {
          final spanRes = _alignWindow(
            asrStrings: unconsumedStrings,
            asrYsProbs: unconsumedYsProbs,
            startChunk: winStartChunk,
            endChunk: spanEnd,
            expectedWord: targetWordCursor,
            config: alignmentConfig.copyWith(
              threshold: alignmentConfig.threshold *
                  alignmentConfig.spanThresholdFactor,
            ),
          );

          if (spanRes != null) {
            _commitMatch(
              result: spanRes,
              unconsumedTokens: unconsumedTokens,
              fullCleanTokens: cleanTokens,
              targetWindow: refChunks.sublist(winStartChunk, spanEnd),
              winStartChunk: winStartChunk,
              startWordId: targetWordCursor,
              endWordId: targetWordCursor + 2,
            );
            matchedSomething = true;
            continue;
          }
        }
      }

      // ── TIER 2: Forward Lookahead Skip (W -> W + 1) ────────────────────────
      if (alignmentConfig.enableLookahead && targetWordCursor + 1 < wordCount) {
        final int nextW = targetWordCursor + 1;
        final int nextStart = wordStartChunk[nextW];
        final int nextEnd = wordEndChunk[nextW];

        if (nextStart < nextEnd) {
          final nextRes = _alignWindow(
            asrStrings: unconsumedStrings,
            asrYsProbs: unconsumedYsProbs,
            startChunk: nextStart,
            endChunk: nextEnd,
            expectedWord: nextW,
            config: alignmentConfig.copyWith(
              threshold: alignmentConfig.threshold *
                  alignmentConfig.lookaheadThresholdFactor,
            ),
          );

          if (nextRes != null) {
            bool acceptSkip = true;

            // Apply Distance Penalty for skips
            final double distancePenalty = nextRes.bestStartI * alignmentConfig.lookaheadJumpPenalty;
            final double adjustedScore = nextRes.bestScore + distancePenalty;
            final double allowedThreshold = alignmentConfig.threshold * alignmentConfig.lookaheadThresholdFactor;

            if (adjustedScore > allowedThreshold) {
              acceptSkip = false;
            }

            final bool hasOverlap = _hasPhoneticOverlap(targetWordCursor, nextW);
            if (hasOverlap && acceptSkip) {
              final wRes = _alignWindow(
                asrStrings: unconsumedStrings,
                asrYsProbs: unconsumedYsProbs,
                startChunk: winStartChunk,
                endChunk: winEndChunk,
                expectedWord: targetWordCursor,
                config: alignmentConfig,
              );
              if (wRes == null) {
                // If the ASR buffer ONLY contains the phonemes for W+1, it might just be the prefix of W1. Wait.
                // But if the buffer has EXTRA tokens after matching W+1, it proves the user has moved on!
                if (unconsumedStrings.length > nextRes.bestI) {
                  acceptSkip = true;
                } else {
                  acceptSkip = false;
                }
              } else if (nextRes.bestScore > wRes.bestScore - alignmentConfig.lookaheadMarginDifferential) {
                // If W1 is a valid partial match, compare scores.
                acceptSkip = false;
              }
            }

            if (acceptSkip) {
              _emitSkippedWord(targetWordCursor, asrStrings: unconsumedStrings, ysProbs: unconsumedYsProbs);
              _commitMatch(
                result: nextRes,
                unconsumedTokens: unconsumedTokens,
                fullCleanTokens: cleanTokens,
                targetWindow: refChunks.sublist(nextStart, nextEnd),
                winStartChunk: nextStart,
                startWordId: nextW,
              );
              matchedSomething = true;
              continue;
            }
          }
        }
      }

      // ── TIER 4: Stalled Buffer Recovery (Local Forward Resync) ─────────────
      int currentWordLen = wordEndChunk[targetWordCursor] - wordStartChunk[targetWordCursor];
      int nextWordLen = 0;
      if (targetWordCursor + 1 < wordCount) {
        nextWordLen = wordEndChunk[targetWordCursor + 1] - wordStartChunk[targetWordCursor + 1];
      }
      
      // Dynamic threshold: 1.5x combined length of W and W+1, safely bounded by a strict minimum floor.
      int dynamicThreshold = ((currentWordLen + nextWordLen) * 1.5).ceil();
      int effectiveRecoveryThreshold = max(
        alignmentConfig.stalledRecoveryBufferChunks,
        dynamicThreshold,
      );

      if (unconsumedStrings.length >= effectiveRecoveryThreshold &&
          targetWordCursor + 2 < wordCount) {
        final int maxScan = min(
          targetWordCursor + 1 + alignmentConfig.stalledRecoveryMaxWords,
          wordCount,
        );
        for (int scanW = targetWordCursor + 2; scanW < maxScan; scanW++) {
          final int sStart = wordStartChunk[scanW];
          final int sEnd = wordEndChunk[scanW];
          if (sStart >= sEnd) continue;

          final sRes = _alignWindow(
            asrStrings: unconsumedStrings,
            asrYsProbs: unconsumedYsProbs,
            startChunk: sStart,
            endChunk: sEnd,
            expectedWord: scanW,
            config: alignmentConfig,
          );

          if (sRes != null) {
            for (int skipped = targetWordCursor; skipped < scanW; skipped++) {
              _emitSkippedWord(skipped, asrStrings: unconsumedStrings, ysProbs: unconsumedYsProbs);
            }
            _commitMatch(
              result: sRes,
              unconsumedTokens: unconsumedTokens,
              fullCleanTokens: cleanTokens,
              targetWindow: refChunks.sublist(sStart, sEnd),
              winStartChunk: sStart,
              startWordId: scanW,
            );
            matchedSomething = true;
            break;
          }
        }
      }
    } while (matchedSomething);
  }

  /// Checks if Word [w2] is a substring, sub-phoneme, or heavily overlapping with Word [w1].
  bool _hasPhoneticOverlap(int w1, int w2) {
    if (w1 >= wordStartChunk.length || w2 >= wordStartChunk.length) return false;
    final int s1 = wordStartChunk[w1], e1 = wordEndChunk[w1];
    final int s2 = wordStartChunk[w2], e2 = wordEndChunk[w2];
    if (s1 >= e1 || s2 >= e2) return false;

    final String str1 = refChunks.sublist(s1, e1).join('');
    final String str2 = refChunks.sublist(s2, e2).join('');

    // 1. Identical words or extremely short particles (e.g. 'لا', 'و', 'ب')
    if (str1 == str2 || (e2 - s2) <= 2) {
      return true;
    }

    // 2. Strict Prefix Substring: Does one literally start with the other?
    if (str1.startsWith(str2) || str2.startsWith(str1)) {
      return true;
    }

    // 3. Fuzzy Prefix Match: Do they share the same starting sounds?
    // Just checking the first 2 chunks is enough to detect a dangerous prefix overlap.
    int minLen = min(e1 - s1, e2 - s2);
    int prefixMatches = 0;
    for (int i = 0; i < min(2, minLen); i++) {
      if (refChunks[s1 + i] == refChunks[s2 + i]) {
        prefixMatches++;
      }
    }
    
    // If they share at least 1 of their starting phonemes, it's a dangerous overlap.
    return prefixMatches > 0;
  }

  /// Evaluates alignment for a specific reference window slice.
  AlignmentResult? _alignWindow({
    required List<String> asrStrings,
    required List<double> asrYsProbs,
    required int startChunk,
    required int endChunk,
    required int expectedWord,
    required AlignmentConfig config,
    bool suppressLogs = false,
  }) {
    return _matcher.align(
      currentAsrChunks: asrStrings,
      targetWindow: refChunks.sublist(startChunk, endChunk),
      expectedWord: expectedWord,
      config: config,
      targetEncodedIds:
          Int32List.sublistView(refEncodedIds, startChunk, endChunk),
      asrYsProbs: asrYsProbs,
      debugLog: suppressLogs ? null : debugLog,
    );
  }

  /// Emits a skipped (RED) or neutral word event to the UI thread.
  void _emitSkippedWord(int wordId, {List<String>? asrStrings, List<double>? ysProbs}) {
    bool isNeutral = false;
    
    // Retroactive Forgiveness Check (Only in Normal mode)
    if (asrStrings != null) {
      final int wStart = wordStartChunk[wordId];
      final int wEnd = wordEndChunk[wordId];
      if (wStart < wEnd) {
        final String wordStr = refChunks.sublist(wStart, wEnd).join('');
        final res = _alignWindow(
          asrStrings: asrStrings,
          asrYsProbs: ysProbs ?? [],
          startChunk: wStart,
          endChunk: wEnd,
          expectedWord: wordId,
          config: AlignmentConfig.defaultConfig().copyWith(threshold: 1.0),
          suppressLogs: true,
        );
        
        if (res != null) {
          final int safeStartI = res.bestStartI.clamp(0, asrStrings.length);
          final int safeEndI = res.bestI.clamp(safeStartI, asrStrings.length);
          final String heardWordStr = asrStrings.sublist(safeStartI, safeEndI).join('');

          if (res.bestScore <= 0.45) {
            isNeutral = true;
            debugLog('🛡️ [FORGIVENESS] Skipped "$wordStr", heard "$heardWordStr" | passed 45% threshold (Score: ${res.bestScore.toStringAsFixed(3)}). Painting NEUTRAL.');
          } else {
            debugLog('❌ [FORGIVENESS] Skipped "$wordStr", heard "$heardWordStr" | failed 45% threshold (Score: ${res.bestScore.toStringAsFixed(3)}). Painting RED.');
          }
        }
      }
    }

    mainSendPort.send(
      WordMatchedEvent(
        wordId: wordId,
        cleanAsr: '',
        tajweedErrors: null,
        isRed: !isNeutral,
        isNeutral: isNeutral,
      ).toMap(),
    );
  }

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
    final int safeEndI = result.bestI.clamp(safeStartI, unconsumedTokens.length);
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
    debugLog('✅ COMMITTED (GREEN): ref word is "$refStr", heard word is "$heardStr"');

    final List<PhonemeGroupAlignment> localAlignments = result.trace;

    for (int w = startWordId; w < endW; w++) {
      String wordPredStr = '';
      final List<double> wordPredTs = [];

      for (final align in localAlignments) {
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
      final int safeCharIdx = min(
        charStart,
        currentSegmentTimestamps.length,
      );

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
        matchScore: result.pureAcousticScore,
        previousWordTail: lastMatchedPhoneme,
      );
    }

    for (int w = startWordId; w < endW; w++) {
      List<Map<String, dynamic>>? serializedErrors;
      if (tajweedErrors != null && tajweedErrors.containsKey(w)) {
        serializedErrors = tajweedErrors[w]!.map((e) => e.toMap()).toList();
      }

      mainSendPort.send(
        WordMatchedEvent(
          wordId: w,
          cleanAsr: w < acceptedWordsAsr.length ? acceptedWordsAsr[w] : '',
          tajweedErrors: serializedErrors,
          isRed: false,
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

  List<double> _getUnconsumedYsProbs(
    List<PhonemeToken> cleanTokens,
    int consumedCount,
  ) {
    final int charStart = min(
      _getCharIndexForToken(cleanTokens, consumedCount),
      currentSegmentYsProbs.length,
    );
    if (charStart < currentSegmentYsProbs.length) {
      return currentSegmentYsProbs.sublist(charStart);
    }
    return const [];
  }

}
