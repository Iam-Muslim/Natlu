import 'package:flutter_test/flutter_test.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Inspect Word 775 in Surah 2', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final surahWords = dataLoader.getSurahWords(2);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    final w775 = surahWords[775];
    print('Word 775: "${w775.uthmani}" ("${w775.phoneme}") | Ayah: ${w775.ayah} | WordInAyah: ${w775.wordInAyah}');
    
    // Find the ayah containing word 775
    final targetAyah = w775.ayah;
    final verses = dataLoader.getSurahVerses(2);
    
    int startWord = 0;
    for (int a = 0; a < targetAyah - 1; a++) {
      startWord += verses[a].phonemeWords.length;
    }

    harness.setSurahReference(
      surahNumber: 2,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: startWord,
    );

    // Test ayah before, target ayah, and ayah after
    final testVerses = verses.where((v) => v.ayah >= targetAyah - 1 && v.ayah <= targetAyah + 1).toList();

    for (final verse in testVerses) {
      print('\n==================== AYAH ${verse.ayah} (${verse.phonemeWords.length} words) ====================');
      for (int i = 0; i < verse.phonemeWords.length; i++) {
        print('  W$i: "${verse.phonemeWords[i]}"');
      }

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

      for (final log in harness.capture.debugEvents) {
        print('    LOG: ${log.message}');
      }
      harness.capture.debugEvents.clear();
      for (final ev in harness.capture.matchedEvents) {
        print('    🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
      }
      harness.capture.matchedEvents.clear();
    }
  });
}
