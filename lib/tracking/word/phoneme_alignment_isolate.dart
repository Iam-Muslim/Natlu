import 'dart:async';
import 'dart:isolate';

import '../../utils/debug_logger.dart';
import 'phoneme_matrix.dart';
import 'dictation_sequencer.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ISOLATE PROTOCOL (Commands: Main UI ➔ Isolate | Events: Isolate ➔ Main UI)
// ═══════════════════════════════════════════════════════════════════════════════

/// Sealed base class for all commands sent from Main UI Thread ➔ Alignment Isolate.
sealed class IsolateCommand {
  const IsolateCommand();

  Map<String, dynamic> toMap();

  static IsolateCommand fromMap(Map map) {
    final command = map['command'] as String?;
    switch (command) {
      case 'setup':
        return SetupMatrixCommand(
          tokens: (map['tokens'] as List).cast<String>(),
        );

      case 'set_surah_reference':
        return SetSurahReferenceCommand(
          fullPhonemes: map['phonemes'] as String,
          boundaries: (map['boundaries'] as List).cast<int>(),
          surahNumber: map['surahNumber'] as int? ?? 0,
          isTajweed: map['isTajweed'] as bool? ?? false,
          trackingStrictness: map['trackingStrictness'] as String? ?? 'normal',
          forceClear: map['forceClear'] as bool? ?? false,
          startGlobalWord: map['startGlobalWord'] as int? ?? 0,
        );

      case 'sync_stream':
        return SyncStreamCommand(
          asrText: map['tokens'] as String? ?? '',
          timestamps: (map['timestamps'] as List?)?.cast<double>() ?? const [],
          ysProbs: (map['ys_probs'] as List?)?.cast<double>() ?? const [],
          isNewSegment: map['is_new_segment'] as bool? ?? false,
          ayahNumber: map['ayah_number'] as int? ?? 0,
        );

      case 'jump_to_word':
        return JumpToWordCommand(
          globalWordIndex: map['global_word_index'] as int? ?? 0,
        );

      case 'set_tajweed_mode':
        return SetTajweedModeCommand(
          isTajweed: map['is_tajweed'] as bool? ?? false,
        );

      case 'set_strictness':
        return SetTrackingStrictnessCommand(
          strictness: map['strictness'] as String? ?? 'normal',
        );

      case 'stop':
        return const StopIsolateCommand();

      default:
        throw ArgumentError('Unknown IsolateCommand: $command');
    }
  }
}

class SetupMatrixCommand extends IsolateCommand {
  final List<String> tokens;
  const SetupMatrixCommand({required this.tokens});

  @override
  Map<String, dynamic> toMap() => {'command': 'setup', 'tokens': tokens};
}

class SetSurahReferenceCommand extends IsolateCommand {
  final String fullPhonemes;
  final List<int> boundaries;
  final int surahNumber;
  final bool isTajweed;
  final String trackingStrictness;
  final bool forceClear;
  final int startGlobalWord;

  const SetSurahReferenceCommand({
    required this.fullPhonemes,
    required this.boundaries,
    required this.surahNumber,
    this.isTajweed = false,
    this.trackingStrictness = 'normal',
    this.forceClear = false,
    this.startGlobalWord = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
        'command': 'set_surah_reference',
        'phonemes': fullPhonemes,
        'boundaries': boundaries,
        'surahNumber': surahNumber,
        'isTajweed': isTajweed,
        'trackingStrictness': trackingStrictness,
        'forceClear': forceClear,
        'startGlobalWord': startGlobalWord,
      };
}

class SyncStreamCommand extends IsolateCommand {
  final String asrText;
  final List<double> timestamps;
  final List<double> ysProbs;
  final bool isNewSegment;
  final int ayahNumber;

  const SyncStreamCommand({
    required this.asrText,
    required this.timestamps,
    this.ysProbs = const [],
    this.isNewSegment = false,
    this.ayahNumber = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
        'command': 'sync_stream',
        'tokens': asrText,
        'timestamps': timestamps,
        'ys_probs': ysProbs,
        'is_new_segment': isNewSegment,
        'ayah_number': ayahNumber,
      };
}

class JumpToWordCommand extends IsolateCommand {
  final int globalWordIndex;
  const JumpToWordCommand({required this.globalWordIndex});

  @override
  Map<String, dynamic> toMap() => {
        'command': 'jump_to_word',
        'global_word_index': globalWordIndex,
      };
}

class SetTajweedModeCommand extends IsolateCommand {
  final bool isTajweed;
  const SetTajweedModeCommand({required this.isTajweed});

  @override
  Map<String, dynamic> toMap() => {
        'command': 'set_tajweed_mode',
        'is_tajweed': isTajweed,
      };
}

class SetTrackingStrictnessCommand extends IsolateCommand {
  final String strictness;
  const SetTrackingStrictnessCommand({required this.strictness});

  @override
  Map<String, dynamic> toMap() => {
        'command': 'set_strictness',
        'strictness': strictness,
      };
}

class StopIsolateCommand extends IsolateCommand {
  const StopIsolateCommand();

  @override
  Map<String, dynamic> toMap() => {'command': 'stop'};
}

/// Sealed base class for all events emitted from Alignment Isolate ➔ Main UI Thread.
sealed class IsolateEvent {
  const IsolateEvent();

  Map<String, dynamic> toMap();

