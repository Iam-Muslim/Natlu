import 'dart:typed_data';

/// ────────────────────────────────────────────────────────────────────────────
/// FILE ROLE: Quranic Arabic Articulatory Distance & Phonetic Penalty Matrix
/// ARCHITECTURE: Pre-calculated contiguous memory lookup table (Float64List)
/// RESPONSIBILITY:
/// - Computes mathematically sound acoustic & articulatory distances between
///   Arabic phonemes grounded in classical Tajweed science (Makharij & Sifat).
/// - Accounts for Uthmani script conventions, Madd variants, and Hamza families.
/// - Pre-bakes all distances into an ultra-fast O(1) contiguous Float64List grid.
/// ────────────────────────────────────────────────────────────────────────────

/// Major Organs of Articulation (المخارج العامة)
enum MakhrajMajor {
  jawf, // الجوف (Empty Space: Madd letters)
  halq, // الحلق (Throat)
  lisan, // اللسان (Tongue)
  shafatan, // الشفتان (Lips)
  khayshum, // الخيشوم (Nasal Cavity: Ghunnah)
}

/// Specific Articulation Points (المخارج الخاصة)
enum MakhrajSpecific {
  jawfMadd, // حروف المد (ا، و، ي)
  halqAqsa, // أقصى الحلق (ء، هـ)
  halqWasat, // وسط الحلق (ع، ح)
  halqAdna, // أدنى الحلق (غ، خ)
  lisanAqsaUvular, // أقصى اللسان فوق (ق)
  lisanAqsaVelar, // أقصى اللسان أسفل (ك)
  lisanWasat, // وسط اللسان (ج، ش، ي)
  lisanHafah, // حافة اللسان (ض، ل)
  lisanTarfGums, // طرف اللسان مع اللثة (ن، ر)
  lisanTarfNataiyyah, // طرف اللسان مع أصول الثنايا العليا (ط، د، ت)
  lisanTarfLathaweeyah, // طرف اللسان مع أطراف الثنايا العليا (ظ، ذ، ث)
  lisanTarfAsaliyyah, // طرف اللسان مع صفائح الثنايا السفلى / الصفير (ص، ز، س)
  shafatanLipTeeth, // بطن الشفة السفلى مع أطراف الثنايا (ف)
  shafatanBothClosed, // بين الشفتين بانطباق (ب، م)
  shafatanBothOpen, // بين الشفتين بانضمام (و)
  khayshumGhunnah, // الخيشوم (الغنة)
}

/// Acoustic Attributes (صفات الحروف)
class ArabicPhoneticFeatures {
  final MakhrajMajor major;
  final MakhrajSpecific specific;
  final bool hams; // الهمس (True = Hams/Whisper, False = Jahr/Vocal Vibration)
  final int manner; // 0 = Shiddah (شدة), 1 = Tawassut (توسط), 2 = Rakhawah (رخاوة)
  final bool istila; // الاستعلاء / التفخيم (True = Heavy/Elevated, False = Light)
  final bool itbaq; // الإطباق (True = Compressed against roof, False = Infitah)
  final bool safeer; // الصفير (ص، ز، س)
  final bool qalqalah; // القلقلة (ق، ط، ب، ج، د)
  final bool ghunnah; // الغنة (ن، م)
  final bool inhiraf; // الانحراف (ل، ر)
  final bool takreer; // التكرير (ر)
  final bool tafashshi; // التفشي (ش)
  final bool istitalah; // الاستطالة (ض)

  const ArabicPhoneticFeatures({
    required this.major,
    required this.specific,
    required this.hams,
    required this.manner,
    required this.istila,
    required this.itbaq,
    this.safeer = false,
    this.qalqalah = false,
    this.ghunnah = false,
    this.inhiraf = false,
    this.takreer = false,
    this.tafashshi = false,
    this.istitalah = false,
  });
}

