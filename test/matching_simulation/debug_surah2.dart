import 'package:flutter_test/flutter_test.dart';

import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Debug Surah 2 Per-Ayah Streaming', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final verses = dataLoader.getSurahVerses(2);
    final surahWords = dataLoader.getSurahWords(2);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    print('Surah 2 has ${verses.length} verses and ${surahWords.length} words.');

    harness.setSurahReference(
      surahNumber: 2,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: 0,
    );

    // Test first 10 verses of Surah 2
    for (int a = 0; a < 10; a++) {
      final verse = verses[a];
      print('\n==================== VERSE ${verse.ayah} (${verse.phonemeWords.length} words) ====================');
      for (int w = 0; w < verse.phonemeWords.length; w++) {
        print('  V${verse.ayah} W$w: "${verse.uthmaniWords[w]}" -> "${verse.phonemeWords[w]}"');
      }

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

        for (final log in harness.capture.debugEvents) {
          print('    LOG: ${log.message}');
        }
        harness.capture.debugEvents.clear();

        for (final ev in harness.capture.matchedEvents) {
          print('    🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
        }
        harness.capture.matchedEvents.clear();
      }
      print('Cursor after Verse ${verse.ayah}: ${harness.sequencer.targetWordCursor}');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    int totalTestedWords = 0;
    for (int a = 0; a < 10; a++) {
      totalTestedWords += verses[a].phonemeWords.length;
    }

    print('\n=== FINAL VERIFICATION ===');
    print('Matched Green: ${harness.capture.greenWordIds.length} / $totalTestedWords');
    print('Matched Red: ${harness.capture.redWordIds.length} -> IDs: ${harness.capture.redWordIds}');
    expect(harness.capture.greenWordIds.length, equals(totalTestedWords));
    expect(harness.capture.redWordIds.length, equals(0));
  });
}
