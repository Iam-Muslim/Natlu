import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../tajweed/error_explainer.dart';
import 'dictation_matcher.dart';
import 'quran_normalizer.dart';
import 'phoneme_matrix.dart';
import '../../utils/debug_logger.dart';

///
/// FILE ROLE: Orchestrator / Thread Manager / App State
/// ARCHITECTURE: Dart Isolate (Background Thread)
/// DEPENDENCIES: dictation_matcher.dart (Engine), quran_normalizer.dart (Text Prep)
/// RESPONSIBILITY:
/// - Manages the `asrWindow` buffer (raw audio phonetic stream).
/// - Manages the `targetWordCursor` (which word the user is currently reading).
/// - Slices 'lookahead' windows of text to feed into the Matcher.
/// - Routes successful matches through the Tajweed `ErrorExplainer`.
/// - Emits final JSON payloads ('highlight' events) back to the Flutter UI thread.
/// AI NOTE: Do NOT modify the mathematical alignment DP logic here; that belongs in `dictation_matcher.dart`.
/// Do NOT modify penalty logic here; that belongs in `phoneme_matrix.dart`.
///

/// ────────────────────────────────────────────────────────────────────────────
/// [IsolateCommands] - Inter-thread Communication Protocol
/// ────────────────────────────────────────────────────────────────────────────
/// Because phonetic alignment is mathematically intense, running it on the main UI
/// thread would cause the app to freeze and drop frames (jank).
/// Instead, we run it in a background "Isolate" (a separate CPU thread).
///
/// Since Isolates do not share memory, they can only communicate by passing messages.
/// This class defines the integer "commands" the UI uses to tell the background
/// thread what to do.
class IsolateCommands {
  static const int setup = 0;
  static const int syncStream = 1; // Sync full ASR stream for current segment
  static const int setSurahReference = 2; // Initialize a Surah with continuous expected phonemes
  static const int shutdown = 3; // Terminate the isolate
  static const int jumpToWord = 4; // Jump targetWordCursor to a specific global word index
  static const int setTajweedMode = 5; // Toggle tajweed mode
  static const int setTrackingStrictness = 6; // Set strictness mode
}

/// ────────────────────────────────────────────────────────────────────────────
/// [PhonemeAlignmentIsolate] - The Isolate Manager (UI Thread Side)
/// ────────────────────────────────────────────────────────────────────────────
/// This class lives on the MAIN UI THREAD.
/// Its only job is to start the background thread, send it messages, and
/// listen for the "highlight" events coming back to update the screen.
class PhonemeAlignmentIsolate {
  SendPort? _sendPort;
  Isolate? _isolate;

  /// A stream that emits the final results (which word to highlight, and any
  /// Tajweed errors found in that word). The Flutter UI listens to this stream.
  final StreamController<Map<String, dynamic>> _wordStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get wordStream => _wordStreamController.stream;

