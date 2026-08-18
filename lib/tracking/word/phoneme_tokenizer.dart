// lib/tracking/word/phoneme_tokenizer.dart
//
// Pure, non-modifying tokenizer for Arabic phonetic sequences.
// Slices continuous reference strings into discrete tokens matching `tokens.txt`
// without altering, normalizing, or merging characters.

class PhonemeTokenizer {
  static List<String> _vocabulary = [];

  /// Initializes the vocabulary for greedy longest-prefix match chunking.
  static void initVocabulary(List<String> tokens) {
    // Sort tokens by length descending for greedy longest match
    _vocabulary = List<String>.from(tokens)..sort((a, b) => b.length.compareTo(a.length));
  }

  /// Splits a continuous phonetic string into exact tokens matching the vocabulary.
  /// No characters are modified, removed, or normalized.
  static List<String> tokenize(String phoneticScript) {
    if (phoneticScript.isEmpty) return const [];

    if (_vocabulary.isNotEmpty) {
      final List<String> chunks = [];
      int i = 0;
      while (i < phoneticScript.length) {
        bool matched = false;
        for (final token in _vocabulary) {
          if (phoneticScript.startsWith(token, i)) {
            chunks.add(token);
            i += token.length;
            matched = true;
            break;
          }
        }
        if (!matched) {
          chunks.add(phoneticScript[i]);
          i++;
        }
      }
      return chunks;
    }

    // Direct character-by-character fallback if vocabulary is not yet initialized
    return phoneticScript.split('');
  }
}
