import 'dart:typed_data';

/// ────────────────────────────────────────────────────────────────────────────
/// FILE ROLE: Quranic Arabic Articulatory Distance & Phonetic Penalty Matrix
/// ARCHITECTURE: Pre-calculated contiguous memory lookup table (Float64List)
/// RESPONSIBILITY:
/// - Computes acoustic & articulatory distances between Arabic phonemes
///   grounded in classical Tajweed science (Makharij & Sifat).
/// - Accounts for Uthmani script conventions, Madd variants, and Hamza families.
/// - Pre-bakes all distances into an ultra-fast O(1) contiguous Float64List grid.
/// ────────────────────────────────────────────────────────────────────────────

/// [SubCostTable] - Phoneme Substitution Cost Table (qua_sdk parity for Uthmani 251 tokens)
class SubCostTable {
  /// Calculates the exact float penalty for substituting [c1] (ASR) with [c2] (Reference).
  static double getCost(String c1, String c2) {
    if (c1 == c2) return 0.0;
    if (c1.isEmpty || c2.isEmpty) return 1.0;

    // ── Rule 0: Special Tajweed Marker Stripping (Qalqalah ڇ, Sakt ۜ, Ikhtilas ؙ, Imala ۪, Iqlab ۾) ──
    final String c1Clean = c1.replaceAll(RegExp(r'[ڇۜ۾ؙ۪]'), '');
    final String c2Clean = c2.replaceAll(RegExp(r'[ڇۜ۾ؙ۪]'), '');
    if (c1Clean == c2Clean && c1Clean.isNotEmpty) {
      return 0.08; // Base consonant and vowel are identical, only Tajweed diacritic marker differs
    }

    String base1 = c1[0];
    String base2 = c2[0];

    bool sameBase = (base1 == base2);
    bool isOrthographicVariant = false;

    // ── Rule 1: Short Vowel vs. Long Madd Vowel Equivalence (qua_sdk vowel_length / vowel_consonant) ──
    // Fatha vs Alif family (َ vs ا, اا, اااا, ٲ, آ)
    const alifFamily = ['ا', 'ٲ', 'آ'];
    if ((c1 == 'َ' && (alifFamily.contains(base2) || c2.contains('ا'))) ||
        (c2 == 'َ' && (alifFamily.contains(base1) || c1.contains('ا')))) {
      return 0.20;
    }

    // Kasra vs Ya / Madd family (ِ vs ي, ۦ, ۦۦ, ۦۦۦۦ)
    const yaMaddFamily = ['ي', 'ى', 'ۦ', 'ۧ'];
    if ((c1 == 'ِ' && (yaMaddFamily.contains(base2) || c2.contains('ي') || c2.contains('ۦ'))) ||
        (c2 == 'ِ' && (yaMaddFamily.contains(base1) || c1.contains('ي') || c1.contains('ۦ')))) {
      return 0.20;
    }

    // Damma vs Waw / Madd family (ُ vs و, ۥ, ۥۥ, ۥۥۥۥ)
    const wawMaddFamily = ['و', 'ۥ', 'ۨ'];
    if ((c1 == 'ُ' && (wawMaddFamily.contains(base2) || c2.contains('و') || c2.contains('ۥ'))) ||
        (c2 == 'ُ' && (wawMaddFamily.contains(base1) || c1.contains('و') || c1.contains('ۥ')))) {
      return 0.20;
    }

    // ── Rule 2: Ta-Marbuta & Ta & Ha Waqf/Wasl Equivalence (ت vs ه vs ة) ──
    const taFamily = ['ت', 'ة'];
    const haFamily = ['ه', 'ة'];
    if ((taFamily.contains(base1) && haFamily.contains(base2)) ||
        (haFamily.contains(base1) && taFamily.contains(base2))) {
      return 0.20;
    }

    // ── Rule 3: Hamza Equivalence (ا، أ، إ، آ، ء، ؤ، ئ، ٲ) ──
    const hamzas = ['ا', 'أ', 'إ', 'آ', 'ء', 'ؤ', 'ئ', 'ٲ'];
    if (!sameBase && hamzas.contains(base1) && hamzas.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    // ── Rule 4: Ya & Waw Madd Orthography Variants (ي، ى، ۦ / و، ۥ) ──
    if (!sameBase && yaMaddFamily.contains(base1) && yaMaddFamily.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    if (!sameBase && wawMaddFamily.contains(base1) && wawMaddFamily.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    // ── Rule 5: Ghunnah/Ikhfa/Iqlab Nasal Family (ں / ن / م / ۾) ──
    const nasals = ['ں', 'ن', 'م', '۾'];
    if (!sameBase && nasals.contains(base1) && nasals.contains(base2)) {
      return 0.25;
    }

    // ── Rule 6: Same Base Character (Evaluate Shaddah / Maddah / Tashkeel) ──
    if (sameBase) {
      if (isOrthographicVariant && c1.length == 1 && c2.length == 1) {
        return 0.15; // Pure orthographic / Madd / Hamza variant
      }

      int base1Code = c1.codeUnitAt(0);
      int count1 = 0;
      for (int i = 0; i < c1.length; i++) {
        if (c1.codeUnitAt(i) == base1Code) count1++;
      }
      int base2Code = c2.codeUnitAt(0);
      int count2 = 0;
      for (int i = 0; i < c2.length; i++) {
        if (c2.codeUnitAt(i) == base2Code) count2++;
      }

      if (count1 != count2) {
        const vowels = ['ا', 'و', 'ي', 'ى', 'ۦ', 'ۥ', '۪', 'ں'];
        if (vowels.contains(base1)) {
          return 0.15; // Madd length tolerance (2 vs 4 vs 6 beats)
        }
        return 0.25; // Shaddah length variation (single vs doubled)
      }

      // Tashkeel mismatch on same base
      return isOrthographicVariant ? 0.25 : 0.35;
    }

    // ── Rule 7: Distinct Base Consonants (qua_sdk sub_costs.json parity) ──
    const emphaticAndNearPairs = {
      'ص': {'س'},
      'س': {'ص', 'ث'},
      'ط': {'ت', 'د'},
      'ت': {'ط', 'د'},
      'د': {'ض', 'ط', 'ت'},
      'ض': {'د', 'ظ'},
      'ظ': {'ذ', 'ض'},
      'ذ': {'ظ', 'ز', 'ث'},
      'ز': {'ذ', 'س'},
      'ث': {'س', 'ذ'},
      'ق': {'ك', 'غ'},
      'ك': {'ق'},
      'غ': {'خ', 'ق'},
      'خ': {'غ', 'ح'},
      'ع': {'ح', 'ء'},
      'ح': {'ع', 'ه', 'خ'},
      'ن': {'ل', 'م'},
      'ل': {'ن', 'ر'},
      'ر': {'ل'},
    };

    final isNearPair = emphaticAndNearPairs[base1]?.contains(base2) ?? false;
    if (!isNearPair) {
      return 1.0; // Completely distinct consonants cost 1.0 (default sub cost)
    }

    bool harakatMatch = false;
    if (c1.length == c2.length) {
      harakatMatch = true;
      for (int i = 1; i < c1.length; i++) {
        if (c1.codeUnitAt(i) != c2.codeUnitAt(i)) {
          harakatMatch = false;
          break;
        }
      }
    }

    // Emphatic / near pair: 0.25 with matching harakat, 0.35 with differing harakat
    return harakatMatch ? 0.25 : 0.35;
  }
}

/// ────────────────────────────────────────────────────────────────────────────
/// [PhonemeMatrix] - High-Performance O(1) 2D Lookup Cache
/// ────────────────────────────────────────────────────────────────────────────
class PhonemeMatrix {
  static final Map<String, int> _phonemeToId = {};
  static int _numPhonemes = 0;
  static int _matrixDim = 0;
  static Float64List _subMatrix = Float64List(0);

  /// Resets the static matrix cache to prevent unbounded memory leaks across sessions.
  static void reset() {
    _phonemeToId.clear();
    _numPhonemes = 0;
    _matrixDim = 0;
    _subMatrix = Float64List(0);
  }

  /// Encodes a phoneme string to a compact integer ID.
  static int encode(String p) {
    if (!_phonemeToId.containsKey(p)) {
      _phonemeToId[p] = _numPhonemes++;
    }
    return _phonemeToId[p]!;
  }

  /// Preheats the matrix with known phonemes to avoid runtime GC/reallocations.
  static void preheat(Iterable<String> tokens) {
    bool needsRebuild = false;
    for (final p in tokens) {
      if (!_phonemeToId.containsKey(p)) {
        _phonemeToId[p] = _numPhonemes++;
        needsRebuild = true;
      }
    }

    if (needsRebuild) {
      _rebuildMatrix();
    }
  }

  static void _rebuildMatrix() {
    _matrixDim = _numPhonemes;
    int size = _matrixDim;
    Float64List newMat = Float64List(size * size);
    newMat.fillRange(0, size * size, 1.0);

    for (int i = 0; i < size; i++) {
      newMat[i * size + i] = 0.0;
    }

    for (var entry1 in _phonemeToId.entries) {
      for (var entry2 in _phonemeToId.entries) {
        int aid = entry1.value;
        int bid = entry2.value;

        if (aid != bid) {
          newMat[aid * size + bid] = SubCostTable.getCost(
            entry1.key,
            entry2.key,
          );
        }
      }
    }

    _subMatrix = newMat;
  }

  /// O(1) instant memory lookup between two phoneme IDs.
  static double getCost(int aid, int bid) {
    if (aid == bid) return 0.0;
    if (aid < _matrixDim && bid < _matrixDim) {
      return _subMatrix[aid * _matrixDim + bid];
    }
    return 1.0;
  }
}
