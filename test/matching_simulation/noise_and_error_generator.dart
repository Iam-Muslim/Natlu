import 'dart:math';

import '../../lib/tracking/common/quran_normalizer.dart';

/// Injects realistic speech variations, ASR weaknesses, deletions, repetitions, and noise.
class NoiseAndErrorGenerator {
  final Random _rnd;

  NoiseAndErrorGenerator([int seed = 42]) : _rnd = Random(seed);

  static const Map<String, List<String>> _acousticSubstitutions = {
    'س': ['ص', 'ث', 'ز'],
    'ص': ['س', 'ض'],
    'ت': ['ط', 'د', 'ث'],
    'ط': ['ت', 'ض', 'ظ'],
    'د': ['ض', 'ت', 'ذ'],
    'ض': ['د', 'ظ', 'ط'],
    'ذ': ['ز', 'ظ', 'ث', 'د'],
    'ظ': ['ذ', 'ض', 'ط', 'ز'],
    'ق': ['ك', 'غ', 'ء'],
    'ك': ['ق', 'ت'],
    'ع': ['ء', 'ح', 'غ'],
    'ء': ['ع', 'ه', 'ا'],
    'ح': ['ه', 'خ', 'ع'],
    'ه': ['ح', 'ء'],
    'غ': ['خ', 'ق', 'ع'],
    'خ': ['غ', 'ح'],
    'ث': ['س', 'ت', 'ذ'],
    'ز': ['س', 'ذ', 'ظ'],
    'ن': ['م', 'ں'],
    'م': ['ن', 'ب'],
    'ب': ['م', 'ف'],
    'ف': ['ث', 'ب'],
    'ل': ['ر', 'ن'],
    'ر': ['ل', 'غ'],
  };

  static const List<String> _babbleInterjections = [
    'أعوذ',
    'يعني',
    'أه',
    'اممم',
    'صدق',
    'كح',
    'نعم',
    'طيب',
  ];

  /// Introduces acoustic drift / model weakness to a list of word phonemes.
  List<String> applyAcousticWeakness(List<String> wordPhonemes, {double errorProbability = 0.15}) {
    final List<String> result = [];
    for (final word in wordPhonemes) {
      final chunks = QuranNormalizer.chunkPhonemes(word);
      final List<String> corruptedChunks = [];

      for (final ch in chunks) {
        if (ch.isNotEmpty && _rnd.nextDouble() < errorProbability) {
          final baseChar = ch[0];
          final subs = _acousticSubstitutions[baseChar];
          if (subs != null && subs.isNotEmpty) {
            final chosenSub = subs[_rnd.nextInt(subs.length)];
            final rest = ch.substring(1);
            corruptedChunks.add('$chosenSub$rest');
            continue;
          }
        }
        corruptedChunks.add(ch);
      }
      result.add(corruptedChunks.join(''));
    }
    return result;
  }

  /// Skips specific word indices in a list of words.
  List<String> applyWordSkips(List<String> words, Set<int> indicesToSkip) {
    final List<String> result = [];
    for (int i = 0; i < words.length; i++) {
      if (!indicesToSkip.contains(i)) {
        result.add(words[i]);
      }
    }
    return result;
  }

  /// Simulates a reciter stumbling and repeating a word.
  List<String> applyWordRepetition(List<String> words, int repeatWordIndex) {
    final List<String> result = [];
    for (int i = 0; i < words.length; i++) {
      result.add(words[i]);
      if (i == repeatWordIndex) {
        // Reciter stumbles and says it again
        result.add(words[i]);
      }
    }
    return result;
  }

  /// Injects babble noise / interjections before or between words.
  List<String> applyBabbleNoise(List<String> words, {double noiseProbability = 0.20}) {
    final List<String> result = [];
    for (int i = 0; i < words.length; i++) {
      if (_rnd.nextDouble() < noiseProbability) {
        final babble = _babbleInterjections[_rnd.nextInt(_babbleInterjections.length)];
        result.add(babble);
      }
      result.add(words[i]);
    }
    return result;
  }

  /// Generates completely random Arabic phoneme strings for false positive rejection testing.
  List<String> generateUnrelatedPhonemes(int count) {
    const consonants = [
      'ب', 'ت', 'ث', 'ج', 'ح', 'خ', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', 'ص', 'ض',
      'ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ك', 'ل', 'م', 'ن', 'ه', 'و', 'ي'
    ];
    const vowels = ['َ', 'ُ', 'ِ', 'ْ', ''];
    final List<String> result = [];

    for (int i = 0; i < count; i++) {
      int len = 2 + _rnd.nextInt(4);
      String word = '';
      for (int j = 0; j < len; j++) {
        word += consonants[_rnd.nextInt(consonants.length)];
        word += vowels[_rnd.nextInt(vowels.length)];
      }
      result.add(word);
    }
    return result;
  }
}
