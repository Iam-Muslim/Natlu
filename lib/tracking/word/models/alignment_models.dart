// lib/tracking/word/models/alignment_models.dart
// ═══════════════════════════════════════════════════════════════════════════════
// ALIGNMENT DOMAIN MODELS & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

import '../../tajweed/error_explainer.dart';

/// The edit operation chosen in the DP trellis at cell (i, j).
enum AlignmentOp {
  /// Exact phonetic match between ASR and reference (diagonal step).
  match,

  /// Phonetic substitution/replace error (diagonal step with penalty).
  replace,

  /// ASR inserted an extra sound not present in reference (vertical step).
  insert,

  /// ASR omitted or swallowed a required sound (horizontal step).
  delete,
}

/// Parameters configuring the behavior and strictness of the DP alignment engine.
class AlignmentConfig {
  /// Maximum normalized penalty threshold allowed for a valid match.
  final double threshold;

  /// Penalty cost for omitting a reference phoneme (Deletions).
  final double costDel;

  /// Penalty cost for hallucinating an extra phoneme (Insertions).
  final double costIns;

  /// When true, enforces that the final reference phoneme has 0.0 penalty.
  final bool requireStableTail;

  const AlignmentConfig({
    required this.threshold,
    this.costDel = 1.0,
    this.costIns = 1.0,
    this.requireStableTail = false,
  });

  /// Factory helper for standard reciting modes.
  factory AlignmentConfig.fromStrictness(
    String strictness, {
    bool isTajweed = false,
    double averagePhonemeDuration = 0.15,
  }) {
    double threshold = strictness == 'easy'
        ? 0.35
        : (strictness == 'strict' ? 0.15 : 0.25);

    double costDel = strictness == 'easy' ? 0.65 : 1.0;
    double costIns = strictness == 'easy' ? 0.65 : 1.0;

    // Fast Hadr recitation forgiveness
    if (averagePhonemeDuration < 0.08 && strictness != 'easy') {
      costDel = 0.75;
    }

    return AlignmentConfig(
      threshold: threshold,
      costDel: costDel,
      costIns: costIns,
      requireStableTail: isTajweed,
    );
  }
}

/// Represents an individual verified word match from the DP engine.
class WordMatch {
  /// The global Word ID index in the active Ayah.
  final int wordId;

  /// The normalized penalty score (lower is better, 0.0 = perfect match).
  final double score;

  const WordMatch({
    required this.wordId,
    required this.score,
  });

  @override
  String toString() => 'WordMatch(wordId: $wordId, score: ${score.toStringAsFixed(3)})';
}

/// Complete output payload returned by the forward DP matcher.
class AlignmentResult {
  /// Index in the ASR stream where the winning match ended.
  final int bestI;

  /// Index in the Reference window where the winning match ended.
  final int bestJ;

  /// Index in the ASR stream where the winning match started.
  final int bestStartI;

  /// Index in the Reference window where the winning match started.
  final int bestStartJ;

  /// Normalized penalty score for the match.
  final double bestScore;

  /// Unadjusted pure acoustic score.
  final double pureAcousticScore;

  /// Step-by-step phonetic traceback path.
  final List<PhonemeGroupAlignment> trace;

  /// Verified matched words within this alignment.
  final List<WordMatch> words;

  /// Words protected by Acoustic Shielding.
  final List<int> shieldedWords;

  const AlignmentResult({
    required this.bestI,
    required this.bestJ,
    required this.bestStartI,
    required this.bestStartJ,
    required this.bestScore,
    required this.pureAcousticScore,
    required this.trace,
    required this.words,
    this.shieldedWords = const [],
  });

  @override
  String toString() =>
      'AlignmentResult(words: ${words.length}, score: ${bestScore.toStringAsFixed(3)}, asr: [$bestStartI..$bestI], ref: [$bestStartJ..$bestJ])';
}
