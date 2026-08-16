import 'package:flutter_test/flutter_test.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Trace Surah 5 Ayah 106 and Surah 28 Ayah 4', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    // 1. Test Surah 28: Ayah 4 (Word 53)
    {
      final surahWords = dataLoader.getSurahWords(28);
      final phonemeWords = surahWords.map((w) => w.phoneme).toList();
      final boundaries = dataLoader.calculateBoundaries(phonemeWords);
      final fullPhonemes = phonemeWords.join('');

      harness.setSurahReference(
        surahNumber: 28,
        fullPhonemes: fullPhonemes,
        boundaries: boundaries,
        isTajweed: false,
        forceClear: true,
        startGlobalWord: 0,
      );

      final verses = dataLoader.getSurahVerses(28);
      print('=== TESTING SURAH 28 AYAHS 1 to 6 ===');
      for (int a = 0; a < 6; a++) {
        final verse = verses[a];
        final isAyah6 = (verse.ayah == 6);
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

        if (isAyah6) {
          print('\n=== SURAH 28 AYAH 6 FRAMES ===');
          for (int w = 0; w < verse.phonemeWords.length; w++) {
            print('  W$w: "${verse.phonemeWords[w]}"');
          }
          for (int f = 0; f < configuredFrames.length; f++) {
            final frame = configuredFrames[f];
            print('  [F$f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
            await harness.feedFrames([frame], ayahNumber: verse.ayah);
            for (final log in harness.capture.debugEvents) {
              print('  [F$f] LOG: ${log.message}');
            }
            for (final ev in harness.capture.matchedEvents) {
              print('  [F$f] 🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
            }
            harness.capture.debugEvents.clear();
            harness.capture.matchedEvents.clear();
          }
        } else {
          await harness.feedFrames(configuredFrames, ayahNumber: verse.ayah);
        }
      }
    }
  });
}
