import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/quran_data.dart';
import '../../engine/sherpa_engine.dart';
import '../../state/app_state.dart';
import '../../utils/debug_logger.dart';
import '../common/quran_normalizer.dart';
import '../tajweed/error_explainer.dart';
import 'phoneme_alignment_isolate.dart';

export 'phoneme_alignment_isolate.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TRACKING DOMAIN MODELS
// ═══════════════════════════════════════════════════════════════════════════════

enum TrackerState { discovery, tracking }

class VerseMatch {
  final QuranVerse verse;
  final double score;

  const VerseMatch({required this.verse, required this.score});

  dynamic operator [](String key) {
    if (key == 'surah') return verse.surah;
    if (key == 'ayah') return verse.ayah;
    if (key == 'score') return score;
    if (key == 'text' || key == 'text_uthmani') return verse.textUthmani;
    return null;
  }
}


// ═══════════════════════════════════════════════════════════════════════════════
// ASR ACOUSTIC TOKEN PROCESSOR
// ═══════════════════════════════════════════════════════════════════════════════

class ProcessedAudioStream {
  final String asrText;
  final List<double> charDurations;
  final List<double> charYsProbs;

  const ProcessedAudioStream({
    required this.asrText,
    required this.charDurations,
    required this.charYsProbs,
  });

  bool get isEmpty => asrText.isEmpty;
  bool get isNotEmpty => asrText.isNotEmpty;
}

class AsrTokenProcessor {
  static const double lookaheadDelay = 0.320;

