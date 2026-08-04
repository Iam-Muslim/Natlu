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
/// - Slices strict monotonic target windows (active expected word) for the Matcher.
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
  /// maps them to specific global Word IDs, and builds the chunk lookup arrays.
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
    lastMatchedPhoneme = null;

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
  /// This loop takes the incoming buffer of ASR audio, matches against the active
  /// expected word, and if matched, commits the word, advances the cursor, and
  /// loops immediately in the same tick to process any subsequent words recited
  /// in the same breath.
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

      // [CRITICAL ROLLBACK HANDLING]
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
      // Strict Monotonic Target Window (Active Expected Word)
      // -----------------------------------------------------------------------
      int wordCount = wordBoundaries.length - 1;
      if (targetWordCursor >= wordCount ||
          targetWordCursor >= wordStartChunk.length ||
          targetWordCursor >= wordEndChunk.length) {
        break;
      }

      int winStartChunk = wordStartChunk[targetWordCursor];
      int winEndChunk = wordEndChunk[targetWordCursor];

      if (winStartChunk >= winEndChunk) break;

      debugLog(
        '🔍 [WINDOW] Analyzing reference chunks [$winStartChunk..${winEndChunk - 1}] (Word $targetWordCursor). ASR buffer size: $m chunks.',
      );

      List<String> targetWindow = refChunks.sublist(winStartChunk, winEndChunk);

      // Compute dynamic alignment configuration based on recitation speed & strictness
      double averagePhonemeDuration = 0.15;
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

      final alignmentConfig = AlignmentConfig.fromStrictness(
        trackingStrictness,
        isTajweed: isTajweed,
        averagePhonemeDuration: averagePhonemeDuration,
      );

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
  /// to the exact active word, routes it through the Tajweed ErrorExplainer if needed,
  /// and fires the highlight message to the UI.
  void _commitMatch(
    AlignmentResult result,
    List<PhonemeToken> unconsumedTokens,
    List<PhonemeToken> fullCleanTokens,
    List<String> targetWindow,
    int winStartChunk,
  ) {
    int w = targetWordCursor;

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

    String wordPredStr = '';
    List<double> wordPredTs = [];

    // Group the ASR sounds and timestamps strictly for this word.
    for (var align in localAlignments) {
      if (align.refIdx < 0 || align.predIdx < 0) continue;
      int absRefIdx = winStartChunk + result.bestStartJ + align.refIdx;
      if (absRefIdx >= chunkToWordMap.length) continue;

      int wId = chunkToWordMap[absRefIdx];
      if (wId != w) continue;

      int absPredIdx = result.bestStartI + align.predIdx;
      String chunk = unconsumedTokens[absPredIdx].text;
      wordPredStr += chunk;

      // Extract timestamps mapped exactly in O(1) time
      int globalTokenIdx = asrConsumedTokenCount + absPredIdx;
      int charStart = _getCharIndexForToken(fullCleanTokens, globalTokenIdx);

      for (int c = 0; c < chunk.length; c++) {
        if (charStart + c < currentSegmentTimestamps.length) {
          wordPredTs.add(currentSegmentTimestamps[charStart + c]);
        }
      }
    }

    acceptedWordsAsr[w] = wordPredStr;
    acceptedWordsTimestamps[w] = wordPredTs;

    // -------------------------------------------------------------------------
    // [Tajweed] Primary Evaluation Block
    // -------------------------------------------------------------------------
    Map<int, List<ReciterError>>? tajweedErrors;
    if (isTajweed) {
      int globalStartIdx = asrConsumedTokenCount + result.bestStartI;
      int charStart = _getCharIndexForToken(fullCleanTokens, globalStartIdx);
      int safeStartIdx = min(charStart, currentSegmentTimestamps.length);

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

    // -------------------------------------------------------------------------
    // Event Emission to UI
    // -------------------------------------------------------------------------
    List<Map<String, dynamic>> serializedErrors = [];
    if (tajweedErrors != null && tajweedErrors.containsKey(w)) {
      serializedErrors = tajweedErrors[w]!.map((e) => e.toMap()).toList();
    }

    mainSendPort.send({
      'event': 'highlight',
      'word_id': w,
      'is_red': false,
      'clean_asr': acceptedWordsAsr[w],
      'word_asr': acceptedWordsAsr,
      'tajweed_errors': serializedErrors,
    });

    // Advance the monotonic cursor forward to the next word.
    targetWordCursor++;

    // Consume matched tokens from the ASR buffer.
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
