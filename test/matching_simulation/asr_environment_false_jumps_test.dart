import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/quran_data.dart';
import '../../lib/tracking/common/quran_normalizer.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'noise_and_error_generator.dart';
import 'quran_data_loader.dart';

void main() {
  group('ASR Environment Real-World Streaming & False Jump Exhaustive Suite', () {
    late SimulationQuranDataLoader dataLoader;
    late MatchingHarness harness;
    final random = Random(2026);
    final noiseGen = NoiseAndErrorGenerator(2026);

    setUpAll(() async {
      dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    });

    setUp(() {
      harness = MatchingHarness.create();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 1: ASR Token Jitter & Burst Dynamics (1 to 6 Tokens/Frame)
    // ─────────────────────────────────────────────────────────────────────────
    test('1. ASR Token Jitter & Variable Burst Rates across Surahs 1 to 5', () async {
      print('\n▶ [SCENARIO 1] ASR Token Jitter & Variable Burst Packetization');

      // Test packetization burst sizes: 1 (micro-trickle), 2 (pairs), 3 (syllabic), 5 (fast burst), Random (jitter)
      final burstConfigs = <String, List<int>>{
        'Micro-trickle (1 token)': [1],
        'Pair chunks (2 tokens)': [2],
        'Syllabic chunks (3 tokens)': [3],
        'Fast burst (5 tokens)': [5],
        'Realistic Dynamic Jitter (1-4 tokens)': [1, 2, 3, 4],
      };

      for (final entry in burstConfigs.entries) {
        final configName = entry.key;
        final burstSizes = entry.value;

        int totalWords = 0;
        int totalGreens = 0;
        int totalFalseJumps = 0;

        for (int surah = 1; surah <= 5; surah++) {
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
            // Flatten verse to token stream
            final allTokens = <String>[];
            for (final w in verse.phonemeWords) {
              allTokens.addAll(QuranNormalizer.chunkPhonemes(w));
            }

            final streamFrames = <AsrStreamFrame>[];
            final runningTokens = <String>[];
            int tokenIdx = 0;
            int frameIdx = 0;

            while (tokenIdx < allTokens.length) {
              final currentBurst = burstSizes[random.nextInt(burstSizes.length)];
              final end = min(tokenIdx + currentBurst, allTokens.length);
              runningTokens.addAll(allTokens.sublist(tokenIdx, end));
              tokenIdx = end;

              streamFrames.add(
                AsrStreamFrame(
                  tokens: List.from(runningTokens),
                  timestamps: List.generate(runningTokens.length, (idx) => idx * 0.08),
                  isNewSegment: (frameIdx == 0),
                  debugDescription: '$configName frame $frameIdx',
                ),
              );
              frameIdx++;
            }

            await harness.feedFrames(streamFrames, ayahNumber: verse.ayah);
          }

          final greenCount = harness.capture.greenWordIds.length;
          final redCount = harness.capture.redWordIds.length;
          totalWords += surahWords.length;
          totalGreens += greenCount;
          totalFalseJumps += redCount;

          expect(redCount, equals(0),
              reason: 'Surah $surah under $configName produced $redCount false jumps (expected 0)');
        }

        print('  ✅ $configName: $totalGreens / $totalWords words GREEN (0 False Jumps)');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 2: ASR Madd Variations & Elongations (2, 4, 6 Harakah Nuances)
    // ─────────────────────────────────────────────────────────────────────────
    test('2. ASR Madd Elongation Variations (Shortening & Lengthening)', () async {
      print('\n▶ [SCENARIO 2] ASR Madd Elongation Nuances (2 vs 4 vs 6 Harakah)');

      // Simulate reciter pronouncing Madd Munfasil/Muttasil/Aared with 2, 4, or 6 harakat
      for (int surah = 1; surah <= 10; surah++) {
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
          final List<String> modifiedWords = [];
          for (final word in verse.phonemeWords) {
            String mod = word;
            // Realistic Madd elongation/shortening (Madd 4 -> Madd 2 or Madd 6, Madd 2 -> Madd 4)
            if (mod.contains('اااا')) {
              mod = random.nextBool() ? mod.replaceAll('اااا', 'اا') : mod;
            } else if (mod.contains('ۦۦۦۦ')) {
              mod = random.nextBool() ? mod.replaceAll('ۦۦۦۦ', 'ۦۦ') : mod;
            } else if (mod.contains('ۥۥۥۥ')) {
              mod = random.nextBool() ? mod.replaceAll('ۥۥۥۥ', 'ۥۥ') : mod;
            }
            modifiedWords.add(mod);
          }

          final frames = AsrChunkSimulator.simulateStreamingAccretion(
            modifiedWords,
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
        expect(redCount, equals(0), reason: 'Surah $surah Madd variations produced $redCount false jumps');
        expect(greenCount, equals(surahWords.length));
      }
      print('  ✅ Madd Elongation Variations verified with 0 False Jumps across Surahs 1 to 10');
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 3: ASR Acoustic Encoder Drift (10% Real-World Consonant Shifts)
    // ─────────────────────────────────────────────────────────────────────────
    test('3. ASR Acoustic Encoder Drift (10% Soft Consonant Substitutions)', () async {
      print('\n▶ [SCENARIO 3] ASR Acoustic Encoder Noise & Soft Consonant Drift (10% rate)');

      int totalWords = 0;
      int totalGreens = 0;

      for (int surah = 1; surah <= 15; surah++) {
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
          // Apply 10% acoustic substitutions
          final driftedWords = noiseGen.applyAcousticWeakness(verse.phonemeWords, errorProbability: 0.10);
          final frames = AsrChunkSimulator.simulateStreamingAccretion(
            driftedWords,
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
        totalWords += surahWords.length;
        totalGreens += greenCount;

        // Verify that tracking didn't stall and all words were evaluated (green + red == totalWords)
        expect(greenCount + redCount, equals(surahWords.length),
            reason: 'Surah $surah stalled: evaluated ${greenCount + redCount}/${surahWords.length}');
      }

      print('  ✅ Acoustic Encoder Drift (10%): $totalGreens / $totalWords words GREEN (Tracking 100% resilient)');
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 4: Reciter Stumbles, Repeats & In-Flight Hesitations
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Reciter Stumbles, Repeats & In-Flight Hesitation Debris', () async {
      print('\n▶ [SCENARIO 4] Reciter Stumbles, Immediate Word Repeats & Hesitation Debris');

      for (int surah = 1; surah <= 10; surah++) {
        final verses = dataLoader.getSurahVerses(surah);
        final surahWords = dataLoader.getSurahWords(surah);
        if (surahWords.isEmpty) continue;
        final phonemeWords = surahWords.map((w) => w.phoneme).toList();
        final boundaries = dataLoader.calculateBoundaries(phonemeWords);
        final fullPhonemes = phonemeWords.join('');

        for (final verse in verses) {
          if (verse.phonemeWords.length < 4) continue;

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

          // Reciter repeats word 1 (e.g. "Word 0, Word 1, Word 1, Word 2, Word 3...")
          final repeatedWords = noiseGen.applyWordRepetition(verse.phonemeWords, 1);
          final frames = AsrChunkSimulator.simulateStreamingAccretion(repeatedWords);
          await harness.feedFrames(frames, ayahNumber: verse.ayah);

          final int greenCount = harness.capture.greenWordIds.length;
          final int redCount = harness.capture.redWordIds.length;

          // Word repetition should be cleanly swallowed by the trellis without jumping ahead or marking words RED
          expect(redCount, equals(0),
              reason: 'Surah $surah:${verse.ayah} word repeat caused $redCount false skips');
          expect(greenCount, greaterThanOrEqualTo(verse.phonemeWords.length));
        }
      }

      print('  ✅ Reciter Stumbles & Immediate Word Repeats verified with 0 False Jumps');
    }, timeout: const Timeout(Duration(minutes: 2)));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 5: Full 114-Surah Comprehensive False Jump & Skip Verification
    // ─────────────────────────────────────────────────────────────────────────
    test('5. Full 114-Surah Comprehensive ASR Stream Scan (77,433 Words)', () async {
      print('\n▶ [SCENARIO 5] Full 114-Surah Complete Quran ASR Stream Scan');

      int totalSurahs = 0;
      int totalWords = 0;
      int totalGreens = 0;
      int totalFalseJumps = 0;

      final stopwatch = Stopwatch()..start();

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
        totalSurahs++;
        totalWords += surahWords.length;
        totalGreens += greenCount;
        totalFalseJumps += redCount;

        expect(redCount, equals(0), reason: 'Surah $surah produced $redCount false skips');
        expect(greenCount, equals(surahWords.length));
      }

      stopwatch.stop();

      print('\n═══════════════════════════════════════════════════════════════════');
      print('      FULL 114-SURAH ASR STREAM FALSE JUMP SCAN SUMMARY            ');
      print('═══════════════════════════════════════════════════════════════════');
      print('Total Surahs Verified : $totalSurahs / 114');
      print('Total Words Verified  : $totalWords / 77,433');
      print('Total GREEN Words     : $totalGreens (100.00%)');
      print('Total False Jumps     : $totalFalseJumps (ZERO)');
      print('Execution Time        : ${stopwatch.elapsedMilliseconds / 1000}s');
      print('═══════════════════════════════════════════════════════════════════');

      expect(totalFalseJumps, equals(0));
      expect(totalGreens, equals(77433));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
