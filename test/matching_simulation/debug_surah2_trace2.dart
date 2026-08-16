import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/quran_data.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Trace Surah 2 for 1 false skip', () async {
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
    for (final verse in verses) {
      final isTarget = (verse.ayah == 116);
      if (isTarget) {
        print('\n=== AYAH 116 WORDS (${verse.phonemeWords.length}) ===');
        for (int w = 0; w < verse.phonemeWords.length; w++) {
          print('  W$w (Global ${harness.sequencer.targetWordCursor + w}): "${verse.phonemeWords[w]}"');
        }
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

      if (isTarget) {
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

      if (harness.capture.redWordIds.isNotEmpty) {
        print('❌ Ayah ${verse.ayah} has Reds: ${harness.capture.redWordIds}');
        for (final rId in harness.capture.redWordIds) {
          print('   -> Red Word $rId: "${surahWords[rId].phoneme}" (Ayah ${surahWords[rId].ayah})');
        }
        break;
      }
    }
  });
}
