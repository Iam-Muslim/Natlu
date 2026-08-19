import 'package:flutter_test/flutter_test.dart';
import 'package:the_great_quran/data/quran_data.dart';
import 'package:the_great_quran/tracking/tajweed/error_explainer.dart';
import 'package:the_great_quran/tracking/tajweed/tajweed_rules.dart';
import 'package:the_great_quran/tracking/word/dictation_matcher.dart';

void main() {
  group('Tajweed Span-Based Evaluation & Timing Tests', () {
    // ── Reference for Surah 1:1 (Al-Fatihah 1:1) ──
    // Word 0: "بِسمِ" (5 chars: indices 0..5)
    // Word 1: "للَااهِ" (7 chars: indices 5..12) - Natural Madd (2 beats) on "اا", Shaddah on "لل"
    // Word 2: "ررَحمَاانِ" (10 chars: indices 12..22) - Natural Madd (2 beats) on "اا", Shaddah on "رر"
    // Word 3: "ررَحِۦۦۦۦم" (10 chars: indices 22..32) - Aared Madd (4 beats) on "ۦۦۦۦ", Shaddah on "رر"
    const String fullPhonemes1_1 = 'بِسمِللَااهِررَحمَاانِررَحِۦۦۦۦم';
    final List<int> boundaries1_1 = [0, 5, 12, 22, 32];

    final List<WordTajweedRule> word2Rules = [
      const WordTajweedRule(
        ruleId: 1,
        nameAr: 'المد الطبيعي',
        nameEn: 'Natural Madd',
        goldenLen: 2,
      ),
      const WordTajweedRule(
        ruleId: 9,
        nameAr: 'الشدة',
        nameEn: 'Shaddah',
        goldenLen: 1,
      ),
    ];

    final List<WordTajweedRule> word3Rules = [
      const WordTajweedRule(
        ruleId: 5,
        nameAr: 'المد العارض للسكون',
        nameEn: 'Aared Madd',
        goldenLen: 4,
      ),
      const WordTajweedRule(
        ruleId: 9,
        nameAr: 'الشدة',
        nameEn: 'Shaddah',
        goldenLen: 1,
      ),
    ];

    test('1. Perfect Recitation of Al-Fatihah 1:1 produces ZERO false errors', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      // Sliced ASR for Word 2 ("ررَحمَاانِ" -> 10 chars)
      const asrWord2 = 'ررَحمَاانِ';
      // Timestamps: "ررَ" has 0.18 + 0.18 + 0.10 = 0.46s (>= 0.35s), "اا" has 0.26 + 0.26 = 0.52s (>= 0.50s)
      final asrTimestamps2 = [0.18, 0.18, 0.10, 0.10, 0.10, 0.10, 0.26, 0.26, 0.10, 0.10];

      final matchResult = matcher.matchWord(
        asrText: asrWord2,
        asrTimestamps: asrTimestamps2,
        fullPhonemes: fullPhonemes1_1,
        refStart: boundaries1_1[2],
        refEnd: boundaries1_1[3],
        config: config,
      );

      expect(matchResult, isNotNull);
      expect(matchResult!.isPartial, isFalse);

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: matchResult.trace,
        fullPhonemes: fullPhonemes1_1,
        wordBoundaries: boundaries1_1,
        currentAsrText: asrWord2,
        trackingTimestamps: asrTimestamps2,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 2,
        nextWordId: 3,
        totalAyahWords: 4,
        expectedWordRules: word2Rules,
      );

      // Must have zero false errors!
      expect(errors, isEmpty, reason: 'Valid recitation should pass without false defects');
    });

    test('2. Shortened Aared Madd produces EXACTLY ONE defect error without duplicates', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      // Sliced ASR for Word 3 ("ررَحِۦۦۦۦم") where reciter shortened the Madd to only 0.25s ("ررَحِۦم")
      const asrWord3 = 'ررَحِۦم';
      final asrTimestamps3 = [0.18, 0.18, 0.10, 0.10, 0.10, 0.25, 0.10]; // only 0.25s on 'ۦ' vs 1.00s required

      final matchResult = matcher.matchWord(
        asrText: asrWord3,
        asrTimestamps: asrTimestamps3,
        fullPhonemes: fullPhonemes1_1,
        refStart: boundaries1_1[3],
        refEnd: boundaries1_1[4],
        config: config,
      );

      expect(matchResult, isNotNull);

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: matchResult!.trace,
        fullPhonemes: fullPhonemes1_1,
        wordBoundaries: boundaries1_1,
        currentAsrText: asrWord3,
        trackingTimestamps: asrTimestamps3,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 3,
        nextWordId: 4,
        totalAyahWords: 4,
        expectedWordRules: word3Rules,
      );

      expect(errors.containsKey(3), isTrue);
      final word3ErrorList = errors[3]!;

      // Verify EXACTLY ONE error for the Madd (NO duplicates!)
      expect(word3ErrorList.length, equals(1));
      final err = word3ErrorList.first;
      expect(err.errorType, equals(ErrorCategory.tajweed));
      expect(err.durationStatus, equals(TajweedDurationStatus.defect));
      expect(err.expectedRule, isA<AaredMaddRule>());
      expect(err.expectedDuration, equals(1.00));
      expect(err.actualDuration, closeTo(0.25, 0.05));
    });

    test('3. Missing Shaddah doubling produces EXACTLY ONE Shaddah defect error', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      // Reciter said "رَحمَاانِ" (single 'رَ' instead of 'ررَ', but Madd "اا" is valid >= 0.50s)
      const asrWord2 = 'رَحمَاانِ';
      final asrTimestamps2 = [0.10, 0.10, 0.10, 0.10, 0.10, 0.26, 0.26, 0.10, 0.10];

      final matchResult = matcher.matchWord(
        asrText: asrWord2,
        asrTimestamps: asrTimestamps2,
        fullPhonemes: fullPhonemes1_1,
        refStart: boundaries1_1[2],
        refEnd: boundaries1_1[3],
        config: config,
      );

      expect(matchResult, isNotNull);

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: matchResult!.trace,
        fullPhonemes: fullPhonemes1_1,
        wordBoundaries: boundaries1_1,
        currentAsrText: asrWord2,
        trackingTimestamps: asrTimestamps2,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 2,
        nextWordId: 3,
        totalAyahWords: 4,
        expectedWordRules: word2Rules,
      );

      expect(errors.containsKey(2), isTrue);
      final word2ErrorList = errors[2]!;

      // Should contain Shaddah defect
      expect(word2ErrorList.length, equals(1));
      final err = word2ErrorList.first;
      expect(err.errorType, equals(ErrorCategory.tajweed));
      expect(err.expectedRule, isA<ShaddahRule>());
    });

    test('4. Mushaddad Ghunnah on "ءِننننَ" evaluates duration and doubling', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      const String fullPhonemes2_6 = 'ءِننننَللَذِۦۦنَ';
      final List<int> boundaries2_6 = [0, 7, 16];

      final List<WordTajweedRule> word0Rules = [
        const WordTajweedRule(
          ruleId: 10,
          nameAr: 'النون المشددة',
          nameEn: 'Mushaddad Noon',
          goldenLen: 2,
        ),
      ];

      // Test 4A: Valid Ghunnah duration (0.50s)
      const validAsr = 'ءِننننَ';
      final validTs = [0.10, 0.10, 0.15, 0.15, 0.10, 0.10, 0.10]; // total nasal ~0.50s

      final validMatch = matcher.matchWord(
        asrText: validAsr,
        asrTimestamps: validTs,
        fullPhonemes: fullPhonemes2_6,
        refStart: boundaries2_6[0],
        refEnd: boundaries2_6[1],
        config: config,
      );

      expect(validMatch, isNotNull);

      final validErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: validMatch!.trace,
        fullPhonemes: fullPhonemes2_6,
        wordBoundaries: boundaries2_6,
        currentAsrText: validAsr,
        trackingTimestamps: validTs,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 2,
        expectedWordRules: word0Rules,
      );

      expect(validErrors, isEmpty, reason: 'Valid 0.50s Ghunnah must pass');

      // Test 4B: Under-held Ghunnah (shortened duration 0.20s vs required 0.50s)
      const shortAsr = 'ءِننننَ';
      final shortTs = [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]; // total duration ~0.20s on nasal

      final shortMatch = matcher.matchWord(
        asrText: shortAsr,
        asrTimestamps: shortTs,
        fullPhonemes: fullPhonemes2_6,
        refStart: boundaries2_6[0],
        refEnd: boundaries2_6[1],
        config: config,
      );

      expect(shortMatch, isNotNull);

      final shortErrors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: shortMatch!.trace,
        fullPhonemes: fullPhonemes2_6,
        wordBoundaries: boundaries2_6,
        currentAsrText: shortAsr,
        trackingTimestamps: shortTs,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 2,
        expectedWordRules: word0Rules,
      );

      expect(shortErrors.containsKey(0), isTrue);
      final err = shortErrors[0]!.first;
      expect(err.errorType, equals(ErrorCategory.tajweed));
      expect(err.durationStatus, equals(TajweedDurationStatus.defect));
      expect(err.expectedRule, isA<MushaddadGhunnahRule>());
      expect(err.expectedDuration, equals(0.50));
    });

    test('5. Wrong Tashkeel diacritic produces Tashkeel error', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      // Reciter said "بِسمُ" (Damma instead of Kasra on Meem)
      const asrWord0 = 'بِسمُ';
      final asrTimestamps0 = [0.10, 0.10, 0.10, 0.10, 0.10];

      final matchResult = matcher.matchWord(
        asrText: asrWord0,
        asrTimestamps: asrTimestamps0,
        fullPhonemes: fullPhonemes1_1,
        refStart: boundaries1_1[0],
        refEnd: boundaries1_1[1],
        config: config,
      );

      expect(matchResult, isNotNull);

      final errors = ErrorExplainer.evaluatePreAlignedWords(
        alignments: matchResult!.trace,
        fullPhonemes: fullPhonemes1_1,
        wordBoundaries: boundaries1_1,
        currentAsrText: asrWord0,
        trackingTimestamps: asrTimestamps0,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 4,
        expectedWordRules: const [],
      );

      expect(errors.containsKey(0), isTrue);
      final err = errors[0]!.first;
      expect(err.errorType, equals(ErrorCategory.tashkeel));
    });

    test('6. Multi-rule evaluation isolates independent defects accurately', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      final List<WordTajweedRule> word1Rules = [
        const WordTajweedRule(
          ruleId: 1,
          nameAr: 'المد الطبيعي',
          nameEn: 'Natural Madd',
          goldenLen: 2,
        ),
        const WordTajweedRule(
          ruleId: 9,
          nameAr: 'الشدة',
          nameEn: 'Shaddah',
          goldenLen: 1,
        ),
      ];

      // Test 6A: Missing Shaddah on "للَااهِ" ("لَااهِ" instead of "للَااهِ") but Madd "اا" is valid (0.50s)
      const asrMissingShaddah = 'لَااهِ';
      final tsMissingShaddah = [0.15, 0.10, 0.25, 0.25, 0.10, 0.10]; // Shaddah missing, Madd 0.50s

      final match6A = matcher.matchWord(
        asrText: asrMissingShaddah,
        asrTimestamps: tsMissingShaddah,
        fullPhonemes: fullPhonemes1_1,
        refStart: boundaries1_1[1],
        refEnd: boundaries1_1[2],
        config: config,
      );

      expect(match6A, isNotNull);

      final errors6A = ErrorExplainer.evaluatePreAlignedWords(
        alignments: match6A!.trace,
        fullPhonemes: fullPhonemes1_1,
        wordBoundaries: boundaries1_1,
        currentAsrText: asrMissingShaddah,
        trackingTimestamps: tsMissingShaddah,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 1,
        nextWordId: 2,
        totalAyahWords: 4,
        expectedWordRules: word1Rules,
      );

      expect(errors6A.containsKey(1), isTrue);
      final list6A = errors6A[1]!;
      expect(list6A.length, equals(1));
      expect(list6A.first.expectedRule, isA<ShaddahRule>());

      // Test 6B: Shaddah "لل" is valid (0.40s) but Madd "اا" is shortened (0.20s)
      const asrShortMadd = 'للَاهِ';
      final tsShortMadd = [0.20, 0.20, 0.10, 0.20, 0.10, 0.10]; // Shaddah 0.40s, Madd only 0.20s

      final match6B = matcher.matchWord(
        asrText: asrShortMadd,
        asrTimestamps: tsShortMadd,
        fullPhonemes: fullPhonemes1_1,
        refStart: boundaries1_1[1],
        refEnd: boundaries1_1[2],
        config: config,
      );

      expect(match6B, isNotNull);

      final errors6B = ErrorExplainer.evaluatePreAlignedWords(
        alignments: match6B!.trace,
        fullPhonemes: fullPhonemes1_1,
        wordBoundaries: boundaries1_1,
        currentAsrText: asrShortMadd,
        trackingTimestamps: tsShortMadd,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 1,
        nextWordId: 2,
        totalAyahWords: 4,
        expectedWordRules: word1Rules,
      );

      expect(errors6B.containsKey(1), isTrue);
      final list6B = errors6B[1]!;
      expect(list6B.length, equals(1));
      expect(list6B.first.expectedRule, isA<NormalMaddRule>());
      expect(list6B.first.durationStatus, equals(TajweedDurationStatus.defect));
    });

    test('7. Lazem Madd (6 beats = 1.50s) on Surah 2:1 "الٓمٓ"', () {
      final matcher = QuranDictationMatcher();
      const config = AlignmentConfig(isTajweedEnabled: true);

      // Surah 2:1: "ءَلِفلَااااااممممِۦۦۦۦۦۦم" (25 chars)
      const String fullPhonemes2_1 = 'ءَلِفلَااااااممممِۦۦۦۦۦۦم';
      final List<int> boundaries2_1 = [0, 25];

      final List<WordTajweedRule> word0Rules = [
        const WordTajweedRule(
          ruleId: 6,
          nameAr: 'المد اللازم',
          nameEn: 'Lazem Madd',
          goldenLen: 6,
        ),
      ];

      // Test 7A: Valid 1.50s Lazem Madd
      const validAsr = 'ءَلِفلَااااااممممِۦۦۦۦۦۦم';
      // Give each 'ا' 0.25s (6 * 0.25 = 1.50s)
      final validTs = List.filled(25, 0.25);

      final match7A = matcher.matchWord(
        asrText: validAsr,
        asrTimestamps: validTs,
        fullPhonemes: fullPhonemes2_1,
        refStart: boundaries2_1[0],
        refEnd: boundaries2_1[1],
        config: config,
      );

      expect(match7A, isNotNull);

      final errors7A = ErrorExplainer.evaluatePreAlignedWords(
        alignments: match7A!.trace,
        fullPhonemes: fullPhonemes2_1,
        wordBoundaries: boundaries2_1,
        currentAsrText: validAsr,
        trackingTimestamps: validTs,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 1,
        expectedWordRules: word0Rules,
      );

      expect(errors7A, isEmpty, reason: 'Valid 1.50s Lazem Madd must pass');

      // Test 7B: Shortened Lazem Madd (only 0.60s on "اااااا")
      const shortAsr = 'ءَلِفلَااااااممممِۦۦۦۦۦۦم';
      final shortTs = List.filled(25, 0.10); // 6 * 0.10 = 0.60s on Madd vs 1.50s required

      final match7B = matcher.matchWord(
        asrText: shortAsr,
        asrTimestamps: shortTs,
        fullPhonemes: fullPhonemes2_1,
        refStart: boundaries2_1[0],
        refEnd: boundaries2_1[1],
        config: config,
      );

      expect(match7B, isNotNull);

      final errors7B = ErrorExplainer.evaluatePreAlignedWords(
        alignments: match7B!.trace,
        fullPhonemes: fullPhonemes2_1,
        wordBoundaries: boundaries2_1,
        currentAsrText: shortAsr,
        trackingTimestamps: shortTs,
        bestAsrStartIdx: 0,
        targetCharCursor: 0,
        startWordId: 0,
        nextWordId: 1,
        totalAyahWords: 1,
        expectedWordRules: word0Rules,
      );

      expect(errors7B.containsKey(0), isTrue);
      final err = errors7B[0]!.first;
      expect(err.errorType, equals(ErrorCategory.tajweed));
      expect(err.expectedRule, isA<LazemMaddRule>());
      expect(err.expectedDuration, equals(1.50));
    });
  });
}
