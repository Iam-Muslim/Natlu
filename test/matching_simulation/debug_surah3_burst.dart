import 'package:flutter_test/flutter_test.dart';

import '../../lib/data/quran_data.dart';
import '../../lib/tracking/common/quran_normalizer.dart';
import '../../lib/tracking/word/phoneme_alignment_isolate.dart';
import 'asr_chunk_simulator.dart';
import 'matching_harness.dart';
import 'quran_data_loader.dart';

void main() {
  test('Trace Surah 3 under 3-token burst chunking', () async {
    final dataLoader = await SimulationQuranDataLoader.loadFromProjectRoot('.');
    final harness = MatchingHarness.create();

    final surahWords = dataLoader.getSurahWords(3);
    final phonemeWords = surahWords.map((w) => w.phoneme).toList();
    final boundaries = dataLoader.calculateBoundaries(phonemeWords);
    final fullPhonemes = phonemeWords.join('');

    harness.setSurahReference(
      surahNumber: 3,
      fullPhonemes: fullPhonemes,
      boundaries: boundaries,
      isTajweed: false,
      forceClear: true,
      startGlobalWord: 0,
    );

    final verses = dataLoader.getSurahVerses(3);
    for (final verse in verses) {
      if (verse.ayah == 156) {
        print('\n=== AYAH 156 WORDS (${verse.phonemeWords.length}) ===');
        for (int w = 0; w < verse.phonemeWords.length; w++) {
          print('  W$w (Global ${harness.sequencer.targetWordCursor + w}): "${verse.phonemeWords[w]}"');
        }
      }

      final allTokens = <String>[];
      for (final w in verse.phonemeWords) {
        allTokens.addAll(QuranNormalizer.chunkPhonemes(w));
      }

      final streamFrames = <AsrStreamFrame>[];
      final runningTokens = <String>[];
      int tokenIdx = 0;
      int frameIdx = 0;

      while (tokenIdx < allTokens.length) {
        final end = (tokenIdx + 3 > allTokens.length) ? allTokens.length : tokenIdx + 3;
        runningTokens.addAll(allTokens.sublist(tokenIdx, end));
        tokenIdx = end;

        streamFrames.add(
          AsrStreamFrame(
            tokens: List.from(runningTokens),
            timestamps: List.generate(runningTokens.length, (idx) => idx * 0.08),
            isNewSegment: (frameIdx == 0),
            debugDescription: 'Burst 3 frame $frameIdx',
          ),
        );
        frameIdx++;
      }

      if (verse.ayah == 156) {
        for (int f = 0; f < streamFrames.length; f++) {
          final frame = streamFrames[f];
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
        await harness.feedFrames(streamFrames, ayahNumber: verse.ayah);
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
