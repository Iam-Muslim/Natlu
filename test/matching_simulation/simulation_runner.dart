import 'dart:io';

import '../../lib/data/quran_data.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'noise_and_error_generator.dart';
import 'quran_data_loader.dart';
import 'test_reporter.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Quran Matching System Exhaustive Simulation Suite', () async {
    print('================================================================================');
    print('       STARTING COMPREHENSIVE QURAN MATCHING SYSTEM STRESS-TEST SUITE           ');
    print('================================================================================');

  final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
  final reporter = TestReporter();
  final noiseGen = NoiseAndErrorGenerator(1337);
  final harness = MatchingHarness.create();

  print('Loaded Quran Data. Beginning 8-Scenario Exhaustive Testing across all 114 Surahs...\n');

  try {
    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 1: Clean Streaming Recitation (All 114 Surahs, All 6,236 Ayahs)
    // ─────────────────────────────────────────────────────────────────────────
    print('▶ Running SCENARIO 1: Clean Streaming Recitation (All 114 Surahs)...');
    for (int surah = 1; surah <= 114; surah++) {
      final surahWords = dataLoader.getSurahWords(surah);
      if (surahWords.isEmpty) continue;

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
      final sw = Stopwatch()..start();

      for (final verse in verses) {
        final frames = AsrChunkSimulator.simulateStreamingAccretion(
          verse.phonemeWords,
          baseTokenDuration: 0.10,
          interWordPause: 0.12,
        );

        for (int f = 0; f < frames.length; f++) {
          final frame = frames[f];
          final isNew = (f == 0);
          harness.sequencer.syncStream(
            SyncStreamCommand(
              asrTokens: frame.tokens,
              timestamps: frame.timestamps,
              isNewSegment: isNew,
              ayahNumber: verse.ayah,
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      sw.stop();

      final int greenCount = harness.capture.greenWordIds.length;
      final int redCount = harness.capture.redWordIds.length;
      final int expectedCount = surahWords.length;
      final int missedWords = expectedCount - (greenCount + redCount);

      final bool success = greenCount == expectedCount && redCount == 0 && missedWords == 0;

      final List<WordMatchDetail> wordDetails = [];
      for (int w = 0; w < surahWords.length; w++) {
        final isGreen = harness.capture.greenWordIds.contains(w);
        final isRed = harness.capture.redWordIds.contains(w);
        wordDetails.add(
          WordMatchDetail(
            wordId: w,
            uthmani: surahWords[w].uthmani,
            phoneme: surahWords[w].phoneme,
            isGreen: isGreen,
            isRed: isRed,
            asrChunk: isGreen ? surahWords[w].phoneme : '',
            score: isGreen ? 0.0 : 1.0,
            threshold: 0.45,
            coverage: isGreen ? 1.0 : 0.0,
          ),
        );
      }

      final errorLogs = harness.capture.debugEvents.map((e) => e.message).toList();
      harness.capture.debugEvents.clear();

      reporter.recordResult(
        TestScenarioResult(
          scenarioName: 'Clean Streaming',
          surah: surah,
          ayah: 0,
          totalWordsExpected: expectedCount,
          wordsRecited: expectedCount,
          greenWords: greenCount,
          redWords: redCount,
          falseGreens: 0,
          falseReds: redCount,
          stalled: missedWords > 0,
          details: 'Surah $surah: Matched $greenCount/$expectedCount (Reds: $redCount, Missed: $missedWords)',
          elapsedMs: sw.elapsedMilliseconds.toDouble(),
          wordDetails: success ? [] : wordDetails,
          errorLogs: success ? [] : errorLogs,
        ),
      );

      if (surah % 15 == 0 || surah == 114 || !success) {
        final status = success ? '✅ PASS' : '❌ FAIL';
        print('  Surah $surah/114 [Words: $expectedCount | Matched: $greenCount] -> $status (${sw.elapsedMilliseconds}ms)');
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 2: Single-Word Skips Across the Quran
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 2: Single-Word Skips Across Surahs...');
    for (int surah = 1; surah <= 114; surah++) {
      final verses = dataLoader.getSurahVerses(surah);
      final surahWords = dataLoader.getSurahWords(surah);
      if (surahWords.isEmpty) continue;
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      for (final verse in verses) {
        if (verse.phonemeWords.length < 3) continue; // need at least 3 words to test skip
        final skipWordIdx = 1; // skip word 1 in ayah

        // Find local index of this verse inside current surah
        int verseStartInSurah = 0;
        for (int i = 0; i < surahWords.length; i++) {
          if (surahWords[i].ayah == verse.ayah) {
            verseStartInSurah = i;
            break;
          }
        }

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: verseStartInSurah,
        );

        final List<String> recitedWords = [];
        for (int i = 0; i < verse.phonemeWords.length; i++) {
          if (i != skipWordIdx) {
            recitedWords.add(verse.phonemeWords[i]);
          }
        }

        final frames = AsrChunkSimulator.simulateStreamingAccretion(recitedWords);
        final sw = Stopwatch()..start();
        await harness.feedFrames(frames, ayahNumber: verse.ayah);
        sw.stop();

        final skippedLocalIdx = verseStartInSurah + skipWordIdx;
        final bool skipIsRed = harness.capture.redWordIds.contains(skippedLocalIdx);
        final bool othersAreGreen = harness.capture.greenWordIds.contains(verseStartInSurah) &&
            harness.capture.greenWordIds.contains(verseStartInSurah + 2);

        final bool success = skipIsRed && othersAreGreen;

        reporter.recordResult(
          TestScenarioResult(
            scenarioName: 'Single-Word Skip',
            surah: surah,
            ayah: verse.ayah,
            totalWordsExpected: verse.phonemeWords.length,
            wordsRecited: recitedWords.length,
            greenWords: harness.capture.greenWordIds.length,
            redWords: harness.capture.redWordIds.length,
            falseGreens: harness.capture.greenWordIds.contains(skippedLocalIdx) ? 1 : 0,
            falseReds: skipIsRed ? 0 : 1,
            stalled: false,
            details: 'Surah $surah:${verse.ayah} Skipped word $skipWordIdx (Red: $skipIsRed, Others Green: $othersAreGreen)',
            elapsedMs: sw.elapsedMilliseconds.toDouble(),
          ),
        );
      }
      if (surah % 20 == 0 || surah == 114) {
        print('  Tested skips through Surah $surah/114');
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 3: Multi-Word Skips / Large Jumps
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 3: Multi-Word Skips (Jumping 2-3 words ahead)...');
    for (int surah = 1; surah <= 50; surah++) {
      final verses = dataLoader.getSurahVerses(surah);
      final surahWords = dataLoader.getSurahWords(surah);
      if (surahWords.isEmpty) continue;
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      for (final verse in verses) {
        if (verse.phonemeWords.length < 6) continue;

        final Set<int> wordsToSkip = {1, 2}; // skip 2 consecutive words

        int verseStartInSurah = 0;
        for (int i = 0; i < surahWords.length; i++) {
          if (surahWords[i].ayah == verse.ayah) {
            verseStartInSurah = i;
            break;
          }
        }

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: verseStartInSurah,
        );

        final recitedWords = noiseGen.applyWordSkips(verse.phonemeWords, wordsToSkip);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(recitedWords);
        final sw = Stopwatch()..start();
        await harness.feedFrames(frames, ayahNumber: verse.ayah);
        sw.stop();

        final bool jumpWordGreen = harness.capture.greenWordIds.contains(verseStartInSurah + 3);
        final bool skippedAreRed = harness.capture.redWordIds.contains(verseStartInSurah + 1) &&
            harness.capture.redWordIds.contains(verseStartInSurah + 2);

        reporter.recordResult(
          TestScenarioResult(
            scenarioName: 'Multi-Word Skip',
            surah: surah,
            ayah: verse.ayah,
            totalWordsExpected: verse.phonemeWords.length,
            wordsRecited: recitedWords.length,
            greenWords: harness.capture.greenWordIds.length,
            redWords: harness.capture.redWordIds.length,
            falseGreens: 0,
            falseReds: skippedAreRed ? 0 : 1,
            stalled: !jumpWordGreen,
            details: 'Surah $surah:${verse.ayah} Skipped {1, 2} (Jumped to 3 Green=$jumpWordGreen, Reds=$skippedAreRed)',
            elapsedMs: sw.elapsedMilliseconds.toDouble(),
          ),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 4: Stumble & Self-Correction (Repeating Words)
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 4: Stumble & Self-Correction (Word Repetitions)...');
    for (int surah = 1; surah <= 30; surah++) {
      final verses = dataLoader.getSurahVerses(surah);
      final surahWords = dataLoader.getSurahWords(surah);
      if (surahWords.isEmpty) continue;
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      for (final verse in verses) {
        if (verse.phonemeWords.length < 3) continue;

        int verseStartInSurah = 0;
        for (int i = 0; i < surahWords.length; i++) {
          if (surahWords[i].ayah == verse.ayah) {
            verseStartInSurah = i;
            break;
          }
        }

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: verseStartInSurah,
        );

        // Repeat word 1 (reciter repeats the word)
        final recitedWords = noiseGen.applyWordRepetition(verse.phonemeWords, 1);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(recitedWords);
        final sw = Stopwatch()..start();
        await harness.feedFrames(frames, ayahNumber: verse.ayah);
        sw.stop();

        final int greenCount = harness.capture.greenWordIds.length;
        final bool success = greenCount >= verse.phonemeWords.length;

        reporter.recordResult(
          TestScenarioResult(
            scenarioName: 'Stumble & Repetition',
            surah: surah,
            ayah: verse.ayah,
            totalWordsExpected: verse.phonemeWords.length,
            wordsRecited: recitedWords.length,
            greenWords: greenCount,
            redWords: harness.capture.redWordIds.length,
            falseGreens: 0,
            falseReds: 0,
            stalled: !success,
            details: 'Surah $surah:${verse.ayah} Repeated word 1 -> Matched $greenCount/${verse.phonemeWords.length}',
            elapsedMs: sw.elapsedMilliseconds.toDouble(),
          ),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 5: 15% Acoustic Drift & Near-Articulatory Substitutions
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 5: Acoustic Drift & Articulatory Weakness (15% Error Rate)...');
    for (int surah = 1; surah <= 40; surah++) {
      final verses = dataLoader.getSurahVerses(surah);
      final surahWords = dataLoader.getSurahWords(surah);
      if (surahWords.isEmpty) continue;
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      for (final verse in verses) {
        if (verse.phonemeWords.isEmpty) continue;

        int verseStartInSurah = 0;
        for (int i = 0; i < surahWords.length; i++) {
          if (surahWords[i].ayah == verse.ayah) {
            verseStartInSurah = i;
            break;
          }
        }

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: verseStartInSurah,
        );

        final corruptedWords = noiseGen.applyAcousticWeakness(verse.phonemeWords, errorProbability: 0.15);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(corruptedWords);
        final sw = Stopwatch()..start();
        await harness.feedFrames(frames, ayahNumber: verse.ayah);
        sw.stop();

        final int greens = harness.capture.greenWordIds.length;
        final double matchRatio = verse.phonemeWords.isNotEmpty ? (greens / verse.phonemeWords.length) : 1.0;
        final bool acceptable = matchRatio >= 0.70;

        reporter.recordResult(
          TestScenarioResult(
            scenarioName: 'Acoustic Drift',
            surah: surah,
            ayah: verse.ayah,
            totalWordsExpected: verse.phonemeWords.length,
            wordsRecited: corruptedWords.length,
            greenWords: greens,
            redWords: harness.capture.redWordIds.length,
            falseGreens: 0,
            falseReds: acceptable ? 0 : 1,
            stalled: !acceptable,
            details: 'Surah $surah:${verse.ayah} Drift Matched $greens/${verse.phonemeWords.length} (${(matchRatio * 100).toInt()}%)',
            elapsedMs: sw.elapsedMilliseconds.toDouble(),
          ),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 6: Babble Noise & Foreign Interjection Rejection
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 6: Foreign Babble & Cough Interjections...');
    for (int surah = 1; surah <= 30; surah++) {
      final verses = dataLoader.getSurahVerses(surah);
      final surahWords = dataLoader.getSurahWords(surah);
      if (surahWords.isEmpty) continue;
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      for (final verse in verses) {
        int verseStartInSurah = 0;
        for (int i = 0; i < surahWords.length; i++) {
          if (surahWords[i].ayah == verse.ayah) {
            verseStartInSurah = i;
            break;
          }
        }

        harness.setSurahReference(
          surahNumber: surah,
          fullPhonemes: fullPhonemes,
          boundaries: boundaries,
          isTajweed: false,
          forceClear: true,
          startGlobalWord: verseStartInSurah,
        );

        final babbleWords = noiseGen.applyBabbleNoise(verse.phonemeWords, noiseProbability: 0.25);
        final frames = AsrChunkSimulator.simulateStreamingAccretion(babbleWords);
        final sw = Stopwatch()..start();
        await harness.feedFrames(frames, ayahNumber: verse.ayah);
        sw.stop();

        final int greens = harness.capture.greenWordIds.length;
        final bool success = greens >= (verse.phonemeWords.length * 0.60);

        reporter.recordResult(
          TestScenarioResult(
            scenarioName: 'Babble Interjection',
            surah: surah,
            ayah: verse.ayah,
            totalWordsExpected: verse.phonemeWords.length,
            wordsRecited: babbleWords.length,
            greenWords: greens,
            redWords: harness.capture.redWordIds.length,
            falseGreens: 0,
            falseReds: success ? 0 : 1,
            stalled: !success,
            details: 'Surah $surah:${verse.ayah} Babble Matched $greens/${verse.phonemeWords.length}',
            elapsedMs: sw.elapsedMilliseconds.toDouble(),
          ),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 7: False Positive Stress Test (Gibberish Rejection)
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 7: Adversarial Gibberish Rejection...');
    for (int surah = 1; surah <= 20; surah++) {
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

      final gibberish = noiseGen.generateUnrelatedPhonemes(15);
      final frames = AsrChunkSimulator.simulateStreamingAccretion(gibberish);
      final sw = Stopwatch()..start();
      await harness.feedFrames(frames, ayahNumber: 1);
      sw.stop();

      final int falseGreens = harness.capture.greenWordIds.length;
      final bool success = falseGreens == 0;

      reporter.recordResult(
        TestScenarioResult(
          scenarioName: 'False Positive Rejection',
          surah: surah,
          ayah: 1,
          totalWordsExpected: surahWords.length,
          wordsRecited: gibberish.length,
          greenWords: falseGreens,
          redWords: harness.capture.redWordIds.length,
          falseGreens: falseGreens,
          falseReds: 0,
          stalled: false,
          details: 'Surah $surah Gibberish False Greens: $falseGreens (Expected: 0)',
          elapsedMs: sw.elapsedMilliseconds.toDouble(),
        ),
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 8: Tajweed Duration Checking Stress Test
    // ─────────────────────────────────────────────────────────────────────────
    print('\n▶ Running SCENARIO 8: Tajweed Duration Checking...');
    for (int surah = 1; surah <= 10; surah++) {
      final surahWords = dataLoader.getSurahWords(surah);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      harness.setSurahReference(
        surahNumber: surah,
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        isTajweed: true, // Tajweed ON!
        forceClear: true,
        startGlobalWord: 0,
      );

      // Feed with valid Harakat durations (0.25s per beat)
      final frames = AsrChunkSimulator.simulateStreamingAccretion(
        phonemeWords,
        baseTokenDuration: 0.25,
        interWordPause: 0.20,
      );
      final sw = Stopwatch()..start();
      await harness.feedFrames(frames, ayahNumber: 1);
      sw.stop();

      final int greenCount = harness.capture.greenWordIds.length;
      final int errorsCount = harness.capture.wordTajweedErrors.length;

      reporter.recordResult(
        TestScenarioResult(
          scenarioName: 'Tajweed Duration Check',
          surah: surah,
          ayah: 0,
          totalWordsExpected: surahWords.length,
          wordsRecited: surahWords.length,
          greenWords: greenCount,
          redWords: harness.capture.redWordIds.length,
          falseGreens: 0,
          falseReds: 0,
          stalled: false,
          details: 'Surah $surah Tajweed ON: Matched $greenCount words, Detected Errors in $errorsCount words',
          elapsedMs: sw.elapsedMilliseconds.toDouble(),
        ),
      );
    }

  } catch (e, stack) {
    print('CRITICAL RUNNER EXCEPTION: $e\n$stack');
  } finally {
    harness.dispose();
    await reporter.flushToDisk();
    reporter.printSummary();
  }
  }, timeout: const Timeout(Duration(hours: 2)));
}