  /// Starts the background isolate.
  Future<void> start() async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    // Spawns the _alignmentWorker on a separate CPU core.
    _isolate = await Isolate.spawn(_alignmentWorker, receivePort.sendPort);

    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
      } else if (message is Map) {
        if (message['event'] == 'highlight') {
          // A word was successfully matched in the background! Send it to the UI.
          _wordStreamController.add(message as Map<String, dynamic>);
        } else if (message['event'] == 'debug') {
          DebugLogger.updateAsrBuffer(message['asr_buffer'] as String? ?? '');
          DebugLogger.log('DP', message['message'] as String);
        }
      }
    });

    return completer.future;
  }

  /// Sends the dynamic tokens list to preheat the phoneme matrix.
  void setup(List<String> tokens) {
    _sendPort?.send({'cmd': IsolateCommands.setup, 'tokens': tokens});
  }

  /// Tells the background thread to load a Surah reference.
  void setSurahReference(
    String expectedPhonemes,
    List<int> wordBoundaries, {
    bool isTajweed = false,
    bool forceClear = false,
    String trackingStrictness = 'normal',
    int startGlobalWord = 0,
    int surahNumber = 0,
  }) {
    _sendPort?.send({
      'cmd': IsolateCommands.setSurahReference,
      'phonemes': expectedPhonemes,
      'boundaries': wordBoundaries,
      'isTajweed': isTajweed,
      'forceClear': forceClear,
      'trackingStrictness': trackingStrictness,
      'startGlobalWord': startGlobalWord,
      'surahNumber': surahNumber,
    });
  }

  /// Jumps the tracking cursor to a specific global word index (e.g. when user taps an Ayah).
  void jumpToWord(int globalWordIndex) {
    _sendPort?.send({
      'cmd': IsolateCommands.jumpToWord,
      'globalWordIndex': globalWordIndex,
    });
  }

  /// Sends the full unconsumed segment string and its timestamps to the background thread.
  void syncStream(
    String fullSegmentAsr,
    List<double> segmentTimestamps, [
    List<double>? segmentYsProbs,
    bool isNewSegment = false,
    int ayahNumber = 0,
  ]) {
    _sendPort?.send({
      'cmd': IsolateCommands.syncStream,
      'asr': fullSegmentAsr,
      'timestamps': segmentTimestamps,
      'ysProbs': segmentYsProbs ?? [],
      'isNewSegment': isNewSegment,
      'ayahNumber': ayahNumber,
    });
  }

  void setTajweedMode(bool isTajweed) {
    _sendPort?.send({
      'cmd': IsolateCommands.setTajweedMode,
      'isTajweed': isTajweed,
    });
  }

  void setTrackingStrictness(String strictness) {
    _sendPort?.send({
      'cmd': IsolateCommands.setTrackingStrictness,
      'strictness': strictness,
    });
  }

  void stop() {
    _sendPort?.send({'cmd': IsolateCommands.shutdown});
    _wordStreamController.close();
    _isolate?.kill();
    _isolate = null;
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// [DictationSequencer] - The App Logic Orchestrator (Background Thread Side)
/// ────────────────────────────────────────────────────────────────────────────
/// This class lives entirely in the BACKGROUND THREAD.
///
/// It acts as the "Traffic Controller" between the incoming raw audio (ASR)
/// and the purely mathematical `ForwardDictationMatcher`.
///
/// It maintains state:
/// - What word are we currently waiting for the user to say? (`targetWordCursor`)
/// - How much "garbage" audio is currently buffered? (`asrWindow`)
/// - What was the last phoneme matched? (`lastMatchedPhoneme` for Tajweed bridging)
///
/// It constructs the "Lookahead Window" (a small slice of the Ayah) and feeds it
/// to the Matcher. If the Matcher finds a match, the Sequencer cuts out the
/// matched audio, advances the cursor, and sends a highlight event to the UI.
class DictationSequencer {
  final SendPort mainSendPort;

  // ---------------------------------------------------------------------------
  // Reference State (The perfect text)
  // ---------------------------------------------------------------------------
  List<int> wordBoundaries = [];
  List<String> refChunks = [];
  List<int> chunkToWordMap = [];
  List<bool> startBd = [];
  List<bool> endBd = [];

  bool isTajweed = false;
  String trackingStrictness = 'normal';

  // ---------------------------------------------------------------------------
  // ASR State (The messy audio)
  // ---------------------------------------------------------------------------
  /// The full string of phonetic sounds the microphone has heard in the current segment.
  String currentSegmentAsr = '';

  /// The timestamps corresponding to every character in the `currentSegmentAsr`.
  List<double> currentSegmentTimestamps = [];

  /// The acoustic confidence (log probability) corresponding to every character.
  List<double> currentSegmentYsProbs = [];

  /// The number of valid phoneme tokens the DP engine has successfully consumed
  /// from the `currentSegmentAsr` stream.
  int asrConsumedTokenCount = 0;

  // ---------------------------------------------------------------------------
  // Output State
  // ---------------------------------------------------------------------------
  List<String> acceptedWordsAsr = [];
  List<List<double>> acceptedWordsTimestamps = [];

  /// The most important variable in the orchestrator.
  /// This points to the Word ID that we are actively trying to highlight next.
  int targetWordCursor = 0;

  /// [Tajweed] Stores the very last phoneme of the previously matched word.
  /// If Word 1 ends in a Nun Sakinah, and Word 2 begins with a Waw, the Tajweed
  /// engine needs to know what the end of Word 1 sounded like to verify an Idgham.
  String? lastMatchedPhoneme;

  /// Current Surah and Ayah number being tracked
  int currentSurahNumber = 0;
  int currentAyahNumber = 0;

  /// Fast O(1) chunk boundary lookup per word
  List<int> wordStartChunk = [];
  List<int> wordEndChunk = [];

  /// Pre-encoded integer phoneme IDs for the entire Surah
  Int32List refEncodedIds = Int32List(0);

  /// The purely mathematical engine.
  final ForwardDictationMatcher _matcher = ForwardDictationMatcher();

  DictationSequencer(this.mainSendPort);

  void debugLog(String message) {
    mainSendPort.send({
      'event': 'debug',
      'message': message,
      'asr_buffer': currentSegmentAsr,
    });
  }

  /// --------------------------------------------------------------------------
  /// Continuous Surah Reference Initialization
  /// --------------------------------------------------------------------------
  /// Parses the continuous raw string of the entire Surah into individual phoneme chunks,
  /// maps them to specific global Word IDs, and builds the boolean boundary arrays.
  void setSurahReference(Map message) {
    currentSurahNumber = message['surahNumber'] as int? ?? 0;
    String expectedPhonemes = (message['phonemes'] as String).replaceAll(
      ' ',
      '',
    );
    wordBoundaries = message['boundaries'] as List<int>;
    isTajweed = message['isTajweed'] as bool? ?? false;
    trackingStrictness =
        message['trackingStrictness'] as String? ?? trackingStrictness;
    bool forceClear = message['forceClear'] as bool? ?? false;
    int startGlobalWord = message['startGlobalWord'] as int? ?? 0;

    refChunks = QuranNormalizer.chunkPhonemes(expectedPhonemes);
    chunkToWordMap = [];

    int charCursor = 0;
    for (var chunk in refChunks) {
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

    int n = refChunks.length;
    startBd = List.filled(n + 1, false);
    endBd = List.filled(n + 1, false);

    if (n > 0) {
      startBd[0] = true;
      for (int j = 1; j < n; j++) {
        if (chunkToWordMap[j] != chunkToWordMap[j - 1]) {
          startBd[j] = true;
          endBd[j] = true;
        }
      }
      startBd[n] = false;
      endBd[n] = true;
    }

    int wordCount = wordBoundaries.length - 1;

    wordStartChunk = List.filled(wordCount, 0);
    wordEndChunk = List.filled(wordCount, 0);

    for (int j = 0; j < refChunks.length; j++) {
      int w = chunkToWordMap[j];
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

    if (forceClear) {
      currentSegmentAsr = '';
      currentSegmentTimestamps = [];
      currentSegmentYsProbs = [];
      asrConsumedTokenCount = 0;
      targetWordCursor = startGlobalWord.clamp(0, wordCount);
    } else {
      targetWordCursor = startGlobalWord.clamp(0, wordCount);
    }

    acceptedWordsAsr = List.filled(wordCount, '');
    acceptedWordsTimestamps = List.generate(wordCount, (_) => []);
    lastMatchedPhoneme = null;

    debugLog(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );
    debugLog(
      '📖 [SURAH SET] Surah: $currentSurahNumber | Words: $wordCount | StartWord: $targetWordCursor | Tajweed: $isTajweed | Strict: $trackingStrictness',
    );
    debugLog(
      '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
    );

    if (!forceClear && currentSegmentAsr.isNotEmpty) {
      _processSequence();
    }
  }

  void jumpToWord(Map message) {
    int globalWordIndex = message['globalWordIndex'] as int? ?? 0;
    int wordCount = wordBoundaries.length - 1;
    targetWordCursor = globalWordIndex.clamp(0, max(0, wordCount));

    // FIX: Clear stale ASR state from the previous recording session.
    // If we don't reset these, asrConsumedTokenCount stays at its old value.
    // The new session's fresh (short) ASR text will be immediately fully-consumed
    // by the clamping logic → unconsumedTokens.isEmpty → matching never fires.
    currentSegmentAsr = '';
    currentSegmentTimestamps = [];
    currentSegmentYsProbs = [];
    asrConsumedTokenCount = 0;

    debugLog('🎯 [JUMP TO WORD] Cursor jumped to global word $targetWordCursor (ASR state cleared)');
  }

  /// --------------------------------------------------------------------------
  // ASR Data Ingestion
  /// --------------------------------------------------------------------------
  /// Whenever the microphone hears new sounds, the UI sends the full segment text here.
  /// Then, we instantly kick off a processing loop to see if those new sounds
  /// are enough to complete the word we are waiting for.
  void syncStream(Map message) {
    String newAsr = message['asr'];
    List<double> newTimestamps = List<double>.from(message['timestamps']);
    List<double> newYsProbs = List<double>.from(message['ysProbs'] ?? []);
    bool isNewSegment = message['isNewSegment'] ?? false;

    if (isNewSegment) {
      asrConsumedTokenCount = 0;
      debugLog(
        '🔄 [SYNC] New ASR segment started. Consumed tokens reset to 0.',
      );
    }

    currentSegmentAsr = newAsr;
    currentSegmentTimestamps = newTimestamps;
    currentSegmentYsProbs = newYsProbs;

    // Now that we have updated audio, trigger the DP algorithm to search for the word.
    _processSequence();
  }

  /// --------------------------------------------------------------------------
  /// The Core Orchestration Loop
  /// --------------------------------------------------------------------------
  /// This loop is where the magic happens. It takes the giant buffer of messy
  /// audio, slices a smart "Lookahead Window" out of the Reference Ayah, and
  /// asks the Math Engine if there's a match.
  ///
  /// If there IS a match, it commits the match, slices the garbage out of the
  /// audio buffer, and loops again immediately (in case the user read really fast
  /// and there are 2 words hiding inside the audio buffer!).
  void _processSequence() {
    if (currentSegmentAsr.isEmpty) return;

    // Chunk and filter clean tokens ONCE per sequence tick rather than on every loop iteration
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

      // If we finished the Ayah, do nothing.
      if (targetWordCursor >= wordBoundaries.length - 1) break;

      // [CRITICAL LOOKAHEAD JUMP HANDLING]
      // If the model rewrote past history such that the new token count is LESS than
      // what we already successfully matched, it means the model heavily rolled back.
      // We clamp our consumed token count so we don't throw an OutOfBounds exception.
      if (cleanTokens.length < asrConsumedTokenCount) {
        asrConsumedTokenCount = cleanTokens.length;
      }

      // We only feed the newly unconsumed tokens to the Math Engine!
      List<PhonemeToken> unconsumedTokens = cleanTokens.sublist(
        asrConsumedTokenCount,
      );

      if (unconsumedTokens.isEmpty) break;

      int m = unconsumedTokens.length;

      // -----------------------------------------------------------------------
      // Buffer Management (Garbage Collection)
      // -----------------------------------------------------------------------
      // We limit how many tokens we analyze to prevent CPU lag.
      int maxAsrChunks =
          150; // Increased to 150 to allow ~6 seconds of buffer without dropping
      if (m > maxAsrChunks) {
        // Simply pretend we consumed the oldest tokens and dropped them!
        int chunksToDrop = m - maxAsrChunks;
        asrConsumedTokenCount += chunksToDrop;
        unconsumedTokens = unconsumedTokens.sublist(chunksToDrop);
        m = unconsumedTokens.length;
        debugLog(
          '🗑️ [BUFFER GC] Dropped $chunksToDrop oldest tokens to prevent lag (Max $maxAsrChunks reached)',
        );
      }

      // -----------------------------------------------------------------------
      // Fixed Lookahead Windowing (Strictly Word-based, O(1) Array Indexing)
      // -----------------------------------------------------------------------
      int lookaheadWords = trackingStrictness == 'easy'
          ? 0
          : (trackingStrictness == 'strict' ? 3 : 2);

      int wordCount = wordBoundaries.length - 1;
      if (targetWordCursor >= wordCount ||
          targetWordCursor >= wordStartChunk.length) {
        break;
      }

      int endWordLimit = min(targetWordCursor + lookaheadWords, wordCount - 1);

      int winStartChunk = wordStartChunk[targetWordCursor];
      int winEndChunk = (endWordLimit < wordEndChunk.length)
          ? wordEndChunk[endWordLimit]
          : refChunks.length;

      if (winStartChunk >= winEndChunk) break;

      debugLog(
        '🔍 [WINDOW] Analyzing reference chunks [$winStartChunk..${winEndChunk - 1}] (Words $targetWordCursor..$endWordLimit). ASR buffer size: $m chunks.',
      );

      List<String> targetWindow = refChunks.sublist(winStartChunk, winEndChunk);
      List<int> targetWordIds = chunkToWordMap.sublist(
        winStartChunk,
        winEndChunk,
      );
      List<bool> targetStartBd = startBd.sublist(
        winStartChunk,
        winEndChunk + 1,
      );
      List<bool> targetEndBd = endBd.sublist(winStartChunk, winEndChunk + 1);

      // Strictness determines the acceptable penalty threshold.
      // Easy is strictly capped at 0.35 to completely block False Greens (reading the wrong word).
      double threshold = trackingStrictness == 'easy'
          ? 0.35
          : (trackingStrictness == 'strict' ? 0.15 : 0.25);

      // In Easy Mode, we dynamically lower the penalty for stuttering (Insertions)
      // and swallowing letters (Deletions) down to 0.65. This forgives beginners
      // for these common mistakes without raising the main threshold that blocks gibberish.
      double dynamicCostDel = trackingStrictness == 'easy' ? 0.65 : 1.0;
      double dynamicCostIns = trackingStrictness == 'easy' ? 0.65 : 1.0;

      // -----------------------------------------------------------------------
      // [HADR MODE] Dynamic Strictness for Fast Readers
      // -----------------------------------------------------------------------
      // If the user is reading very fast (Hadr), phonemes naturally merge and
      // drop. We measure their speed in real-time using average duration.
      double averagePhonemeDuration = 0.15; // default normal speed
      int unconsumedCharStart = _getCharIndexForToken(
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

      if (averagePhonemeDuration < 0.08 && trackingStrictness != 'easy') {
        // User is reciting very fast (< 0.08s per phoneme). Forgive dropped letters!
        dynamicCostDel = 0.75;
      }

      // -----------------------------------------------------------------------
      // The Engine Call
      // -----------------------------------------------------------------------
      final stopwatch = Stopwatch()..start();

      List<String> unconsumedStrings = unconsumedTokens
          .map((t) => t.text)
          .toList();

      // We ask the purely mathematical ForwardDictationMatcher to find a path.
      AlignmentResult? result = _matcher.align(
        currentAsrChunks: unconsumedStrings,
        targetWindow: targetWindow,
        targetStartBd: targetStartBd,
        targetEndBd: targetEndBd,
        targetWordIds: targetWordIds,
        expectedWord: targetWordCursor,
        targetEncodedIds: Int32List.sublistView(
          refEncodedIds,
          winStartChunk,
          winEndChunk,
        ),
        // YsProbs must be mapped from the characters, but for now we simply pass
        // the unconsumed segment probabilities. We calculate the unconsumed character index.
        asrYsProbs: _getUnconsumedYsProbs(cleanTokens, asrConsumedTokenCount),
        threshold: threshold,
        costDel: dynamicCostDel,
        costIns: dynamicCostIns,
        // EDGE-BOUND TAIL STABILITY RULE:
        // Only active during Tajweed mode. If true, the DP engine refuses to commit
        // to a match if the word is pushed against the leading edge of the audio stream
        // and ends in a deletion, because the user might just be holding a long vowel (Madd).
        // It forces the engine to wait for the final consonant to arrive.
        requireStableTail: isTajweed,
        debugLog: debugLog,
      );

      stopwatch.stop();
      if (result != null || stopwatch.elapsedMilliseconds > 2) {
        debugLog(
          '⏱️ [ISOLATE] DP Matrix calculated in ${stopwatch.elapsedMilliseconds}ms',
        );
      }

      // If a path was successfully found below the penalty threshold...
      if (result != null) {
        // ...we finalize the match and increment the tokens consumed.
        _commitMatch(
          result,
          unconsumedTokens,
          cleanTokens,
          targetWindow,
          targetWordIds,
          winStartChunk,
        );
        matchedSomething = true;
      }
    } while (matchedSomething);
  }

  /// --------------------------------------------------------------------------
  /// Match Finalization & Tajweed Routing
  /// --------------------------------------------------------------------------
  /// A match was successful!
  /// This method slices the exact subset of the audio that matched, maps it
  /// to the exact words, routes it through the Tajweed ErrorExplainer if needed,
  /// and fires the highlight message to the UI.
  void _commitMatch(
    AlignmentResult result,
    List<PhonemeToken> unconsumedTokens,
    List<PhonemeToken> fullCleanTokens,
    List<String> targetWindow,
    List<int> targetWordIds,
    int winStartChunk,
  ) {
    int n = targetWindow.length;

    // Determine exactly which word(s) this match belonged to.
    int matchedWordStart =
        targetWordIds[result.bestStartJ < n ? result.bestStartJ : n - 1];
    int matchedWordEnd = targetWordIds[result.bestJ - 1];

    List<String> matchedAsrSlice = unconsumedTokens
        .sublist(result.bestStartI, result.bestI)
        .map((t) => t.text)
        .toList();
    List<String> matchedRefSlice = targetWindow.sublist(
      result.bestStartJ,
      result.bestJ,
    );

    List<PhonemeGroupAlignment> localAlignments = result.trace;

    // Convert the local window indices into global Ayah indices for the ErrorExplainer.
    List<PhonemeGroupAlignment> globalAlignments = localAlignments.map((a) {
      return PhonemeGroupAlignment(
        opType: a.opType,
        refIdx: a.refIdx >= 0
            ? winStartChunk + result.bestStartJ + a.refIdx
            : -1,
        predIdx: a.predIdx >= 0 ? a.predIdx : -1,
      );
    }).toList();

    Map<int, String> wordPredStrMap = {};
    Map<int, List<double>> wordPredTsMap = {};

    // Group the ASR sounds and timestamps strictly into their respective word bins.
    for (var align in localAlignments) {
      if (align.refIdx < 0 || align.predIdx < 0) continue;
      int absRefIdx = winStartChunk + result.bestStartJ + align.refIdx;
      if (absRefIdx >= chunkToWordMap.length) continue;

      int wId = chunkToWordMap[absRefIdx];
      if (wId < matchedWordStart || wId > matchedWordEnd) continue;

      int absPredIdx = result.bestStartI + align.predIdx;
      String chunk = unconsumedTokens[absPredIdx].text;
      wordPredStrMap[wId] = (wordPredStrMap[wId] ?? '') + chunk;

      // Extract timestamps mapped exactly in O(1) time
      int globalTokenIdx = asrConsumedTokenCount + absPredIdx;
      int charStart = _getCharIndexForToken(fullCleanTokens, globalTokenIdx);

      for (int c = 0; c < chunk.length; c++) {
        if (charStart + c < currentSegmentTimestamps.length) {
          wordPredTsMap
              .putIfAbsent(wId, () => [])
              .add(currentSegmentTimestamps[charStart + c]);
        }
      }
    }

    for (int w = matchedWordStart; w <= matchedWordEnd; w++) {
      acceptedWordsAsr[w] = wordPredStrMap[w] ?? '';
      acceptedWordsTimestamps[w] = wordPredTsMap[w] ?? [];
    }

    // -------------------------------------------------------------------------
    // [Tajweed] Primary Evaluation Block
    // -------------------------------------------------------------------------
    // If Tajweed mode is on, we send the perfectly aligned paths directly to the
    // professional ErrorExplainer rules engine.
    Map<int, List<ReciterError>>? tajweedErrors;
    if (isTajweed) {
      int globalStartIdx = asrConsumedTokenCount + result.bestStartI;
      int charStart = _getCharIndexForToken(fullCleanTokens, globalStartIdx);
      int safeStartIdx = min(charStart, currentSegmentTimestamps.length);

      tajweedErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments:
            globalAlignments, // The exact operations (equal, replace, insert, delete)
        globalRefChunks: refChunks, // Full reference text
        refChunkToWordMap: chunkToWordMap, // Mapping chunks to word IDs
        currentAsrChunks: matchedAsrSlice, // The actual sounds the user spoke
        // Pass only the raw timestamps that belong to the user's spoken string slice
        trackingTimestamps: currentSegmentTimestamps.sublist(safeStartIdx),

        bestAsrStartIdx: 0,
        targetChunkCursor: 0,
        startWordId: matchedWordStart,
        nextWordId: matchedWordEnd + 1,
        totalAyahWords: wordBoundaries.length - 1,

        // [Tajweed] Confidence-Gating Parameter
        // Protects the UI from spamming false-positive red errors if the
        // microphone quality or acoustic match was poor.
        // We strictly use the `pureAcousticScore` here so Tajweed is not artificially
        // suppressed when the user simply skips a word (which inflates the global score).
        matchScore: result.pureAcousticScore,

        // [Tajweed] Cross-Word Context Parameter
        // Passes the final sound of the previous word so the explainer can
        // verify rules like Idgham that occur across word spaces.
        previousWordTail: lastMatchedPhoneme,

        // Pass the strictness setting to filter output errors based on user preference
        trackingStrictness: trackingStrictness,
      );
    }

    // -------------------------------------------------------------------------
    // Event Emission to UI
    // -------------------------------------------------------------------------

    // If the user skipped a word (e.g., they read Word 3, but the cursor was at Word 1),
    // the system correctly identifies it. We loop over all skipped words and explicitly
    // send them to the UI flagged as `is_red` (skipped/missed).
    for (int w = targetWordCursor; w <= matchedWordEnd; w++) {
      // A word is skipped if it was before the matched path, OR if the DP engine
      // dropped it for failing the strictness threshold (poorly pronounced/hallucinated).
      bool isSkipped =
          (w < matchedWordStart) ||
          !result.words.any((match) => match.wordId == w);

      // ════════════════════════════════════════════════════════════════════════════
      // [ANDROID ASR FAULT DETECTION "THE SHIELD"]
      // ════════════════════════════════════════════════════════════════════════════
      // The DP Engine just told us this word failed strictness, which means `isSkipped`
      // is currently TRUE. By default, this means we are about to emit a Red event.
      // HOWEVER, before we emit it, we look inside the `shieldedWords` array.
      if (isSkipped && result.shieldedWords.contains(w)) {
        // We found the word inside the Shield array! This means the Math Engine proved
        // that the microphone glitched and the user is NOT to blame.
        // We use `continue` to instantly skip the rest of the loop.
        // The Red event is NEVER fired, and the UI word safely stays Grey!
        continue;
      }
      // ════════════════════════════════════════════════════════════════════════════

      if (isSkipped) {
        String skippedWordStr = '';
        for (int i = 0; i < refChunks.length; i++) {
          if (chunkToWordMap[i] == w) skippedWordStr += refChunks[i];
        }
        debugLog('🩸 [HIGHLIGHT] Word "$skippedWordStr" ($w) skipped -> RED');
      }

      List<Map<String, dynamic>> serializedErrors = [];
      if (!isSkipped && tajweedErrors != null && tajweedErrors.containsKey(w)) {
        serializedErrors = tajweedErrors[w]!.map((e) => e.toMap()).toList();
      }

      // This is the message the UI listens to!
      mainSendPort.send({
        'event': 'highlight',
        'word_id': w,
        'is_red': isSkipped,
        'clean_asr': isSkipped ? '' : acceptedWordsAsr[w],
        'word_asr': acceptedWordsAsr,
        'tajweed_errors': serializedErrors,
      });
    }

    // Move the cursor forward past the words we just successfully processed.
    targetWordCursor = matchedWordEnd + 1;

    // We successfully consumed bestI tokens from our unconsumed array.
    asrConsumedTokenCount += result.bestI;

    // [Tajweed] Save the very last phoneme of this successful match to bridge to the next word
    if (matchedRefSlice.isNotEmpty) {
      lastMatchedPhoneme = matchedRefSlice.last;
    }
  }

  // ---------------------------------------------------------------------------
  // Helper Math
  // ---------------------------------------------------------------------------

  int _getCharIndexForToken(List<PhonemeToken> tokens, int tokenIndex) {
    if (tokenIndex >= tokens.length) return currentSegmentAsr.length;
    return tokens[tokenIndex].originalIndex;
  }

  List<double> _getUnconsumedYsProbs(
    List<PhonemeToken> cleanTokens,
    int consumedCount,
  ) {
    int charStart = _getCharIndexForToken(cleanTokens, consumedCount);
    if (charStart < currentSegmentYsProbs.length) {
      return currentSegmentYsProbs.sublist(charStart);
    }
    return [];
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// Worker Entrypoint
/// ────────────────────────────────────────────────────────────────────────────
/// This is the raw C-level entrypoint for the background Isolate thread.
/// It establishes the reverse communication port back to the UI thread, and
/// creates the Sequencer to start handling commands.
void _alignmentWorker(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  final sequencer = DictationSequencer(mainSendPort);

  commandPort.listen((message) {
    if (message is! Map) return;
    int cmd = message['cmd'];

    switch (cmd) {
      case IsolateCommands.setup:
        List<String> tokens = (message['tokens'] as List).cast<String>();
        PhonemeMatrix.preheat(tokens);
        break;
      case IsolateCommands.syncStream:
        sequencer.syncStream(message);
        break;
      case IsolateCommands.setSurahReference:
        sequencer.setSurahReference(message);
        break;
      case IsolateCommands.jumpToWord:
        sequencer.jumpToWord(message);
        break;
      case IsolateCommands.setTajweedMode:
        sequencer.isTajweed = message['isTajweed'];
        break;
      case IsolateCommands.setTrackingStrictness:
        sequencer.trackingStrictness = message['strictness'];
        break;
      case IsolateCommands.shutdown:
        Isolate.current.kill();
        break;
    }
  });
}
