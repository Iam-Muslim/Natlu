import '../../lib/tracking/common/quran_normalizer.dart';

/// Simulates streaming ASR behavior: incremental token accretion, micro-chunks, and timestamps.
class AsrStreamFrame {
  final List<String> tokens;
  final List<double> timestamps;
  final bool isNewSegment;
  final String debugDescription;

  AsrStreamFrame({
    required this.tokens,
    required this.timestamps,
    this.isNewSegment = false,
    this.debugDescription = '',
  });
}

class AsrChunkSimulator {
  /// Transforms a list of full words into a realistic sequence of streaming ASR frames.
  /// Simulates incremental typing/speaking accretion:
  /// e.g. ["بِ"], ["بِ", "سْ"], ["بِ", "سْ", "مِ"], ["بِ", "سْ", "مِ", "لَّ"], ...
  static List<AsrStreamFrame> simulateStreamingAccretion(
    List<String> words, {
    double baseTokenDuration = 0.12,
    double interWordPause = 0.15,
    bool simulatePruningAtWordCount = false,
  }) {
    final List<AsrStreamFrame> frames = [];
    final List<String> accumulatedTokens = [];
    final List<double> accumulatedTimestamps = [];
    double currentTime = 0.0;

    for (int w = 0; w < words.length; w++) {
      final word = words[w];
      final chunks = QuranNormalizer.chunkPhonemes(word);

      for (int c = 0; c < chunks.length; c++) {
        final chunk = chunks[c];
        accumulatedTokens.add(chunk);
        currentTime += baseTokenDuration;
        accumulatedTimestamps.add(currentTime);

        frames.add(
          AsrStreamFrame(
            tokens: List<String>.from(accumulatedTokens),
            timestamps: List<double>.from(accumulatedTimestamps),
            isNewSegment: false,
            debugDescription: 'Word $w chunk $c/"$chunk" -> Buffer: "${accumulatedTokens.join('')}"',
          ),
        );
      }

      // Add inter-word pause
      currentTime += interWordPause;

      // Optional: simulate Sherpa-ONNX stream pruning every N words
      if (simulatePruningAtWordCount && w > 0 && w % 8 == 0) {
        // Prune the older tokens upstream
        final keepTokens = accumulatedTokens.length > 20 ? 20 : accumulatedTokens.length;
        accumulatedTokens.removeRange(0, accumulatedTokens.length - keepTokens);
        accumulatedTimestamps.removeRange(0, accumulatedTimestamps.length - keepTokens);

        frames.add(
          AsrStreamFrame(
            tokens: List<String>.from(accumulatedTokens),
            timestamps: List<double>.from(accumulatedTimestamps),
            isNewSegment: false,
            debugDescription: '🔄 Stream Pruned (Buffer clamped to $keepTokens tokens)',
          ),
        );
      }
    }

    return frames;
  }

  /// Simulates a sudden segment reset (e.g. user paused and ASR flushed state).
  static List<AsrStreamFrame> simulateSegmentedRecitation(
    List<List<String>> segments, {
    double baseTokenDuration = 0.12,
  }) {
    final List<AsrStreamFrame> frames = [];
    double currentTime = 0.0;

    for (int s = 0; s < segments.length; s++) {
      final segmentWords = segments[s];
      final List<String> segTokens = [];
      final List<double> segTimestamps = [];

      for (final word in segmentWords) {
        final chunks = QuranNormalizer.chunkPhonemes(word);
        for (final chunk in chunks) {
          segTokens.add(chunk);
          currentTime += baseTokenDuration;
          segTimestamps.add(currentTime);

          frames.add(
            AsrStreamFrame(
              tokens: List<String>.from(segTokens),
              timestamps: List<double>.from(segTimestamps),
              isNewSegment: s > 0 && segTokens.length == 1,
              debugDescription: 'Segment $s: "${segTokens.join('')}"',
            ),
          );
        }
      }
      currentTime += 0.5; // pause between segments
    }

    return frames;
  }
}
