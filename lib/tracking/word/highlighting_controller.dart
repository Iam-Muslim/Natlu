// lib/tracking/word/highlighting_controller.dart
//
// HighlightingController — bridges ASR engine output to per-word highlighting.
//
// Architecture:
//   SherpaEngine → transcriptionStream → HighlightingController → UI
//
// Matching system:
//   Uses PhoneticWordTracker (ported from quran-transcript/src/quran_transcript/
//   tasmeea.py + utils.py) to match the accumulating ASR phonetic stream
//   against the expected Uthmani words of the current ayah word-by-word.
//
//   The ASR model outputs phonetic Arabic (e.g. "بِسمِللَااهِ") that accumulates
//   over time. PhoneticWordTracker normalizes both sides (QuranNormalizer,
//   ported from normalize_aya()) and uses Levenshtein distance to commit
//   words as correct/wrong one at a time.
//
// Word-order constraint (Tarteel-style):
//   - Words must match IN ORDER. A wrong/skipped word turns red immediately.
//   - Advancing to the next ayah is automatic when all words are resolved.
//   - The user selects the start surah+ayah; tracker proceeds sequentially.
//

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';
import '../../engine/sherpa_engine.dart';
import '../../data/quran_data.dart';
import '../tajweed/error_explainer.dart';
import 'phoneme_alignment_isolate.dart';
import 'quran_normalizer.dart';
import '../../utils/debug_logger.dart';

// ── State machine ────────────────────────────────────────────────────────────

/// The three states the live recitation tracker can be in.
///
/// [discovery] — engine is idle / stopped.
/// [tracking]  — actively listening and matching words.
enum TrackerState { discovery, tracking }

// ── Verse match result ───────────────────────────────────────────────────────

/// A matched verse together with its confidence score (0.0 – 1.0).
class VerseMatch {
  /// The matched [QuranVerse].
  final QuranVerse verse;

  /// Match score — always 1.0 for manual/sequential selection.
  final double score;

  VerseMatch({required this.verse, required this.score});

  /// Subscript access for legacy widget code.
  dynamic operator [](String key) {
    if (key == 'surah') return verse.surah;
    if (key == 'ayah') return verse.ayah;
    if (key == 'score') return score;
    if (key == 'text' || key == 'text_uthmani') return verse.textUthmani;
    return null;
  }
}

// ── Verse span match result ──────────────────────────────────────────────────

/// A matched span of verses (kept for voice-search compat).
class VerseSpanMatch {
  final int surah;
  final int startAyah;
  final int endAyah;
  final String textClean;
  final String textUthmani;
  final double score;

  VerseSpanMatch({
    required this.surah,
    required this.startAyah,
    required this.endAyah,
    required this.textClean,
    required this.textUthmani,
    required this.score,
  });
}

// ── Main controller ──────────────────────────────────────────────────────────

class HighlightingController extends ChangeNotifier {
  final SherpaEngine _engine;
  final QuranRepository repository;
  final VoidCallback? onAyahChanged;
  bool isTajweed;

  void setTajweedMode(bool active) {
    if (isTajweed == active) return;
    isTajweed = active;
    if (_isolateStarted) {
      _alignmentIsolate.setTajweedMode(active);
    }
    notifyListeners();
  }

  TrackerState _state = TrackerState.discovery;
  VerseMatch? _currentMatch;
  final ValueNotifier<int?> activeAyah = ValueNotifier(null);

  int _targetSurah = 1;
  int get targetSurah => _targetSurah;

  // ── Per-ayah word status maps ─────────────────────────────────────────────
  // Keyed by ayah number (1-based). Sets contain 0-based word indices.
  final Map<int, Set<int>> _greenWordsByVerse = {};
  final Map<int, Set<int>> _redWordsByVerse = {};
  final Map<int, Set<int>> _yellowWordsByVerse = {};
  final Map<int, Map<int, List<ReciterError>>> _errorsByVerse = {};
  final Set<int> _completedAyahs = {};

  // ── Debug ─────────────────────────────────────────────────────────────────
  final ValueNotifier<String> debugRecognizedText = ValueNotifier('');

  final ValueNotifier<int> globalRevision = ValueNotifier(0);

  final PhonemeAlignmentIsolate _alignmentIsolate = PhonemeAlignmentIsolate();
  bool _isolateStarted = false;

  StreamSubscription? _engineSub;
  StreamSubscription<Map<String, dynamic>>? _wordSub;

