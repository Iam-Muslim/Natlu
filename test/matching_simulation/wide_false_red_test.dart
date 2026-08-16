import 'package:flutter_test/flutter_test.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Wide 114-Surah Comprehensive Zero-False-Red Verification', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    int totalWordsTested = 0;
    int totalGreenWords = 0;
    int totalRedWords = 0;
    final List<String> falseRedReports = [];

    final stopwatch = Stopwatch()..start();

    print('═══════════════════════════════════════════════════════════════════');
    print('   STARTING WIDE 114-SURAH ZERO-FALSE-RED COMPREHENSIVE SUITE     ');
    print('═══════════════════════════════════════════════════════════════════');

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
      final int surahTotal = surahWords.length;

      totalWordsTested += surahTotal;
      totalGreenWords += greenCount;
      totalRedWords += redCount;

      if (redCount > 0) {
        final redIds = harness.capture.redWordIds.toList()..sort();
        for (final rId in redIds) {
          final word = (rId < surahWords.length) ? surahWords[rId] : null;
          falseRedReports.add(
            'Surah $surah (Word $rId): Ref="${word?.phoneme ?? '?'}" | Ayah=${word?.ayah ?? '?'}'
          );
        }
        print('  ❌ Surah $surah/114: $greenCount/$surahTotal Green, $redCount RED -> IDs: $redIds');
      } else {
        if (surah % 10 == 0 || surah == 1 || surah == 114) {
          print('  ✅ Surah $surah/114: 100% Clean ($greenCount/$surahTotal Green, 0 Red)');
        }
      }
    }

    stopwatch.stop();

    print('\n═══════════════════════════════════════════════════════════════════');
    print('                      WIDE TEST RESULTS SUMMARY                    ');
    print('═══════════════════════════════════════════════════════════════════');
    print('Total Surahs Tested     : 114');
    print('Total Words Tested      : $totalWordsTested');
    print('Total Green Words       : $totalGreenWords (${((totalGreenWords / totalWordsTested) * 100).toStringAsFixed(2)}%)');
    print('Total False Reds        : $totalRedWords');
    print('Execution Time          : ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');

    if (falseRedReports.isNotEmpty) {
      print('\nTop False Red Discrepancies (first 20):');
      for (int i = 0; i < falseRedReports.length && i < 20; i++) {
        print('  • ${falseRedReports[i]}');
      }
    }

    expect(totalRedWords, equals(0), reason: 'Expected ZERO False Reds across all 114 Surahs');
    expect(totalGreenWords, equals(totalWordsTested), reason: 'Expected all words to be matched GREEN');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
