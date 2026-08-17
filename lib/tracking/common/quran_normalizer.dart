// lib/tracking/common/quran_normalizer.dart
//
// Arabic phonetic normalizer and regex-based phoneme chunk tokenizer.
// Shared across Ayah Search, Tajweed error analysis, and Word tracking.

class PhonemeToken {
  final String text;
  final int originalIndex;

  const PhonemeToken(this.text, this.originalIndex);
}

class QuranNormalizer {
  // ── Tashkeel (harakat + shadda + sukun + tanween) ──────────────────────────
  static const String _tashkeelChars =
      '\u064B\u064C\u064D\u064E\u064F\u0650\u0651\u0652\u06EB';

  // ── Alef variants ──────────────────────────────────────────────────────────
  static const String _alefMaksura = '\u0649';
  static const String _alef = '\u0627';
  static const String _smallAlef = '\u0670';
  static const String _hamzatWasl = '\u0671';

  // ── Advanced Tajweed edge cases ───────────────────────────────────────────
  static const String sakt = '\u06E3'; // Small seen above (Sakt)
  static const String ishmam = '\u0658'; // Ishmam sign
  static const String tasheel = '\u065F'; // Tasheel sign
  static const String imala = '\u065E'; // Imala sign

  /// Standard normalization used for matching Arabic phonetic text.
  static String normalize(
    String text, {
    bool removeSpaces = true,
    bool removeTashkeel = true,
    bool ignoreAlefMaksura = true,
    bool removeSmallAlef = true,
    bool normalizeHamzatWasl = true,
  }) {
    String s = text;

    if (removeSpaces) {
      s = s.replaceAll(_whitespaceRegex, '');
    }

    if (ignoreAlefMaksura) {
      s = s.replaceAll(_alefMaksura, _alef);
    }

    if (normalizeHamzatWasl) {
      s = s.replaceAll(_hamzatWasl, _alef);
    }

    if (removeSmallAlef) {
      s = s.replaceAll(_smallAlef, '');
    }

    if (removeTashkeel) {
      s = s.replaceAll(_tashkeelRegex, '');
    }

    return s;
  }

  /// Normalizes structural differences while keeping tashkeel for phoneme comparison.
  static String normalizeWithTashkeel(String word) {
    return normalize(
      word,
      removeSpaces: true,
      removeTashkeel: false,
      ignoreAlefMaksura: true,
      removeSmallAlef: true,
      normalizeHamzatWasl: true,
    );
  }

  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _tashkeelRegex = RegExp('[$_tashkeelChars]');

  // ── Residual characters (harakat, tanween, sukun, etc.) ───────────────────
  static const String _residualsStr =
      r'\u064B\u064C\u064D\u064E\u064F\u0650\u0651\u0652\u06EB\u0686\u065E\u06E3\u0619\u06DC\u06EA\u0640';

  static const Set<int> _residualCodeUnits = {
    0x064B, // fathan
    0x064C, // dammatan
    0x064D, // kasratan
    0x064E, // fatha
    0x064F, // damma
    0x0650, // kasra
    0x0651, // shadda
    0x0652, // sukun
    0x06EB, // tanween idhaam determiner
    0x0686, // qalqalah (small jeem)
    0x065E, // fatha momala (imala)
    0x06E3, // sakt (small seen above)
    0x0619, // dama mokhtalasa
    0x06DC, // sakt marker
    0x06EA, // jazm / special marker
    0x0640, // tatweel (kashida)
  };

  static bool isResidual(String char) {
    if (char.isEmpty) return false;
    return _residualCodeUnits.contains(char.codeUnitAt(0));
  }

  // ── Regex: identical non-residual chars + optional trailing residuals ─────
  static final RegExp _chunkRegex =
      RegExp('(([^$_residualsStr])\\2*[$_residualsStr]*)');

  static List<String> _vocabulary = [];

  /// Initializes the ASR vocabulary for greedy longest-prefix match chunking.
  static void initVocabulary(List<String> tokens) {
    // Sort tokens by length descending for greedy match
    _vocabulary = List<String>.from(tokens)..sort((a, b) => b.length.compareTo(a.length));
  }

  /// Splits a continuous Arabic phonetic string into individual phoneme groups.
  /// Uses Longest-Prefix-Match against the loaded vocabulary if available,
  /// otherwise falls back to the legacy regex behavior.
  static List<String> chunkPhonemes(String phoneticScript) {
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

    // Fallback to legacy regex chunker
    return _chunkRegex
        .allMatches(phoneticScript)
        .map((m) => m.group(1)!)
        .toList();
  }

  /// Same as `chunkPhonemes`, but returns the exact original character index
  /// where this chunk began in `phoneticScript` for O(1) timestamp mapping.
  static List<PhonemeToken> chunkPhonemesWithIndices(String phoneticScript) {
    if (_vocabulary.isNotEmpty) {
      final List<PhonemeToken> chunks = [];
      int i = 0;
      while (i < phoneticScript.length) {
        bool matched = false;
        for (final token in _vocabulary) {
          if (phoneticScript.startsWith(token, i)) {
            chunks.add(PhonemeToken(token, i));
            i += token.length;
            matched = true;
            break;
          }
        }
        if (!matched) {
          chunks.add(PhonemeToken(phoneticScript[i], i));
          i++;
        }
      }
      return chunks;
    }

    return _chunkRegex
        .allMatches(phoneticScript)
        .map((m) => PhonemeToken(m.group(1)!, m.start))
        .toList();
  }
}
