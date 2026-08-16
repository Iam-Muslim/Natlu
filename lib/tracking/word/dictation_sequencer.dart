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
  List<String> currentSegmentAsrTokens = [];
  List<double> currentSegmentTimestamps = [];
  int asrConsumedTokenCount = 0;
  bool isFinalSegment = false;

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
      DebugLogEvent(message: message, asrBuffer: currentSegmentAsrTokens.join('')).toMap(),
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
      currentSegmentAsrTokens = [];
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

    if (!cmd.forceClear && currentSegmentAsrTokens.isNotEmpty) {
      _processSequence();
    }
  }

  /// Jumps the tracking cursor to a specific global word index (e.g. manual Ayah selection).
  void jumpToWord(JumpToWordCommand cmd) {
    final int wordCount = wordBoundaries.length - 1;
    targetWordCursor = cmd.globalWordIndex.clamp(0, max(0, wordCount));

    currentSegmentAsrTokens = [];
    currentSegmentTimestamps = [];
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
        '🔄 [SYNC] New ASR segment started (Explicit Reset). Consumed tokens reset to 0.',
      );
    } else if (cmd.asrTokens.length < currentSegmentAsrTokens.length) {
      // Safe prefix clamping: if Sherpa prunes the stream upstream, we clamp rather than zeroing out
      asrConsumedTokenCount = min(asrConsumedTokenCount, cmd.asrTokens.length);
      debugLog(
        '🔄 [SYNC] Stream pruned upstream. Clamped consumed tokens to $asrConsumedTokenCount.',
      );
    }

    currentSegmentAsrTokens = cmd.asrTokens;
    currentSegmentTimestamps = cmd.timestamps;
    isFinalSegment = cmd.isNewSegment; // the cmd.isNewSegment actually means isFinal in Sherpa. Wait, it's called isNewSegment from UI, but it maps to isFinal.

    _processSequence();
  }

  /// Core alignment loop: matches unconsumed ASR tokens against the active expected word.
  void _processSequence() {
    if (currentSegmentAsrTokens.isEmpty) return;

    bool matchedSomething;
    do {
      matchedSomething = false;

      if (targetWordCursor >= wordBoundaries.length - 1) break;

      // Handle rollbacks in streaming ASR tokens
      if (currentSegmentAsrTokens.length < asrConsumedTokenCount) {
        asrConsumedTokenCount = currentSegmentAsrTokens.length;
      }

      List<String> unconsumedTokens = currentSegmentAsrTokens.sublist(
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

      // ── THE HOLY GRAIL: Continuous Subsequence DTW ─────────
      // Tests up to 10 upcoming words continuously for native Wasl and free skips.
      const int lookaheadWordSpan = 10;
      final int maxLookaheadWord = min(wordCount, targetWordCursor + lookaheadWordSpan);

      final int winStartChunk = wordStartChunk[targetWordCursor];
      final int winEndChunk = wordEndChunk[maxLookaheadWord - 1];

      if (winStartChunk >= winEndChunk) break;

      final alignmentConfig = AlignmentConfig.defaultConfig(
        isTajweed: isTajweed,
      );

      final List<String> unconsumedStrings = unconsumedTokens;

      Set<int> validStartChunks = {};
      Set<int> validEndChunks = {};
      
      for (int w = targetWordCursor; w < maxLookaheadWord; w++) {
          validStartChunks.add(wordStartChunk[w] - winStartChunk);
          validEndChunks.add(wordEndChunk[w] - winStartChunk);
      }

      AlignmentResult? forwardResult = _alignWindow(
        asrStrings: unconsumedStrings,
        startChunk: winStartChunk,
        endChunk: winEndChunk,
        expectedWord: targetWordCursor,
        config: alignmentConfig,
        validStartChunks: validStartChunks,
        validEndChunks: validEndChunks,
      );

      if (forwardResult != null) {
        final int targetAbsStartChunk = winStartChunk + forwardResult.bestStartJ;
        final int targetAbsEndChunk = winStartChunk + forwardResult.bestJ;
        int startMatchedWord = targetWordCursor;
        if (targetAbsStartChunk < chunkToWordMap.length) {
          startMatchedWord = chunkToWordMap[targetAbsStartChunk];
        }

        int matchedWordIdx = targetWordCursor;
        if (targetAbsEndChunk > 0 && targetAbsEndChunk - 1 < chunkToWordMap.length) {
          matchedWordIdx = chunkToWordMap[targetAbsEndChunk - 1];
        } else {
          for (int w = targetWordCursor; w < maxLookaheadWord; w++) {
            if (wordEndChunk[w] - winStartChunk == forwardResult.bestJ) {
              matchedWordIdx = w;
              break;
            }
          }
        }

        // Backward Repetition Debris Guard:
        // If candidate is a forward jump (startMatchedWord > targetWordCursor) matching ONLY a single isolated word,
        // and that word is phonetically identical to the immediately preceding committed word (targetWordCursor - 1),
        // the reciter has simply repeated the previous word (e.g. stumbling/re-reading).
        // Suppress this forward jump so it doesn't falsely skip the unread intermediate words.
        if (startMatchedWord > targetWordCursor &&
            startMatchedWord == matchedWordIdx &&
            targetWordCursor > 0 &&
            targetWordCursor - 1 < wordStartChunk.length &&
            startMatchedWord < wordStartChunk.length) {
          final int prevWord = targetWordCursor - 1;
          final String prevWordPhonemes = refChunks.sublist(wordStartChunk[prevWord], wordEndChunk[prevWord]).join('');
          final String matchedWordPhonemes = refChunks.sublist(wordStartChunk[startMatchedWord], wordEndChunk[startMatchedWord]).join('');

          if (prevWordPhonemes == matchedWordPhonemes) {
            if (forwardResult.bestI > 0 && forwardResult.bestI <= unconsumedTokens.length) {
              unconsumedTokens.removeRange(0, forwardResult.bestI);
            }
            debugLog('🔄 [REPETITION ABSORPTION] Absorbed repetition of previous word "$prevWordPhonemes" without jumping ahead');
            matchedSomething = true;
            continue;
          }
        }

        _commitMatch(
          result: forwardResult,
          unconsumedTokens: unconsumedTokens,
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
    Set<int>? validStartChunks,
    Set<int>? validEndChunks,
    bool suppressLogs = false,
  }) {
    return _matcher.align(
      currentAsrChunks: asrStrings,
      targetWindow: refChunks.sublist(startChunk, endChunk),
      expectedWord: expectedWord,
      config: config,
      validStartChunks: validStartChunks,
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
    required List<String> unconsumedTokens,
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
        .sublist(safeStartI, safeEndI);

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

        final String chunk = unconsumedTokens[absPredIdx];
        wordPredStr += chunk;

        final int globalTokenIdx = asrConsumedTokenCount + absPredIdx;
        
        // Pillar I: 1-to-1 token-to-timestamp mapping
        if (globalTokenIdx < currentSegmentTimestamps.length) {
          wordPredTs.add(currentSegmentTimestamps[globalTokenIdx]);
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
      final int safeCharIdx = min(globalStartIdx, currentSegmentTimestamps.length);

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

      double validMatchedChunks = 0.0;
      double totalWordCost = 0.0;
      int wordAsrChunks = 0;

      for (final align in localAlignments) {
        if (align.refIdx >= 0) {
          final int absRefIdx = winStartChunk + safeStartJ + align.refIdx;
          if (absRefIdx < chunkToWordMap.length && chunkToWordMap[absRefIdx] == w) {
            if (align.predIdx >= 0 && (safeStartI + align.predIdx) < unconsumedTokens.length) {
              wordAsrChunks++;
              final String pChunk = unconsumedTokens[safeStartI + align.predIdx];
              final String rChunk = refChunks[absRefIdx];
              final int pId = PhonemeMatrix.encode(pChunk);
              final int rId = PhonemeMatrix.encode(rChunk);
              final double cost = PhonemeMatrix.getCost(pId, rId);
              totalWordCost += cost;

              if (cost <= 0.001) {
                // Exact phoneme match
                validMatchedChunks += 1.0;
              } else if (cost <= 0.25) {
                // Minor phonetic / vowel / Madd variation
                validMatchedChunks += 1.0;
              } else if (cost <= 0.40) {
                // Near articulatory neighbor (e.g. ص/س or length difference)
                validMatchedChunks += 0.75;
              } else {
                // Severe phonetic error (wrong consonant / Lahn Jali) -> no match credit
                validMatchedChunks += 0.0;
              }
            } else {
              // Deletion: reference chunk missing in ASR
              totalWordCost += 1.0;
            }
          }
        }
      }

      final int totalRefChunks = (w < wordEndChunk.length && w < wordStartChunk.length)
          ? (wordEndChunk[w] - wordStartChunk[w])
          : 0;

      bool isGreen = false;
      if (totalRefChunks <= 0) {
        isGreen = true;
      } else {
        final double coverage = validMatchedChunks / totalRefChunks;
        final int denom = max(totalRefChunks, max(wordAsrChunks, 1));
        final double wordScore = totalWordCost / denom;
        final double adaptiveThresh = 0.25 * (1.0 + (1.5 / sqrt(max(totalRefChunks, 1))));

        if (totalRefChunks == 1) {
          isGreen = (validMatchedChunks >= 0.75 && wordScore <= 0.35);
        } else if (totalRefChunks == 2) {
          isGreen = (validMatchedChunks >= 1.50 && wordScore <= adaptiveThresh);
        } else {
          isGreen = (coverage >= 0.50 && wordScore <= adaptiveThresh);
        }
      }

      final bool isRed = !isGreen;

      mainSendPort.send(
        WordMatchedEvent(
          wordId: w,
          cleanAsr: w < acceptedWordsAsr.length ? acceptedWordsAsr[w] : '',
          tajweedErrors: serializedErrors,
          isRed: isRed,
        ).toMap(),
      );
    }

    int tokensToAdvance = result.bestI;
    if (matchedRefSlice.isNotEmpty) {
      final String lastChar = matchedRefSlice.last;
      lastMatchedPhoneme = lastChar;
    }

    targetWordCursor = endW;
    asrConsumedTokenCount += tokensToAdvance;
  }
}
