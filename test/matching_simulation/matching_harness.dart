import 'dart:async';
import 'dart:isolate';

import '../../lib/tracking/word/dictation_sequencer.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';

/// Captures all events emitted by DictationSequencer during a test run.
class SimulationEventCapture {
  final List<WordMatchedEvent> matchedEvents = [];
  final List<DebugLogEvent> debugEvents = [];
  final Set<int> greenWordIds = {};
  final Set<int> redWordIds = {};
  final Map<int, List<Map<String, dynamic>>> wordTajweedErrors = {};

  final ReceivePort _receivePort = ReceivePort();
  late final SendPort sendPort;
  StreamSubscription? _sub;

  SimulationEventCapture() {
    sendPort = _receivePort.sendPort;
    _sub = _receivePort.listen((rawMsg) {
      if (rawMsg is! Map) return;
      try {
        final event = IsolateEvent.fromMap(rawMsg);
        if (event is WordMatchedEvent) {
          matchedEvents.add(event);
          if (event.isRed) {
            redWordIds.add(event.wordId);
            greenWordIds.remove(event.wordId);
          } else {
            greenWordIds.add(event.wordId);
            redWordIds.remove(event.wordId);
          }
          if (event.tajweedErrors != null) {
            wordTajweedErrors[event.wordId] = event.tajweedErrors!;
          }
        } else if (event is DebugLogEvent) {
          debugEvents.add(event);
        }
      } catch (_) {}
    });
  }

  void reset() {
    matchedEvents.clear();
    debugEvents.clear();
    greenWordIds.clear();
    redWordIds.clear();
    wordTajweedErrors.clear();
  }

  void dispose() {
    _sub?.cancel();
    _receivePort.close();
  }
}

/// Test harness for executing streaming scenarios against DictationSequencer.
class MatchingHarness {
  final SimulationEventCapture capture;
  late final DictationSequencer sequencer;

  MatchingHarness._(this.capture) {
    sequencer = DictationSequencer(capture.sendPort);
  }

  factory MatchingHarness.create() {
    final capture = SimulationEventCapture();
    return MatchingHarness._(capture);
  }

  void setSurahReference({
    required int surahNumber,
    required String fullPhonemes,
    required List<int> boundaries,
    bool isTajweed = false,
    bool forceClear = true,
    int startGlobalWord = 0,
  }) {
    capture.reset();
    sequencer.setSurahReference(
      SetSurahReferenceCommand(
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        surahNumber: surahNumber,
        isTajweed: isTajweed,
        forceClear: forceClear,
        startGlobalWord: startGlobalWord,
      ),
    );
  }

  /// Feeds a sequence of ASR frames to the sequencer and waits for events to flush.
  Future<void> feedFrames(List<AsrStreamFrame> frames, {int ayahNumber = 1}) async {
    for (final frame in frames) {
      sequencer.syncStream(
        SyncStreamCommand(
          asrTokens: frame.tokens,
          timestamps: frame.timestamps,
          isNewSegment: frame.isNewSegment,
          ayahNumber: ayahNumber,
        ),
      );
      // Allow microtasks to deliver isolate messages
      await Future<void>.delayed(Duration.zero);
    }
    // Final flush
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  void dispose() {
    capture.dispose();
  }
}
