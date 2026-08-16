import 'package:flutter_test/flutter_test.dart';

import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Debug Surah 1 Alignment', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final surahWords = dataLoader.getSurahWords(1);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    print('=== SURAH 1 WORDS (${surahWords.length}) ===');
    for (int i = 0; i < surahWords.length; i++) {
      print('Word $i: Ayah ${surahWords[i].ayah} | Uthmani: "${surahWords[i].uthmani}" | Phoneme: "${surahWords[i].phoneme}"');
    }

    harness.setSurahReference(
      surahNumber: 1,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: 0,
    );

    final frames = AsrChunkSimulator.simulateStreamingAccretion(
      phonemeWords,
      baseTokenDuration: 0.10,
      interWordPause: 0.12,
    );

    print('\n=== FEEDING FRAMES (${frames.length}) ===');
    for (int f = 0; f < frames.length; f++) {
      final frame = frames[f];
      print('\n[FRAME $f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}"');
      await harness.feedFrames([frame]);

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

    print('\n=== FINAL RESULT ===');
    print('Green Words: ${harness.capture.greenWordIds.toList()..sort()}');
    print('Red Words: ${harness.capture.redWordIds.toList()..sort()}');
    print('Total matched: ${harness.capture.greenWordIds.length + harness.capture.redWordIds.length} / ${surahWords.length}');
  });
}
