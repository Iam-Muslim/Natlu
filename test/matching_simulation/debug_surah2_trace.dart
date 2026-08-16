import 'package:flutter_test/flutter_test.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Trace Surah 2 Ayahs 1 to 60', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final surahWords = dataLoader.getSurahWords(2);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    harness.setSurahReference(
      surahNumber: 2,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: 0,
    );

    final verses = dataLoader.getSurahVerses(2);
    int expectedCumulativeWord = 0;

    print('▶ Testing all 286 Ayahs of Surah 2 (${surahWords.length} words)...');
    for (int a = 0; a < verses.length; a++) {
      final verse = verses[a];
      expectedCumulativeWord += verse.phonemeWords.length;

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

      final isAyah149 = (verse.ayah == 149);
      if (isAyah149) {
        print('\n=== AYAH 149 WORDS (${verse.phonemeWords.length}) ===');
        for (int w = 0; w < verse.phonemeWords.length; w++) {
          print('  W$w (Global ${expectedCumulativeWord - verse.phonemeWords.length + w}): "${verse.phonemeWords[w]}"');
        }
        for (int f = 0; f < configuredFrames.length; f++) {
          final frame = configuredFrames[f];
          if (f >= 25 && f <= 45) {
            print('  [F$f] Frame Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
          }
          await harness.feedFrames([frame], ayahNumber: verse.ayah);
          if (f >= 25 && f <= 45) {
            for (final log in harness.capture.debugEvents) {
              print('  [F$f] LOG: ${log.message}');
            }
            for (final ev in harness.capture.matchedEvents) {
              print('  [F$f] 🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
            }
          }
          harness.capture.debugEvents.clear();
          harness.capture.matchedEvents.clear();
        }
      } else {
        await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
      }

      final cursor = harness.sequencer.targetWordCursor;
      final reds = harness.capture.redWordIds;
      final greens = harness.capture.greenWordIds;

      if (cursor != expectedCumulativeWord || reds.isNotEmpty) {
        print('❌ Ayah ${verse.ayah}: ExpectedCursor=$expectedCumulativeWord, ActualCursor=$cursor | Reds=${reds.length} -> $reds');
        for (final ev in harness.capture.matchedEvents) {
          if (ev.isRed) {
            print('   -> Red Word ${ev.wordId}: "${surahWords[ev.wordId].phoneme}"');
          }
        }
        break;
      } else {
        if (verse.ayah % 25 == 0 || verse.ayah == 1 || verse.ayah == verses.length) {
          print('✅ Ayah ${verse.ayah}/${verses.length}: 100% Clean (Cursor=$cursor, Greens=${greens.length}, Reds=0)');
        }
      }
    }

    expect(harness.capture.redWordIds.length, equals(0));
    expect(harness.capture.greenWordIds.length, equals(surahWords.length));
  });
}
