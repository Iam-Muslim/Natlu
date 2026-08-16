import 'package:flutter_test/flutter_test.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Debug Surah 2 Ayah 148-150 and 164', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final surahWords = dataLoader.getSurahWords(2);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    final verses = dataLoader.getSurahVerses(2);
    final targetVerses = verses.where((v) => v.ayah >= 148 && v.ayah <= 150).toList();
    
    // Find global word index of Ayah 148
    int ayah148WordIdx = 0;
    for (int a = 0; a < 147; a++) {
      ayah148WordIdx += verses[a].phonemeWords.length;
    }

    harness.setSurahReference(
      surahNumber: 2,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: ayah148WordIdx,
    );

    for (final verse in targetVerses) {
      print('\n==================== VERSE ${verse.ayah} (${verse.phonemeWords.length} words) ====================');
      for (int w = 0; w < verse.phonemeWords.length; w++) {
        print('  W$w: "${verse.phonemeWords[w]}"');
      }

      final frames = AsrChunkSimulator.simulateStreamingAccretion(
        verse.phonemeWords,
        baseTokenDuration: 0.08,
        interWordPause: 0.10,
      );

      for (int f = 0; f < frames.length; f++) {
        final frame = frames[f];
        await harness.feedFrames([frame], ayahNumber: verse.ayah);
        
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
    }
  });
}