  int _lastResetTime = 0;
  String _lastProcessedText = '';
  bool _expectingNewSegment = false;
  int? _pendingClearAyah;

  HighlightingController({
    required this.repository,
    required SherpaEngine engine,
    this.onAyahChanged,
    this.isTajweed = true,
  }) : _engine = engine {
    AppState.instance.addListener(_onAppStateChanged);
    _initIsolate();
    _engineSub = _engine.transcriptionStream.listen(_onResult);
    reset();
  }

  void _onAppStateChanged() {
    if (_isolateStarted) {
      _alignmentIsolate.setTrackingStrictness(
        AppState.instance.trackingStrictness.name,
      );
    }
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppStateChanged);
    _engineSub?.cancel();
    _wordSub?.cancel();
    _alignmentIsolate.stop();
    super.dispose();
  }

  Future<void> _initIsolate() async {
    await _alignmentIsolate.start();
    _isolateStarted = true;
    
    try {
      String tokensStr = await rootBundle.loadString('assets/model/tokens.txt');
      List<String> tokens = [];
      for (String line in tokensStr.split('\n')) {
        var parts = line.split(' ');
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty && parts[0] != '<blank>') {
          tokens.add(parts[0].trim());
        }
      }
      _alignmentIsolate.setup(tokens);
    } catch (e) {
      DebugLogger.logSimple('HighlightingController', 'Failed to load tokens for matrix preheat: $e');
    }
    
    _wordSub = _alignmentIsolate.wordStream.listen(_onIsolateWordMatched);

    if (_currentMatch != null) {
      _setIsolateAyah(_currentMatch!.verse);
    }
  }

  void _setIsolateAyah(QuranVerse verse, {bool forceClear = false}) {
    String combinedTextPhoneme = verse.textPhoneme;
    List<String> combinedPhonemeWords = List.from(verse.phonemeWords);

    String strictness = AppState.instance.trackingStrictness.name;
    int lookaheadWords = strictness == 'strict'
        ? 3
        : (strictness == 'easy' ? 0 : 2); // default

    final nextVerse = repository.getNextVerse(verse.surah, verse.ayah);
    if (nextVerse != null) {
      int wordsToAdd = min(lookaheadWords, nextVerse.phonemeWords.length);
      for (int i = 0; i < wordsToAdd; i++) {
        combinedTextPhoneme += " ${nextVerse.phonemeWords[i]}";
        combinedPhonemeWords.add(nextVerse.phonemeWords[i]);
      }
    }

    _alignmentIsolate.setAyah(
      combinedTextPhoneme,
      _calculateBoundaries(combinedPhonemeWords),
      isTajweed: isTajweed,
      forceClear: forceClear,
      trackingStrictness: AppState.instance.trackingStrictness.name,
    );
  }

  void _onIsolateWordMatched(Map<String, dynamic> event) {
    if (_currentMatch == null) return;
    final targetAyah = _currentMatch!.verse;
    final ayahNum = targetAyah.ayah;

    int wordId = event['word_id'] as int;
    bool isRed = event['is_red'] as bool? ?? false;
    String cleanAsr = event['clean_asr'] as String? ?? '';

    if (!(_greenWordsByVerse[ayahNum]?.contains(wordId) ?? false) &&
        !(_redWordsByVerse[ayahNum]?.contains(wordId) ?? false) &&
        !(_yellowWordsByVerse[ayahNum]?.contains(wordId) ?? false)) {
      if (isRed) {
        (_redWordsByVerse[ayahNum] ??= {}).add(wordId);
      } else {
        (_greenWordsByVerse[ayahNum] ??= {}).add(wordId);
      }

      // =========================================================================
      // Instant Tajweed Evaluation
      // =========================================================================
      // Grade the word instantly the moment it is matched by the ASR.
      if (isTajweed && cleanAsr.isNotEmpty) {
        if (event['tajweed_errors'] != null) {
          final List<dynamic> rawErrors = event['tajweed_errors'];
          final List<ReciterError> wordErrors = rawErrors
              .map((e) => ReciterError.fromMap(Map<String, dynamic>.from(e)))
              .toList();

          if (wordErrors.isNotEmpty) {
            if (_greenWordsByVerse[ayahNum]?.contains(wordId) ?? false) {
              _greenWordsByVerse[ayahNum]?.remove(wordId);
              (_yellowWordsByVerse[ayahNum] ??= {}).add(wordId);
              (_errorsByVerse[ayahNum] ??= {})[wordId] = wordErrors;
              notifyListeners();
            }
          }
        }
      }

      // If this was the last word of the Ayah, automatically advance to the next Ayah!
      if (wordId == targetAyah.phonemeWords.length - 1) {
        _completedAyahs.add(ayahNum);

        final nextVerse = repository.getNextVerse(
          targetAyah.surah,
          targetAyah.ayah,
        );
        if (nextVerse != null) {
          // Delay very slightly to let the UI paint the last word green before jumping
          Future.delayed(const Duration(milliseconds: 50), () {
            forceActiveAyah(nextVerse);
          });
        } else {
          finalize();
        }
      }

      notifyListeners();
    }
  }

  // ── Public accessors ──────────────────────────────────────────────────────

  HighlightingController get tracker => this;
  TrackerState get state => _state;
  VerseMatch? get currentMatchedVerse => _currentMatch;
  Set<int> get completedAyahs => _completedAyahs;
  bool get softWarningActive => false;

  int? get activeWordIndex {
    return null; // Tracking is now fully async in isolate
  }

  // ── Word color queries ────────────────────────────────────────────────────

  int _mapToPhonemeIndex(int ayah, int uthmaniIndex) {
    if (_targetSurah == 0) return uthmaniIndex;
    final verse = repository.getVerse(_targetSurah, ayah);
    if (verse == null ||
        uthmaniIndex < 0 ||
        uthmaniIndex >= verse.wordMap.length) {
      return uthmaniIndex;
    }
    return verse.wordMap[uthmaniIndex];
  }

  bool isWordGreen(int ayah, int wordIndex) {
    if (isWordRed(ayah, wordIndex)) return false;
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _greenWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordRed(int ayah, int wordIndex) {
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _redWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  /// Yellow not used in base mode — kept for Tajweed mode extension.
  bool isWordYellow(int ayah, int wordIndex) {
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _yellowWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  /// Get errors for a word if any
  List<ReciterError>? getWordErrors(int ayah, int wordIndex) {
    int pIdx = _mapToPhonemeIndex(ayah, wordIndex);

    // Fallback to persisted errors (from post-ayah processing or baseline copy)
    return _errorsByVerse[ayah]?[pIdx];
  }

  // ── Surah / ayah management ───────────────────────────────────────────────

  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
    activeAyah.value = null;
    clearHighlights();
    await repository.loadSurahAsync(surah);
    reset();
  }

  void clearHighlights() {
    _completedAyahs.clear();
    _greenWordsByVerse.clear();
    _redWordsByVerse.clear();
    _yellowWordsByVerse.clear();
    _errorsByVerse.clear();
    globalRevision.value++;
    notifyListeners();
  }

  void clearHighlightsFromAyah(int startAyah) {
    _completedAyahs.removeWhere((ayah) => ayah >= startAyah);
    _greenWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _redWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _yellowWordsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    _errorsByVerse.removeWhere((ayah, _) => ayah >= startAyah);
    globalRevision.value++;
    notifyListeners();
  }

  /// Jump to a specific ayah manually (user taps a verse row).
  void setManualAyah(int surah, int ayah) {
    if (_targetSurah != surah) return;
    final verse = repository.getVerse(surah, ayah);
    if (verse != null) {
      _currentMatch = VerseMatch(verse: verse, score: 1.0);
      activeAyah.value = ayah;

      if (_isolateStarted) {
        _setIsolateAyah(verse, forceClear: true);
      }

      _engine.resetBuffer();
      _lastProcessedText = '';
      _lastResetTime = DateTime.now().millisecondsSinceEpoch;
      _pendingClearAyah = ayah;
      onAyahChanged?.call();
      notifyListeners();
    }
  }

  List<int> _calculateBoundaries(List<String> words) {
    List<int> bounds = [];
    int cursor = 0;
    for (String w in words) {
      bounds.add(cursor);
      cursor += w.replaceAll(' ', '').length;
    }
    bounds.add(cursor); // The end boundary
    return bounds;
  }

  // ── Audio pipeline ────────────────────────────────────────────────────────

  void feed(Float32List audioChunk, {bool isFinal = false}) {
    if (_state == TrackerState.discovery) return;
    _engine.transcribe(audioChunk, isFinal: isFinal);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void reset() {
    _state = TrackerState.tracking;
    if (_currentMatch == null) {
      final verse = repository.getVerse(_targetSurah, 1);
      _currentMatch = verse != null
          ? VerseMatch(verse: verse, score: 1.0)
          : null;
    }
    activeAyah.value = _currentMatch?.verse.ayah;
    if (_currentMatch != null && _isolateStarted) {
      _setIsolateAyah(_currentMatch!.verse, forceClear: true);
    }
    _engine.resetBuffer();
    _lastProcessedText = '';
    _expectingNewSegment = false;
    _lastResetTime = DateTime.now().millisecondsSinceEpoch;
    onAyahChanged?.call();
    notifyListeners();
  }

  void finalize() {
    _state = TrackerState.discovery;
    _engine.resetBuffer();
    notifyListeners();
  }

  void resumeTracking() {
    _state = TrackerState.tracking;
    if (_pendingClearAyah != null) {
      clearHighlightsFromAyah(_pendingClearAyah!);
      _pendingClearAyah = null;
    } else if (activeAyah.value != null) {
      clearHighlightsFromAyah(activeAyah.value!);
    }

    // CRITICAL: Synchronize Isolate state! Since we cleared the UI highlights,
    // the isolate must also reset its word cursor back to 0 for this Ayah.
    if (_currentMatch != null && _isolateStarted) {
      _alignmentIsolate.setAyah(
        _currentMatch!.verse.textPhoneme,
        _calculateBoundaries(_currentMatch!.verse.phonemeWords),
        isTajweed: isTajweed,
        forceClear: true,
        trackingStrictness: AppState.instance.trackingStrictness.name,
      );
    }

    _engine.resetBuffer();
    _lastProcessedText = '';
    _lastResetTime = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  void startRecordingSession() {
    resumeTracking();
  }

  void unloadEngine() {
    _state = TrackerState.discovery;
    _engine.destroy();
    _alignmentIsolate.stop();
    notifyListeners();
  }

  Future<void> reloadEngine() async {
    await _engine.initialize();
    notifyListeners();
  }

  void forceActiveAyah(QuranVerse verse) {
    _state = TrackerState.tracking;
    _currentMatch = VerseMatch(verse: verse, score: 1.0);
    activeAyah.value = verse.ayah;
    _lastProcessedText = '';

    if (_isolateStarted) {
      _setIsolateAyah(verse, forceClear: false);
    }

    // We intentionally DO NOT reset the ASR engine or transcript tracking here.
    // This allows seamless continuous recitation across ayahs without boundary clipping,
    // preserving the Zipformer left_context neural network memory cache.
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _onResult(TranscriptionResult result) {
    if (_state == TrackerState.discovery) return;
    if (_currentMatch == null) return;

    if (result.startTime < _lastResetTime) {
      return;
    }

    List<double> charDurations = [];
    List<double> charYsProbs = [];
    StringBuffer asrTextBuffer = StringBuffer();

    const double lookaheadDelay = 0.320;
    List<Map<String, dynamic>> rawStarts = [];
    double lastBlankTs = -1.0;

    for (
      int i = 0;
      i < min(result.tokens.length, result.timestamps.length);
      i++
    ) {
      String tok = result.tokens[i].replaceAll(' ', '');
      double realTs = max(0.0, result.timestamps[i] - lookaheadDelay);

      if (tok.isEmpty ||
          tok == '<blank>' ||
          tok == '<blk>' ||
          tok == '<eps>' ||
          tok == 'eps') {
        lastBlankTs = realTs; // Track the most recent silence marker
        continue;
      }
      
      // Filter out severe acoustic hallucinations (low confidence noise).
      // ysProbs are log probabilities. -2.0 means roughly 13.5% confidence.
      double prob = 0.0;
      if (result.ysProbs.length > i) {
        prob = result.ysProbs[i];
        if (prob < -2.0) {
          continue; // Ignore this token as it's likely microphone noise
        }
      }
      
      rawStarts.add({'tok': tok, 'ts': realTs, 'lastBlankBefore': lastBlankTs, 'prob': prob});
    }

    for (int i = 0; i < rawStarts.length; i++) {
      String token = rawStarts[i]['tok'] as String;
      double spikeTime = rawStarts[i]['ts'] as double;
      double lastBlankBefore = rawStarts[i]['lastBlankBefore'] as double;
      double prob = rawStarts[i]['prob'] as double;

      // 1. Calculate raw gap from previous token's spike time
      double prevSpikeTime = (i == 0)
          ? max(0.0, spikeTime - 0.15)
          : rawStarts[i - 1]['ts'] as double;
          
      // If a <blank> (silence) occurred AFTER the previous token but BEFORE this token,
      // then the speech paused. The true gap for this token should be measured from the
      // end of the silence (the last blank), NOT from the previous word 2 seconds ago!
      if (lastBlankBefore > prevSpikeTime) {
        prevSpikeTime = lastBlankBefore;
      }

      double rawGap = max(0.04, spikeTime - prevSpikeTime);

      // 2. Classify token type based on tokens.txt structure to set acoustic ceiling
      bool isMaddCarrier =
          token.contains('ا') ||
          token.contains('و') ||
          token.contains('ي') ||
          token.contains('ۥ') ||
          token.contains('ۦ');
      bool isDoubledOrNasal =
          (token.length >= 2 && token[0] == token[1]) ||
          token.contains('ن') ||
          token.contains('م') ||
          token.contains('ں') ||
          token.contains('۾');

      // 3. Clamp maximum allowed duration to prevent <blank> transition silence from bloating tokens.
      // We must set these ceilings high enough so that Tajweed rules (like Ghunnah=0.50s or 
      // Shaddah=0.375s) are reachable, AND so that surplus (ziyada) errors can be detected.
      double maxAllowedDur;
      if (isMaddCarrier) {
        maxAllowedDur = max(0.35, token.length * 1.50); // Elongated vowels expand up to rawGap
      } else if (isDoubledOrNasal) {
        maxAllowedDur = max(0.40, token.length * 0.40); // Shaddah / Ghunnah can reach ~1.2s before clipping
      } else {
        // Short consonants should ideally be < 0.15s, but we allow up to 0.40s so that
        // ErrorExplainer can catch if the user erroneously elongated them (e.g. Qalqalah held too long).
        maxAllowedDur = 0.40; 
      }

      double tokenDur = max(0.04, min(rawGap, maxAllowedDur));

      // 4. Distribute token duration across characters
      // Because the ASR model outputs tokens (e.g. "للَا") rather than individual character
      // timestamps, we must mathematically distribute the token's total duration across its characters.
      //
      // The model's token vocabulary relies on character repetition for duration (e.g. "بب" for Shaddah),
      // meaning base characters represent acoustic beats, while diacritics/residuals do not have independent duration.
      // Therefore, we divide the duration EQUALLY among all BASE characters, assigning 0.0 to diacritics.
      double totalWeight = 0.0;
      List<double> charWeights = [];
      for (int j = 0; j < token.length; j++) {
        String ch = token[j];
        double w = QuranNormalizer.isResidual(ch) ? 0.0 : 1.0;
        charWeights.add(w);
        totalWeight += w;
      }
      
      // Fallback if token somehow only contained diacritics
      if (totalWeight == 0.0) {
        for (int j = 0; j < token.length; j++) charWeights[j] = 1.0;
        totalWeight = token.length.toDouble();
      }

      for (int j = 0; j < token.length; j++) {
        asrTextBuffer.write(token[j]);
        // The duration is distributed proportionally based on the character's phonetic weight.
        double charDur = tokenDur * (charWeights[j] / totalWeight);
        charDurations.add(charDur);
        charYsProbs.add(prob);
      }
    }

    final String asrText = asrTextBuffer.toString();
    debugRecognizedText.value = asrText;

    if (asrText.length > 8000) {
      _engine.resetBuffer();
      _lastProcessedText = '';
      return;
    }

    if (asrText.isEmpty) {
      _lastProcessedText = '';
      if (result.isFinal) {
        _expectingNewSegment = true;
      }
      return;
    }

    // Detect if the ASR engine started a completely new segment (e.g. after final=true)
    bool isNewSegment = false;
    if (_expectingNewSegment) {
      isNewSegment = true;
      _expectingNewSegment = false;
    } else if (!asrText.startsWith(_lastProcessedText)) {
      int commonLen = 0;
      int minLen = min(_lastProcessedText.length, asrText.length);
      for (int i = 0; i < minLen; i++) {
        if (_lastProcessedText[i] == asrText[i]) {
          commonLen++;
        } else {
          break;
        }
      }

      // If it shares almost nothing with the old text, it's a new segment, not a tail correction.
      if (commonLen == 0 || (commonLen < 5 && _lastProcessedText.length > 20)) {
        isNewSegment = true;
      }
    }

    if (asrText.isNotEmpty && _isolateStarted) {
      _alignmentIsolate.syncStream(asrText, charDurations, charYsProbs, isNewSegment);
      
      // If the model resets the string, we tell the isolate it's a new segment so it can 
      // safely reset its `asrConsumedTokenCount` to 0. This fixes the massive desync!
    }

    _lastProcessedText = asrText;

    if (result.isFinal) {
      _expectingNewSegment = true;
    }
  }
}
