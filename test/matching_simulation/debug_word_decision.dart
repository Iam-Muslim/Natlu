import 'package:flutter_test/flutter_test.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Comprehensive Word Decision Verification (Green vs Red vs Corruption)', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    // We test Surah 1: Verse 2: "ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ"
    // Word 4: "ءَلحَمدُ"
    // Word 5: "لِللَااهِ"
    // Word 6: "رَببِ"
    // Word 7: "لعَاالَمِۦۦۦۦن"
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
      startGlobalWord: 4,
    );

    // 1. Recite Word 4: "ءَلحَمدُ", Word 5 corrupted: "كَفَرُۥۥ", Word 6: "رَببِ", Word 7: "لعَاالَمِۦۦۦۦن"
    final recitedWords = ["ءَلحَمدُ", "كَفَرُۥۥ", "رَببِ", "لعَاالَمِۦۦۦۦن"];
    final frames = AsrChunkSimulator.simulateStreamingAccretion(
      recitedWords,
      baseTokenDuration: 0.10,
      interWordPause: 0.12,
    );

    for (int f = 0; f < frames.length; f++) {
      final frame = frames[f];
      print('  [F$f] Tokens (${frame.tokens.length}): "${frame.tokens.join(' ')}" | Cursor: ${harness.sequencer.targetWordCursor}');
      await harness.feedFrames([frame], ayahNumber: 2);
      for (final log in harness.capture.debugEvents) {
        print('  [F$f] LOG: ${log.message}');
      }
      for (final ev in harness.capture.matchedEvents) {
        print('  [F$f] 🎯 MATCHED Word ${ev.wordId} (Red: ${ev.isRed}) | Asr: "${ev.cleanAsr}"');
      }
      harness.capture.debugEvents.clear();
      harness.capture.matchedEvents.clear();
    }

    print('\n=== WORD DECISION CAPTURED RESULTS ===');
    print('Green Words: ${harness.capture.greenWordIds}');
    print('Red Words: ${harness.capture.redWordIds}');

    // Word 4 must be GREEN
    expect(harness.capture.greenWordIds.contains(4), isTrue, reason: 'Word 4 was recited correctly');
    // Word 5 must be RED (corrupted / skipped)
    expect(harness.capture.redWordIds.contains(5), isTrue, reason: 'Word 5 was corrupted and must be marked RED');
    // Word 6 must be GREEN
    expect(harness.capture.greenWordIds.contains(6), isTrue, reason: 'Word 6 was recited correctly');
    // Word 7 must be GREEN
    expect(harness.capture.greenWordIds.contains(7), isTrue, reason: 'Word 7 was recited correctly');
  });
}
