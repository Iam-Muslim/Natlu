import 'package:flutter_test/flutter_test.dart';

import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Debug Skip Scenario Analysis', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    // Test Surah 1 Verse 2: "ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ" (4 words: 0:ءَلحَمدُ, 1:لِللَااهِ, 2:رَببِ, 3:لعَاالَمِۦۦۦۦن)
    final surahWords = dataLoader.getSurahWords(1);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    harness.setSurahReference(
      surahNumber: 1,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: 4, // Start at Verse 2 (global word 4)
    );

    print('=== REFERENCE WORDS FOR VERSE 2 ===');
    for (int i = 4; i < 8; i++) {
      print('Word $i: "${surahWords[i].uthmani}" -> "${surahWords[i].phoneme}"');
    }

    // Recite: Word 4 ("ءَلحَمدُ"), SKIP Word 5 ("لِللَااهِ"), Recite Word 6 ("رَببِ"), Recite Word 7 ("لعَاالَمِۦۦۦۦن")
    final recitedPhonemes = [
      surahWords[4].phoneme, // "ءَلحَمدُ"
      // Word 5 skipped!
      surahWords[6].phoneme, // "رَببِ"
      surahWords[7].phoneme, // "لعَاالَمِۦۦۦۦن"
    ];

    print('\n=== RECITED WORDS: ${recitedPhonemes} ===');

    final frames = AsrChunkSimulator.simulateStreamingAccretion(
      recitedPhonemes,
      baseTokenDuration: 0.10,
      interWordPause: 0.12,
    );

    for (int f = 0; f < frames.length; f++) {
      final frame = frames[f];
      print('\n[FRAME $f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}"');
      await harness.feedFrames([frame], ayahNumber: 2);

      for (final log in harness.capture.debugEvents) {
        print('  LOG: ${log.message}');
      }
      harness.capture.debugEvents.clear();

      for (final ev in harness.capture.matchedEvents) {
        print('  🎯 MATCHED: Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
      }
      harness.capture.matchedEvents.clear();
      print('  Cursor: ${harness.sequencer.targetWordCursor} | ConsumedTokens: ${harness.sequencer.asrConsumedTokenCount}');
    }

    print('\n=== FINAL CAPTURED RESULT ===');
    print('Green Words: ${harness.capture.greenWordIds.toList()..sort()}');
    print('Red Words: ${harness.capture.redWordIds.toList()..sort()}');
  });
}
