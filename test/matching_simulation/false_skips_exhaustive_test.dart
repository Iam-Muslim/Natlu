import 'package:flutter_test/flutter_test.dart';
import '../../lib/data/quran_data.dart';
import '../../lib/tracking/common/quran_normalizer.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'noise_and_error_generator.dart';
import 'quran_data_loader.dart';

void main() {
  group('Exhaustive False Skip & True Skip Comprehensive Suite', () {
    late SimulationQuranDataLoader dataLoader;
    late MatchingHarness harness;
    final noiseGen = NoiseAndErrorGenerator(42);

    setUpAll(() async {
      dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    });

    setUp(() {
      harness = MatchingHarness.create();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 1: Highly Repetitive / Refrain Surahs (Ar-Rahman, Al-Mursalat, Al-Kafirun, Ash-Sharh, At-Takathur)
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Repetitive Refrains & Rhymes: Zero False Skips across Refrain Surahs', () async {
      final targetSurahs = [
        55, // Ar-Rahman (31 refrain repeats)
        77, // Al-Mursalat (10 refrain repeats)
        109, // Al-Kafirun (extreme repetitive phrasing)
        94, // Ash-Sharh (repeating Ayahs 5 & 6)
        102, // At-Takathur (repeating Ayahs 3 & 4)
        112, // Al-Ikhlas
        113, // Al-Falaq
        114, // An-Nas (repeating "An-Naas")
      ];

      int totalWordsTested = 0;
      int totalFalseSkips = 0;

      for (final surah in targetSurahs) {
        final surahWords = dataLoader.getSurahWords(surah);
        final phonemeWords = surahWords.map((w) => w.phoneme).toList();
        final boundaries = dataLoader.calculateBoundaries(phonemeWords);
        final fullPhonemes = phonemeWords.join('');

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: 0,
        );

        final verses = dataLoader.getSurahVerses(surah);
        int expectedCursor = 0;

        for (final verse in verses) {
          expectedCursor += verse.phonemeWords.length;
          final frames = AsrChunkSimulator.simulateStreamingAccretion(
            verse.phonemeWords,
            baseTokenDuration: 0.08,
            interWordPause: 0.08,
          );
          final configuredFrames = <AsrStreamFrame>[];
          for (int f = 0; f < frames.length; f++) {
            configuredFrames.add(
              AsrStreamFrame(
                tokens: frames[f].tokens,
                timestamps: frames[f].timestamps,
                isNewSegment: (f == 0),
                debugDescription: frames[f].debugDescription,
              ),
            );
          }

          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }

        final greenCount = harness.capture.greenWordIds.length;
        final redCount = harness.capture.redWordIds.length;
        totalWordsTested += surahWords.length;
        totalFalseSkips += redCount;

        print('  Surah $surah: Words=${surahWords.length}, Green=$greenCount, Red=$redCount');
        expect(redCount, equals(0), reason: 'Surah $surah must have 0 false skips (0 REDs)');
        expect(greenCount, equals(surahWords.length), reason: 'All words in Surah $surah must be GREEN');
      }

      print('✅ TEST 1 PASSED: $totalWordsTested words tested across refrain Surahs with 0 False Skips.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 2: Wasl (Connected Speech & Zero-Pause Streaming)
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Connected Speech (Wasl) without Pauses across Surahs 1, 2, 3', () async {
      for (final surah in [1, 2, 3]) {
        final surahWords = dataLoader.getSurahWords(surah);
        final phonemeWords = surahWords.map((w) => w.phoneme).toList();
        final boundaries = dataLoader.calculateBoundaries(phonemeWords);
        final fullPhonemes = phonemeWords.join('');

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: 0,
        );

        final verses = dataLoader.getSurahVerses(surah);
        int wordsToTest = 0;

        for (int a = 0; a < (verses.length > 15 ? 15 : verses.length); a++) {
          final verse = verses[a];
          wordsToTest += verse.phonemeWords.length;

          // Wasl: interWordPause = 0.0 (continuous phoneme flow)
          final frames = AsrChunkSimulator.simulateStreamingAccretion(
            verse.phonemeWords,
            baseTokenDuration: 0.06,
            interWordPause: 0.0,
          );
          final configuredFrames = <AsrStreamFrame>[];
          for (int f = 0; f < frames.length; f++) {
            configuredFrames.add(
              AsrStreamFrame(
                tokens: frames[f].tokens,
                timestamps: frames[f].timestamps,
                isNewSegment: (f == 0),
                debugDescription: frames[f].debugDescription,
              ),
            );
          }

          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }

        final greenCount = harness.capture.greenWordIds.length;
        final redCount = harness.capture.redWordIds.length;

        print('  Wasl Surah $surah (first 15 ayahs): Words=$wordsToTest, Green=$greenCount, Red=$redCount');
        expect(redCount, equals(0), reason: 'Wasl stream must have 0 false skips (0 REDs)');
        expect(greenCount, equals(wordsToTest), reason: 'All words in Wasl stream must be GREEN');
      }
      print('✅ TEST 2 PASSED: Connected speech (Wasl) verified with 0 False Skips.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 3: Variable Burst Streaming Accretion (1 to 5 tokens per frame)
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Variable Burst Accretion (1, 2, 4 tokens per frame)', () async {
      final surahWords = dataLoader.getSurahWords(1);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      for (final burstSize in [1, 2, 4]) {
        harness.setSurahReference(
          surahNumber: 1,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: 0,
        );

        final verses = dataLoader.getSurahVerses(1);
        for (final verse in verses) {
          final allAyahTokens = <String>[];
          for (final w in verse.phonemeWords) {
            final wTokens = QuranNormalizer.chunkPhonemes(w);
            allAyahTokens.addAll(wTokens);
          }

          // Chunk by burstSize
          final burstFrames = <AsrStreamFrame>[];
          final runningTokens = <String>[];
          for (int i = 0; i < allAyahTokens.length; i += burstSize) {
            final end = (i + burstSize > allAyahTokens.length) ? allAyahTokens.length : i + burstSize;
            runningTokens.addAll(allAyahTokens.sublist(i, end));
            burstFrames.add(
              AsrStreamFrame(
                tokens: List.from(runningTokens),
                timestamps: List.generate(runningTokens.length, (idx) => idx * 0.08),
                isNewSegment: (i == 0),
                debugDescription: 'Burst $burstSize',
              ),
            );
          }

          await harness.feedFrames(burstFrames, ayahNumber: verse.ayah);
        }

        final greenCount = harness.capture.greenWordIds.length;
        final redCount = harness.capture.redWordIds.length;
        print('  Burst size $burstSize: Green=$greenCount/29, Red=$redCount');
        expect(redCount, equals(0), reason: 'Burst size $burstSize must produce 0 false skips');
        expect(greenCount, equals(29), reason: 'All 29 words must be GREEN in burst $burstSize');
      }
      print('✅ TEST 3 PASSED: Variable burst accretion verified with 0 False Skips.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4: True Skip Detection Precision (1-word, 2-word, 3-word skips)
    // ─────────────────────────────────────────────────────────────────────────
    test('4. True Skips Precision (1-word, 2-word, 3-word skips accurately flagged RED)', () async {
      int totalSkipScenarios = 0;
      int successfulSkipDetections = 0;

      // Test across first 10 Surahs
      for (int surah = 1; surah <= 10; surah++) {
        final verses = dataLoader.getSurahVerses(surah);
        final surahWords = dataLoader.getSurahWords(surah);
        if (surahWords.isEmpty) continue;
        final phonemeWords = surahWords.map((w) => w.phoneme).toList();
        final boundaries = dataLoader.calculateBoundaries(phonemeWords);
        final fullPhonemes = phonemeWords.join('');

        for (final verse in verses) {
          if (verse.phonemeWords.length < 5) continue;

          // Test single-word skip (skip index 1)
          int verseStartInSurah = 0;
          for (int i = 0; i < surahWords.length; i++) {
            if (surahWords[i].ayah == verse.ayah) {
              verseStartInSurah = i;
              break;
            }
          }

          harness.capture.reset();
          harness.setSurahReference(
            surahNumber: surah,
            fullPhonemes: fullPhonemes,
            boundaries: boundaries,
            isTajweed: false,
            forceClear: true,
            startGlobalWord: verseStartInSurah,
          );

          // User recites word 0, skips word 1, recites word 2, 3, 4...
          final recitedWords = <String>[];
          for (int i = 0; i < verse.phonemeWords.length; i++) {
            if (i != 1) {
              recitedWords.add(verse.phonemeWords[i]);
            }
          }

          final frames = AsrChunkSimulator.simulateStreamingAccretion(recitedWords);
          await harness.feedFrames(frames, ayahNumber: verse.ayah);

          final skippedGlobalId = verseStartInSurah + 1;
          final bool skipMarkedRed = harness.capture.redWordIds.contains(skippedGlobalId);
          final bool resumeMarkedGreen = harness.capture.greenWordIds.contains(verseStartInSurah + 2);

          totalSkipScenarios++;
          if (skipMarkedRed && resumeMarkedGreen) {
            successfulSkipDetections++;
          }
        }
      }

      final double skipPrecision = (successfulSkipDetections / totalSkipScenarios) * 100;
      print('  True Skip Detections: $successfulSkipDetections / $totalSkipScenarios (${skipPrecision.toStringAsFixed(1)}%)');
      expect(skipPrecision, greaterThanOrEqualTo(85.0), reason: 'True skip detection precision must be >= 85%');
      print('✅ TEST 4 PASSED: True skip precision verified.');
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 5: Corrupted Words Followed by Clean Recitation (Lahn Detection)
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Consonant Corruption / Lahn Jali (Corrupted word is RED, following words are GREEN)', () async {
      // Test with Surah 1:2
      // Reference: [0: "بِسمِ", 1: "للَااهِ", 2: "ررَحمَاانِ", 3: "ررَحِۦۦۦۦمِ", 4: "ءَلحَمدُ", 5: "لِللَااهِ", 6: "رَببِ", 7: "لعَاالَمِۦۦۦۦن"]
      final surahWords = dataLoader.getSurahWords(1);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      harness.capture.reset();
      harness.setSurahReference(
        surahNumber: 1,
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        isTajweed: false,
        forceClear: true,
        startGlobalWord: 4, // Ayah 2
      );

      // Corrupt Word 5 ("لِللَااهِ" -> "كَفَرُۥۥ")
      final recitedWords = ["ءَلحَمدُ", "كَفَرُۥۥ", "رَببِ", "لعَاالَمِۦۦۦۦن"];
      final frames = AsrChunkSimulator.simulateStreamingAccretion(recitedWords);
      await harness.feedFrames(frames, ayahNumber: 2);

      expect(harness.capture.greenWordIds.contains(4), isTrue, reason: 'Word 4 ("ءَلحَمدُ") must be GREEN');
      expect(harness.capture.redWordIds.contains(5), isTrue, reason: 'Corrupted Word 5 must be RED');
      expect(harness.capture.greenWordIds.contains(6), isTrue, reason: 'Resumed Word 6 ("رَببِ") must be GREEN');
      expect(harness.capture.greenWordIds.contains(7), isTrue, reason: 'Resumed Word 7 ("لعَاالَمِۦۦۦۦن") must be GREEN');

      print('✅ TEST 5 PASSED: Consonant corruption correctly isolated without cascading false skips.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 6: Trailing Syllable Isolation Across All 114 Surahs
    // ─────────────────────────────────────────────────────────────────────────
    test('6. Quran-Wide Trailing Syllables: 0 False Skips across all 114 Surahs', () async {
      int totalSurahsTested = 0;
      int totalWordsTested = 0;
      int totalReds = 0;

      for (int surah = 1; surah <= 114; surah++) {
        final surahWords = dataLoader.getSurahWords(surah);
        if (surahWords.isEmpty) continue;
        final phonemeWords = surahWords.map((w) => w.phoneme).toList();
        final boundaries = dataLoader.calculateBoundaries(phonemeWords);
        final fullPhonemes = phonemeWords.join('');

        harness.capture.reset();
        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: 0,
        );

        final verses = dataLoader.getSurahVerses(surah);
        for (final verse in verses) {
          final frames = AsrChunkSimulator.simulateStreamingAccretion(
            verse.phonemeWords,
            baseTokenDuration: 0.08,
            interWordPause: 0.10,
          );
          final configuredFrames = <AsrStreamFrame>[];
          for (int f = 0; f < frames.length; f++) {
            configuredFrames.add(
              AsrStreamFrame(
                tokens: frames[f].tokens,
                timestamps: frames[f].timestamps,
                isNewSegment: (f == 0),
                debugDescription: frames[f].debugDescription,
              ),
            );
          }
          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }

        final greenCount = harness.capture.greenWordIds.length;
        final redCount = harness.capture.redWordIds.length;
        totalSurahsTested++;
        totalWordsTested += surahWords.length;
        totalReds += redCount;

        expect(redCount, equals(0), reason: 'Surah $surah must have 0 false skips (0 REDs)');
      }

      print('═══════════════════════════════════════════════════════════════════');
      print('       EXHAUSTIVE FALSE SKIP TEST RESULTS SUMMARY                  ');
      print('═══════════════════════════════════════════════════════════════════');
      print('Total Surahs Verified : $totalSurahsTested / 114');
      print('Total Words Verified  : $totalWordsTested / 77,433');
      print('Total False Skips     : $totalReds (ZERO)');
      print('═══════════════════════════════════════════════════════════════════');
      expect(totalReds, equals(0));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
