// lib/tracking/word/models/isolate_protocol.dart
// ═══════════════════════════════════════════════════════════════════════════════
// STRONGLY-TYPED ISOLATE COMMUNICATION PROTOCOL
// ═══════════════════════════════════════════════════════════════════════════════

/// Sealed base class for all commands sent from Main UI Thread ➔ Alignment Isolate.
sealed class IsolateCommand {
  const IsolateCommand();

  /// Converts command to an isolate-safe primitive Map for Port transmission.
  Map<String, dynamic> toMap();

  /// Deserializes a Map received inside the Isolate back to a typed IsolateCommand.
  static IsolateCommand fromMap(Map map) {
    final command = map['command'] as String?;
    switch (command) {
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

      case 'audio':
        return ProcessAudioCommand(
          asrText: map['tokens'] as String? ?? '',
          timestamps: (map['timestamps'] as List?)?.cast<double>() ?? const [],
          ysProbs: (map['ys_probs'] as List?)?.cast<double>() ?? const [],
        );

      case 'set_strictness':
        return SetStrictnessCommand(
          strictness: map['strictness'] as String? ?? 'normal',
        );

      case 'jump_to_word':
        return JumpToWordCommand(
          targetWord: map['target_word'] as int? ?? 0,
        );

      case 'reset_buffer':
        return const ResetBufferCommand();

      case 'stop':
        return const StopIsolateCommand();

      default:
        throw ArgumentError('Unknown IsolateCommand: $command');
    }
  }
}

/// Command to initialize or switch the active Surah reference in the isolate.
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

/// Command to stream incoming speech recognizer audio into the isolate buffer.
class ProcessAudioCommand extends IsolateCommand {
  final String asrText;
  final List<double> timestamps;
  final List<double> ysProbs;

  const ProcessAudioCommand({
    required this.asrText,
    required this.timestamps,
    required this.ysProbs,
  });

  @override
  Map<String, dynamic> toMap() => {
        'command': 'audio',
        'tokens': asrText,
        'timestamps': timestamps,
        'ys_probs': ysProbs,
      };
}

/// Command to update the tracking strictness level on the fly.
class SetStrictnessCommand extends IsolateCommand {
  final String strictness;

  const SetStrictnessCommand({required this.strictness});

  @override
  Map<String, dynamic> toMap() => {
        'command': 'set_strictness',
        'strictness': strictness,
      };
}

/// Command to manually set the cursor to a specific Word ID (e.g. user tap).
class JumpToWordCommand extends IsolateCommand {
  final int targetWord;

  const JumpToWordCommand({required this.targetWord});

  @override
  Map<String, dynamic> toMap() => {
        'command': 'jump_to_word',
        'target_word': targetWord,
      };
}

/// Command to clear the current ASR audio buffer.
class ResetBufferCommand extends IsolateCommand {
  const ResetBufferCommand();

  @override
  Map<String, dynamic> toMap() => {'command': 'reset_buffer'};
}

/// Command to terminate the isolate cleanly.
class StopIsolateCommand extends IsolateCommand {
  const StopIsolateCommand();

  @override
  Map<String, dynamic> toMap() => {'command': 'stop'};
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENTS (Isolate ➔ Main UI Thread)
// ═══════════════════════════════════════════════════════════════════════════════

/// Sealed base class for all events emitted from Alignment Isolate ➔ Main UI Thread.
sealed class IsolateEvent {
  const IsolateEvent();

  /// Converts event to an isolate-safe primitive Map for Port transmission.
  Map<String, dynamic> toMap();

  /// Deserializes a Map received on Main Port back to a typed IsolateEvent.
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

/// Event emitted when a word is successfully recognized and matched.
class WordMatchedEvent extends IsolateEvent {
  final int wordId;
  final double score;
  final String cleanAsr;
  final List<Map<String, dynamic>>? tajweedErrors;
  final bool isRed;

  const WordMatchedEvent({
    required this.wordId,
    required this.score,
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

/// Event emitted for isolate diagnostic logging.
class DebugLogEvent extends IsolateEvent {
  final String message;
  final String asrBuffer;

  const DebugLogEvent({
    required this.message,
    required this.asrBuffer,
  });

  @override
  Map<String, dynamic> toMap() => {
        'event': 'debug',
        'message': message,
        'asr_buffer': asrBuffer,
      };
}