/// ────────────────────────────────────────────────────────────────────────────
/// [SubCostTable] - Tajweed Feature Distance Engine
/// ────────────────────────────────────────────────────────────────────────────
class SubCostTable {
  /// Complete phonetic feature registry for all Arabic consonants & vowels.
  static final Map<String, ArabicPhoneticFeatures> _featureRegistry = {
    // ── الحلق (Throat) ──
    'ء': const ArabicPhoneticFeatures(
      major: MakhrajMajor.halq,
      specific: MakhrajSpecific.halqAqsa,
      hams: false,
      manner: 0,
      istila: false,
      itbaq: false,
    ),
    'ه': const ArabicPhoneticFeatures(
      major: MakhrajMajor.halq,
      specific: MakhrajSpecific.halqAqsa,
      hams: true,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
    'ع': const ArabicPhoneticFeatures(
      major: MakhrajMajor.halq,
      specific: MakhrajSpecific.halqWasat,
      hams: false,
      manner: 1,
      istila: false,
      itbaq: false,
    ),
    'ح': const ArabicPhoneticFeatures(
      major: MakhrajMajor.halq,
      specific: MakhrajSpecific.halqWasat,
      hams: true,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
    'غ': const ArabicPhoneticFeatures(
      major: MakhrajMajor.halq,
      specific: MakhrajSpecific.halqAdna,
      hams: false,
      manner: 2,
      istila: true,
      itbaq: false,
    ),
    'خ': const ArabicPhoneticFeatures(
      major: MakhrajMajor.halq,
      specific: MakhrajSpecific.halqAdna,
      hams: true,
      manner: 2,
      istila: true,
      itbaq: false,
    ),

    // ── اللسان (Tongue) ──
    'ق': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanAqsaUvular,
      hams: false,
      manner: 0,
      istila: true,
      itbaq: false,
      qalqalah: true,
    ),
    'ك': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanAqsaVelar,
      hams: true,
      manner: 0,
      istila: false,
      itbaq: false,
    ),
    'ج': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanWasat,
      hams: false,
      manner: 0,
      istila: false,
      itbaq: false,
      qalqalah: true,
    ),
    'ش': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanWasat,
      hams: true,
      manner: 2,
      istila: false,
      itbaq: false,
      tafashshi: true,
    ),
    'ي': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanWasat,
      hams: false,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
    'ض': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanHafah,
      hams: false,
      manner: 2,
      istila: true,
      itbaq: true,
      istitalah: true,
    ),
    'ل': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanHafah,
      hams: false,
      manner: 1,
      istila: false,
      itbaq: false,
      inhiraf: true,
    ),
    'ن': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfGums,
      hams: false,
      manner: 1,
      istila: false,
      itbaq: false,
      ghunnah: true,
    ),
    'ر': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfGums,
      hams: false,
      manner: 1,
      istila: false,
      itbaq: false,
      inhiraf: true,
      takreer: true,
    ),
    'ط': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfNataiyyah,
      hams: false,
      manner: 0,
      istila: true,
      itbaq: true,
      qalqalah: true,
    ),
    'د': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfNataiyyah,
      hams: false,
      manner: 0,
      istila: false,
      itbaq: false,
      qalqalah: true,
    ),
    'ت': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfNataiyyah,
      hams: true,
      manner: 0,
      istila: false,
      itbaq: false,
    ),
    'ص': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfAsaliyyah,
      hams: true,
      manner: 2,
      istila: true,
      itbaq: true,
      safeer: true,
    ),
    'ز': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfAsaliyyah,
      hams: false,
      manner: 2,
      istila: false,
      itbaq: false,
      safeer: true,
    ),
    'س': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfAsaliyyah,
      hams: true,
      manner: 2,
      istila: false,
      itbaq: false,
      safeer: true,
    ),
    'ظ': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfLathaweeyah,
      hams: false,
      manner: 2,
      istila: true,
      itbaq: true,
    ),
    'ذ': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfLathaweeyah,
      hams: false,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
    'ث': const ArabicPhoneticFeatures(
      major: MakhrajMajor.lisan,
      specific: MakhrajSpecific.lisanTarfLathaweeyah,
      hams: true,
      manner: 2,
      istila: false,
      itbaq: false,
    ),

    // ── الشفتان (Lips) ──
    'ف': const ArabicPhoneticFeatures(
      major: MakhrajMajor.shafatan,
      specific: MakhrajSpecific.shafatanLipTeeth,
      hams: true,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
    'ب': const ArabicPhoneticFeatures(
      major: MakhrajMajor.shafatan,
      specific: MakhrajSpecific.shafatanBothClosed,
      hams: false,
      manner: 0,
      istila: false,
      itbaq: false,
      qalqalah: true,
    ),
    'م': const ArabicPhoneticFeatures(
      major: MakhrajMajor.shafatan,
      specific: MakhrajSpecific.shafatanBothClosed,
      hams: false,
      manner: 1,
      istila: false,
      itbaq: false,
      ghunnah: true,
    ),
    'و': const ArabicPhoneticFeatures(
      major: MakhrajMajor.shafatan,
      specific: MakhrajSpecific.shafatanBothOpen,
      hams: false,
      manner: 2,
      istila: false,
      itbaq: false,
    ),

    // ── الجوف (Empty Space: Madd) ──
    'ا': const ArabicPhoneticFeatures(
      major: MakhrajMajor.jawf,
      specific: MakhrajSpecific.jawfMadd,
      hams: false,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
    'ى': const ArabicPhoneticFeatures(
      major: MakhrajMajor.jawf,
      specific: MakhrajSpecific.jawfMadd,
      hams: false,
      manner: 2,
      istila: false,
      itbaq: false,
    ),
  };

  /// Computes the articulatory feature distance between two base Arabic letters.
  static double computeArticulatoryDistance(String b1, String b2) {
    if (b1 == b2) return 0.0;

    final f1 = _featureRegistry[b1];
    final f2 = _featureRegistry[b2];

    if (f1 == null || f2 == null) {
      return 1.0;
    }

    // 1. Makhraj Distance
    double makhrajDist = 0.0;
    if (f1.specific == f2.specific) {
      makhrajDist = 0.0; // Same specific makhraj (e.g. ط / د / ت or ص / ز / س)
    } else if (f1.major == f2.major) {
      // Same major organ (e.g. tongue tip vs tongue edge, throat middle vs throat deep)
      final int diff = (f1.specific.index - f2.specific.index).abs();
      makhrajDist = diff == 1 ? 0.25 : 0.45;
    } else {
      // Different major organs (e.g. throat vs lips)
      makhrajDist = 1.0;
    }

    // 2. Sifat Distance
    double sifatDist = 0.0;
    if (f1.hams != f2.hams) sifatDist += 0.20; // Hams vs Jahr
    if (f1.manner != f2.manner) {
      sifatDist += (f1.manner - f2.manner).abs() == 1 ? 0.15 : 0.30;
    }
    if (f1.istila != f2.istila) sifatDist += 0.20; // Tafkheem / Isti'la
    if (f1.itbaq != f2.itbaq) sifatDist += 0.15; // Itbaq
    if (f1.safeer != f2.safeer) sifatDist += 0.10;
    if (f1.qalqalah != f2.qalqalah) sifatDist += 0.05;
    if (f1.ghunnah != f2.ghunnah) sifatDist += 0.15;

    // Normalize Sifat distance (max possible sum ~ 1.15)
    final double normSifat = (sifatDist / 1.15).clamp(0.0, 1.0);

    // Weighted combination: 45% Makhraj, 55% Sifat
    final double totalDist = 0.45 * makhrajDist + 0.55 * normSifat;
    return totalDist.clamp(0.0, 1.0);
  }

  /// Calculates the exact float penalty for substituting [c1] (ASR) with [c2] (Reference).
  static double getCost(String c1, String c2) {
    if (c1 == c2) return 0.0;
    if (c1.isEmpty || c2.isEmpty) return 1.0;

    String base1 = c1[0];
    String base2 = c2[0];
    bool sameBase = (base1 == base2);

    bool isOrthographicVariant = false;

    // ── Rule 1: Hamza Equivalence (ا، أ، إ، آ، ء، ؤ، ئ) ──
    const hamzas = ['ا', 'أ', 'إ', 'آ', 'ء', 'ؤ', 'ئ'];
    if (!sameBase && hamzas.contains(base1) && hamzas.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    // ── Rule 2: Ya & Waw Madd Orthography Variants (ي، ى، ۦ / و، ۥ) ──
    const yaFamily = ['ي', 'ى', 'ۦ', 'ۧ'];
    if (!sameBase && yaFamily.contains(base1) && yaFamily.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    const wawFamily = ['و', 'ۥ', 'ۨ'];
    if (!sameBase && wawFamily.contains(base1) && wawFamily.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    // ── Rule 3: Ta-Marbuta & Ha (ة / ه) Waqf Equivalence ──
    if (!sameBase &&
        (base1 == 'ه' || base1 == 'ة') &&
        (base2 == 'ه' || base2 == 'ة')) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    // ── Rule 3.5: Ghunnah/Ikhfa Equivalence (ں / ن / م) ──
    const nasals = ['ں', 'ن', 'م'];
    if (!sameBase && nasals.contains(base1) && nasals.contains(base2)) {
      sameBase = true;
      isOrthographicVariant = true;
    }

    // ── Rule 4: Same Base Character (Evaluate Shaddah / Maddah / Tashkeel) ──
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
          return 0.15; // Madd length tolerance
        }
        return 0.25; // Shaddah length variation
      }

      // Tajweed marker vs Sukoon equivalence
      String c1Strip = c1.replaceAll(RegExp(r'[ڇۜ۾۪]'), 'ْ').replaceAll('ْْ', 'ْ');
      String c2Strip = c2.replaceAll(RegExp(r'[ڇۜ۾۪]'), 'ْ').replaceAll('ْْ', 'ْ');
      if (c1Strip == c2Strip) {
        return 0.10; // Tiny penalty for missing Tajweed marker but preserving the Sukoon
      }

      // Tashkeel mismatch on same base
      return isOrthographicVariant ? 0.25 : 0.45;
    }

    // ── Rule 5: Distinct Base Consonants (Articulatory Distance + Harakat Check) ──
    final double rawArticulatory = computeArticulatoryDistance(base1, base2);

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

    if (!harakatMatch) {
      // Conflicting vowel/tashkeel -> always apply heavy penalty
      return (rawArticulatory + 0.35).clamp(0.45, 1.0);
    }

    // If consonants are close phonetic neighbors (e.g. س/ص, ت/ط, ذ/ظ) with same harakat
    if (rawArticulatory <= 0.35) {
      // Articulatory neighbor + identical vowel
      return (rawArticulatory * 0.8).clamp(0.15, 0.28);
    }

    // Completely dissimilar sounds (e.g. ب vs ش)
    return rawArticulatory >= 0.70 ? 1.0 : rawArticulatory;
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
      // We explicitly DO NOT rebuild the matrix during live tracking here.
      // Unseen noise tokens will just be assigned an ID > _matrixDim and return cost 1.0.
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