  static IsolateEvent fromMap(Map map) {
    final event = map['event'] as String?;
    switch (event) {
      case 'highlight':
        return WordMatchedEvent(
          wordId: map['word_id'] as int,
          score: (map['score'] as num?)?.toDouble() ?? 0.0,
          cleanAsr: map['clean_asr'] as String? ?? '',
          tajweedErrors: (map['tajweed_errors'] as List?)
              ?.map((e) => (e as Map).cast<String, dynamic>())
              .toList(),
          isRed: map['is_red'] as bool? ?? false,
        );

      case 'debug':
        return DebugLogEvent(
          message: map['message'] as String? ?? '',
          asrBuffer: map['asr_buffer'] as String? ?? '',
        );

      default:
        throw ArgumentError('Unknown IsolateEvent: $event');
    }
  }
}

class WordMatchedEvent extends IsolateEvent {
  final int wordId;
  final double score;
  final String cleanAsr;
  final List<Map<String, dynamic>>? tajweedErrors;
  final bool isRed;

  const WordMatchedEvent({
    required this.wordId,
    this.score = 0.0,
    required this.cleanAsr,
    this.tajweedErrors,
    this.isRed = false,
  });

  @override
  Map<String, dynamic> toMap() => {
        'event': 'highlight',
        'word_id': wordId,
        'score': score,
        'clean_asr': cleanAsr,
        'tajweed_errors': tajweedErrors,
        'is_red': isRed,
      };
}

class DebugLogEvent extends IsolateEvent {
  final String message;
  final String asrBuffer;

  const DebugLogEvent({required this.message, required this.asrBuffer});

  @override
  Map<String, dynamic> toMap() => {
        'event': 'debug',
        'message': message,
        'asr_buffer': asrBuffer,
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND ISOLATE WORKER ENTRYPOINT
// ═══════════════════════════════════════════════════════════════════════════════

void alignmentWorkerEntrypoint(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  final sequencer = DictationSequencer(mainSendPort);

  commandPort.listen((rawMessage) {
    if (rawMessage is! Map) return;

    final IsolateCommand command;
    try {
      command = IsolateCommand.fromMap(rawMessage);
    } catch (_) {
      return;
    }

    try {
      switch (command) {
        case SetupMatrixCommand(:final tokens):
          PhonemeMatrix.preheat(tokens);

        case SetSurahReferenceCommand():
          sequencer.setSurahReference(command);

        case SyncStreamCommand():
          sequencer.syncStream(command);

        case JumpToWordCommand():
          sequencer.jumpToWord(command);

        case SetTajweedModeCommand(:final isTajweed):
          sequencer.isTajweed = isTajweed;

        case SetTrackingStrictnessCommand(:final strictness):
          sequencer.trackingStrictness = strictness;

        case StopIsolateCommand():
          Isolate.current.kill();
      }
    } catch (e, stack) {
      mainSendPort.send(
        DebugLogEvent(
          message: '⚠️ [ISOLATE ERROR] Handled exception: $e\n$stack',
          asrBuffer: sequencer.currentSegmentAsr,
        ).toMap(),
      );
    }
  });

}

// ═══════════════════════════════════════════════════════════════════════════════
// UI-SIDE ISOLATE MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Main UI thread manager for the background alignment isolate.
class PhonemeAlignmentIsolate {
  SendPort? _sendPort;
  Isolate? _isolate;

  final StreamController<WordMatchedEvent> _wordStreamController =
      StreamController<WordMatchedEvent>.broadcast();

  Stream<WordMatchedEvent> get wordStream => _wordStreamController.stream;

  Future<void> start() async {
    final receivePort = ReceivePort();
    final completer = Completer<void>();

    _isolate = await Isolate.spawn(
      alignmentWorkerEntrypoint,
      receivePort.sendPort,
    );

    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        completer.complete();
      } else if (message is Map) {
        try {
          final event = IsolateEvent.fromMap(message);
          switch (event) {
            case WordMatchedEvent():
              _wordStreamController.add(event);
            case DebugLogEvent(:final message, :final asrBuffer):
              DebugLogger.updateAsrBuffer(asrBuffer);
              DebugLogger.log('DP', message);
          }
        } catch (_) {
          // Ignore malformed event
        }
      }
    });

    return completer.future;
  }

  void send(IsolateCommand command) {
    _sendPort?.send(command.toMap());
  }

  void setup(List<String> tokens) {
    send(SetupMatrixCommand(tokens: tokens));
  }

  void setSurahReference(
    String expectedPhonemes,
    List<int> wordBoundaries, {
    bool isTajweed = false,
    bool forceClear = false,
    String trackingStrictness = 'normal',
    int startGlobalWord = 0,
    int surahNumber = 0,
  }) {
    send(
      SetSurahReferenceCommand(
        fullPhonemes: expectedPhonemes,
        boundaries: wordBoundaries,
        surahNumber: surahNumber,
        isTajweed: isTajweed,
        forceClear: forceClear,
        trackingStrictness: trackingStrictness,
        startGlobalWord: startGlobalWord,
      ),
    );
  }

  void jumpToWord(int globalWordIndex) {
    send(JumpToWordCommand(globalWordIndex: globalWordIndex));
  }

  void syncStream(
    String fullSegmentAsr,
    List<double> segmentTimestamps, [
    List<double>? segmentYsProbs,
    bool isNewSegment = false,
    int ayahNumber = 0,
  ]) {
    send(
      SyncStreamCommand(
        asrText: fullSegmentAsr,
        timestamps: segmentTimestamps,
        ysProbs: segmentYsProbs ?? const [],
        isNewSegment: isNewSegment,
        ayahNumber: ayahNumber,
      ),
    );
  }

  void setTajweedMode(bool isTajweed) {
    send(SetTajweedModeCommand(isTajweed: isTajweed));
  }

  void setTrackingStrictness(String strictness) {
    send(SetTrackingStrictnessCommand(strictness: strictness));
  }

  void stop() {
    send(const StopIsolateCommand());
    _wordStreamController.close();
    _isolate?.kill();
    _isolate = null;
    _sendPort = null;
  }
}