  static ProcessedAudioStream process(TranscriptionResult result) {
    final List<double> charDurations = [];
    final List<double> charYsProbs = [];
    final StringBuffer asrTextBuffer = StringBuffer();

    final List<String> rawTokens = [];
    final List<double> rawSpikeTimes = [];
    final List<double> rawLastBlanks = [];
    final List<double> rawTokenProbs = [];
    double lastBlankTs = -1.0;

    final int maxCount = min(result.tokens.length, result.timestamps.length);

    for (int i = 0; i < maxCount; i++) {
      final String tok = result.tokens[i].replaceAll(' ', '');
      final double realTs = max(0.0, result.timestamps[i] - lookaheadDelay);

      if (tok.isEmpty ||
          tok == '<blank>' ||
          tok == '<blk>' ||
          tok == '<eps>' ||
          tok == 'eps') {
        lastBlankTs = realTs;
        continue;
      }

      double prob = 0.0;
      if (result.ysProbs.length > i) {
        prob = result.ysProbs[i];
        if (prob < -2.0) {
          continue;
        }
      }

      rawTokens.add(tok);
      rawSpikeTimes.add(realTs);
      rawLastBlanks.add(lastBlankTs);
      rawTokenProbs.add(prob);
    }

    for (int i = 0; i < rawTokens.length; i++) {
      final String token = rawTokens[i];
      final double spikeTime = rawSpikeTimes[i];
      final double lastBlankBefore = rawLastBlanks[i];
      final double prob = rawTokenProbs[i];

      double prevSpikeTime =
          (i == 0) ? max(0.0, spikeTime - 0.15) : rawSpikeTimes[i - 1];

      if (lastBlankBefore > prevSpikeTime) {
        prevSpikeTime = lastBlankBefore;
      }

      final double rawGap = max(0.04, spikeTime - prevSpikeTime);

      final bool isMaddCarrier = token.contains('ا') ||
          token.contains('و') ||
          token.contains('ي') ||
          token.contains('ۥ') ||
          token.contains('ۦ');

      final bool isDoubledOrNasal =
          (token.length >= 2 && token[0] == token[1]) ||
              token.contains('ن') ||
              token.contains('م') ||
              token.contains('ں') ||
              token.contains('۾');

      final double maxAllowedDur;
      if (isMaddCarrier) {
        maxAllowedDur = max(0.35, token.length * 1.50);
      } else if (isDoubledOrNasal) {
        maxAllowedDur = max(0.40, token.length * 0.40);
      } else {
        maxAllowedDur = 0.40;
      }

      final double tokenDur = max(0.04, min(rawGap, maxAllowedDur));

      double totalWeight = 0.0;
      final List<double> charWeights = [];
      for (int j = 0; j < token.length; j++) {
        final String ch = token[j];
        final double w = QuranNormalizer.isResidual(ch) ? 0.0 : 1.0;
        charWeights.add(w);
        totalWeight += w;
      }

      if (totalWeight == 0.0) {
        for (int j = 0; j < token.length; j++) {
          charWeights.add(1.0);
        }
        totalWeight = token.length.toDouble();
      }

      for (int j = 0; j < token.length; j++) {
        asrTextBuffer.write(token[j]);
        final double charDur = tokenDur * (charWeights[j] / totalWeight);
        charDurations.add(charDur);
        charYsProbs.add(prob);
      }
    }

    return ProcessedAudioStream(
      asrText: asrTextBuffer.toString(),
      charDurations: charDurations,
      charYsProbs: charYsProbs,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UI HIGHLIGHTING CONTROLLER
// ═══════════════════════════════════════════════════════════════════════════════

/// Bridges speech recognition engine output to per-word visual highlighting in the UI.
class HighlightingController extends ChangeNotifier {
  final SherpaEngine _engine;
  final QuranRepository repository;
  final VoidCallback? onAyahChanged;
  bool isTajweed;

  TrackerState _state = TrackerState.discovery;
  VerseMatch? _currentMatch;
  final ValueNotifier<int?> activeAyah = ValueNotifier(null);

  int _targetSurah = 1;
  int get targetSurah => _targetSurah;

  // Per-Ayah Word Status Maps
  final Map<int, Set<int>> _greenWordsByVerse = {};
  final Map<int, Set<int>> _redWordsByVerse = {};
  final Map<int, Set<int>> _yellowWordsByVerse = {};
  final Map<int, Map<int, List<ReciterError>>> _errorsByVerse = {};
  final Set<int> _completedAyahs = {};

  // Debug State
  final ValueNotifier<String> debugRecognizedText = ValueNotifier('');
  final ValueNotifier<int> globalRevision = ValueNotifier(0);

  // Isolate Pipeline
  final PhonemeAlignmentIsolate _alignmentIsolate = PhonemeAlignmentIsolate();
  bool _isolateStarted = false;

  StreamSubscription? _engineSub;
  StreamSubscription<WordMatchedEvent>? _wordSub;

  int _lastResetTime = 0;
  String _lastProcessedText = '';
  bool _expectingNewSegment = false;
  int? _pendingClearAyah;

  List<ContinuousQuranWord> _currentSurahWords = [];
  List<int> _currentSurahBoundaries = [];

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

  void setTajweedMode(bool active) {
    if (isTajweed == active) return;
    isTajweed = active;
    if (_isolateStarted) {
      _alignmentIsolate.setTajweedMode(active);
    }
    notifyListeners();
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
      final String tokensStr =
          await rootBundle.loadString('assets/model/tokens.txt');
      final List<String> tokens = [];
      for (final line in tokensStr.split('\n')) {
        final parts = line.split(' ');
        if (parts.isNotEmpty &&
            parts[0].trim().isNotEmpty &&
            parts[0] != '<blank>') {
          tokens.add(parts[0].trim());
        }
      }
      _alignmentIsolate.setup(tokens);
    } catch (e) {
      DebugLogger.logSimple(
        'HighlightingController',
        'Failed to load tokens for matrix preheat: $e',
      );
    }

    _wordSub = _alignmentIsolate.wordStream.listen(_onIsolateWordMatched);

    if (_targetSurah != 0) {
      _setSurahReference(forceClear: true, startGlobalWord: 0);
    }
  }

  void _setSurahReference({
    bool forceClear = false,
    int startGlobalWord = 0,
  }) {
    if (_targetSurah == 0 || !_isolateStarted) return;
    _currentSurahWords = repository.getSurahWords(_targetSurah);
    if (_currentSurahWords.isEmpty) return;

    final List<String> phonemeWords =
        _currentSurahWords.map((w) => w.phoneme).toList();
    _currentSurahBoundaries = _calculateBoundaries(phonemeWords);
    final String fullPhonemes = phonemeWords.join('');

    _alignmentIsolate.setSurahReference(
      fullPhonemes,
      _currentSurahBoundaries,
      isTajweed: isTajweed,
      forceClear: forceClear,
      trackingStrictness: AppState.instance.trackingStrictness.name,
      startGlobalWord: startGlobalWord,
      surahNumber: _targetSurah,
    );
  }

  void _onIsolateWordMatched(WordMatchedEvent event) {
    final int globalWordId = event.wordId;
    final bool isRed = event.isRed;
    final String cleanAsr = event.cleanAsr;

    if (globalWordId < 0 || globalWordId >= _currentSurahWords.length) return;
    final word = _currentSurahWords[globalWordId];
    final ayahNum = word.ayah;
    final wordIdInAyah = word.wordInAyah;

    if (!(_greenWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) &&
        !(_redWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) &&
        !(_yellowWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false)) {
      if (isRed) {
        (_redWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
      } else {
        (_greenWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
      }

      if (activeAyah.value != ayahNum) {
        activeAyah.value = ayahNum;
        final v = repository.getVerse(_targetSurah, ayahNum);
        if (v != null) {
          _currentMatch = VerseMatch(verse: v, score: 1.0);
          onAyahChanged?.call();
        }
      }

      if (isTajweed && cleanAsr.isNotEmpty && event.tajweedErrors != null) {
        final List<ReciterError> wordErrors = event.tajweedErrors!
            .map((e) => ReciterError.fromMap(Map<String, dynamic>.from(e)))
            .toList();

        if (wordErrors.isNotEmpty) {
          if (_greenWordsByVerse[ayahNum]?.contains(wordIdInAyah) ?? false) {
            _greenWordsByVerse[ayahNum]?.remove(wordIdInAyah);
            (_yellowWordsByVerse[ayahNum] ??= {}).add(wordIdInAyah);
            (_errorsByVerse[ayahNum] ??= {})[wordIdInAyah] = wordErrors;
          }
        }
      }

      final verse = repository.getVerse(_targetSurah, ayahNum);
      if (verse != null && wordIdInAyah == verse.phonemeWords.length - 1) {
        _completedAyahs.add(ayahNum);

        final nextVerse = repository.getNextVerse(_targetSurah, ayahNum);
        if (nextVerse != null) {
          activeAyah.value = nextVerse.ayah;
          _currentMatch = VerseMatch(verse: nextVerse, score: 1.0);
          onAyahChanged?.call();
        }
      }

      if (globalWordId == _currentSurahWords.length - 1) {
        finalize();
      }

      notifyListeners();
    }
  }

  // Public Accessors
  HighlightingController get tracker => this;
  TrackerState get state => _state;
  VerseMatch? get currentMatchedVerse => _currentMatch;
  Set<int> get completedAyahs => _completedAyahs;

  // Word Color Queries
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
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _greenWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordRed(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _redWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  bool isWordYellow(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _yellowWordsByVerse[ayah]?.contains(pIdx) ?? false;
  }

  List<ReciterError>? getWordErrors(int ayah, int wordIndex) {
    final int pIdx = _mapToPhonemeIndex(ayah, wordIndex);
    return _errorsByVerse[ayah]?[pIdx];
  }

  // Surah / Ayah Management
  Future<void> setTargetSurah(int surah) async {
    _targetSurah = surah;
    _currentMatch = null;
    activeAyah.value = null;
    clearHighlights();
    await repository.loadSurahAsync(surah);
    _currentSurahWords = repository.getSurahWords(surah);
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

  void setManualAyah(int surah, int ayah) {
    if (_targetSurah != surah) return;
    final verse = repository.getVerse(surah, ayah);
    if (verse != null) {
      _currentMatch = VerseMatch(verse: verse, score: 1.0);
      activeAyah.value = ayah;

      final int startWord =
          repository.getAyahStartGlobalIndex(surah, ayah);

      if (_isolateStarted) {
        _alignmentIsolate.jumpToWord(startWord);
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
    final List<int> bounds = [];
    int cursor = 0;
    for (final w in words) {
      bounds.add(cursor);
      cursor += w.replaceAll(' ', '').length;
    }
    bounds.add(cursor);
    return bounds;
  }

  void feed(Float32List audioChunk, {bool isFinal = false}) {
    if (_state == TrackerState.discovery) return;
    _engine.transcribe(audioChunk, isFinal: isFinal);
  }

  // Lifecycle
  void reset() {
    _state = TrackerState.tracking;
    _currentSurahWords = repository.getSurahWords(_targetSurah);
    if (_currentMatch == null) {
      final verse = repository.getVerse(_targetSurah, 1);
      _currentMatch =
          verse != null ? VerseMatch(verse: verse, score: 1.0) : null;
    }
    activeAyah.value = _currentMatch?.verse.ayah ?? 1;
    if (_isolateStarted) {
      _setSurahReference(forceClear: true, startGlobalWord: 0);
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
    int resumeAyah = 1;
    if (_pendingClearAyah != null) {
      resumeAyah = _pendingClearAyah!;
      clearHighlightsFromAyah(_pendingClearAyah!);
      _pendingClearAyah = null;
    } else if (activeAyah.value != null) {
      resumeAyah = activeAyah.value!;
      clearHighlightsFromAyah(activeAyah.value!);
    }

    final int startGlobalWord =
        repository.getAyahStartGlobalIndex(_targetSurah, resumeAyah);
    if (_isolateStarted) {
      _alignmentIsolate.jumpToWord(startGlobalWord);
    }

    _engine.resetBuffer();
    _lastProcessedText = '';
    _expectingNewSegment = true;
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
    notifyListeners();
  }

  void flushAndResetForNextAyah() {}

  // ASR Ingestion
  void _onResult(TranscriptionResult result) {
    if (_state == TrackerState.discovery) return;
    if (_currentMatch == null) return;

    if (result.startTime < _lastResetTime ||
        result.streamEpoch != _engine.currentStreamEpoch) {
      return;
    }

    final ProcessedAudioStream stream = AsrTokenProcessor.process(result);
    final String asrText = stream.asrText;
    debugRecognizedText.value = asrText;

    if (asrText.length > 8000) {
      _engine.resetBuffer();
      _lastProcessedText = '';
      return;
    }

    if (asrText.isEmpty) {
      _lastProcessedText = '';
      return;
    }

    bool isNewSegment = false;
    if (_expectingNewSegment) {
      isNewSegment = true;
      _expectingNewSegment = false;
    } else if (!asrText.startsWith(_lastProcessedText)) {
      int commonLen = 0;
      final int minLen = min(_lastProcessedText.length, asrText.length);
      for (int i = 0; i < minLen; i++) {
        if (_lastProcessedText[i] == asrText[i]) {
          commonLen++;
        } else {
          break;
        }
      }

      if (commonLen == 0 ||
          (commonLen < 5 && _lastProcessedText.length > 20)) {
        isNewSegment = true;
      }
    }

    if (asrText.isNotEmpty && _isolateStarted) {
      if (!isNewSegment && asrText == _lastProcessedText) {
        return;
      }
      _lastProcessedText = asrText;
      _alignmentIsolate.syncStream(
        asrText,
        stream.charDurations,
        stream.charYsProbs,
        isNewSegment,
        _currentMatch?.verse.ayah ?? 0,
      );
    }

    _lastProcessedText = asrText;
  }
}
