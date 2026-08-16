import 'package:flutter_test/flutter_test.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Trace all Ayahs of Surah 7', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final surahWords = dataLoader.getSurahWords(7);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    harness.setSurahReference(
      surahNumber: 7,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: 0,
    );

    final verses = dataLoader.getSurahVerses(7);
    int expectedCursor = 0;

    print('=== TESTING ALL 206 AYAHS OF SURAH 7 ===');
    for (int a = 0; a < verses.length; a++) {
      final verse = verses[a];
      expectedCursor += verse.phonemeWords.length;
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

      if (verse.ayah == 20) {
        print('\n=== AYAH 20 WORDS (${verse.phonemeWords.length}) ===');
        for (int w = 0; w < verse.phonemeWords.length; w++) {
          print('  W$w (Global ${expectedCursor - verse.phonemeWords.length + w}): "${verse.phonemeWords[w]}"');
        }
        for (int f = 0; f < configuredFrames.length; f++) {
          final frame = configuredFrames[f];
          if (f >= 30 && f <= 50) {
            print('  [F$f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
          }
          await harness.feedFrames([frame], ayahNumber: verse.ayah);
          if (f >= 30 && f <= 50) {
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

      if (reds.isNotEmpty || cursor != expectedCursor) {
        print('❌ Ayah ${verse.ayah}: ExpectedCursor=$expectedCursor, ActualCursor=$cursor | Reds=${reds.length} -> $reds');
        for (final ev in harness.capture.matchedEvents) {
          if (ev.isRed) {
            print('   -> Red Word ${ev.wordId}: "${surahWords[ev.wordId].phoneme}"');
          }
        }
        break;
      }
    }
  });
}
