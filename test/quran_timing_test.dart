import 'package:flutter_test/flutter_test.dart';
import 'package:the_great_quran/services/quran_timing_service.dart';

void main() {
  group('QuranTimingService & Model Verification', () {
    test('SurahTiming binary search conforms to author specs', () {
      final words = [
        const WordTiming(ayah: 1, wordIndex: 0, startMs: 1000, endMs: 2000, text: 'بِسۡمِ', occurrence: 1),
        const WordTiming(ayah: 1, wordIndex: 1, startMs: 2200, endMs: 3000, text: 'ٱللَّهِ', occurrence: 1),
        const WordTiming(ayah: 1, wordIndex: 2, startMs: 3200, endMs: 4500, text: 'ٱلرَّحۡمَٰنِ', occurrence: 1),
        const WordTiming(ayah: 2, wordIndex: 0, startMs: 5000, endMs: 6000, text: 'ٱلۡحَمۡدُ', occurrence: 1),
      ];

      final timing = SurahTiming(
        surah: 1,
        words: words,
        ayahs: {
          1: AyahTiming(surah: 1, ayah: 1, ayahStartMs: 1000, ayahEndMs: 4500, words: words.sublist(0, 3)),
          2: AyahTiming(surah: 1, ayah: 2, ayahStartMs: 5000, ayahEndMs: 6000, words: words.sublist(3)),
        },
      );

      // 1. Before first word: null
      expect(timing.findActiveWordAtMs(500), isNull);

      // 2. Exact word 0 active: matches
      final w0 = timing.findActiveWordAtMs(1500);
      expect(w0, isNotNull);
      expect(w0!.wordIndex, 0);
      expect(w0.text, 'بِسۡمِ');

      // 3. Pause between word 0 and word 1 (2000ms - 2200ms): MUST return null ("A pause between words has no entry")
      expect(timing.findActiveWordAtMs(2100), isNull);

      // 4. Exact word 1 active: matches
      final w1 = timing.findActiveWordAtMs(2500);
      expect(w1, isNotNull);
      expect(w1!.wordIndex, 1);

      // 5. Ayah 2 word 0 active: matches Ayah 2
      final wAyah2 = timing.findActiveWordAtMs(5500);
      expect(wAyah2, isNotNull);
      expect(wAyah2!.ayah, 2);
      expect(wAyah2.wordIndex, 0);

      // 6. After last word: null
      expect(timing.findActiveWordAtMs(7000), isNull);
    });

    test('Repeated word occurrences are preserved and matched chronologically', () {
      final words = [
        const WordTiming(ayah: 4, wordIndex: 9, startMs: 26225, endMs: 27345, text: 'رِّجَالٗا', occurrence: 1),
        const WordTiming(ayah: 4, wordIndex: 10, startMs: 28000, endMs: 30000, text: 'كَثِيرٗا', occurrence: 1),
        const WordTiming(ayah: 4, wordIndex: 9, startMs: 33033, endMs: 34425, text: 'رِّجَالٗا', occurrence: 2),
      ];

      final timing = SurahTiming(
        surah: 4,
        words: words,
        ayahs: {
          1: AyahTiming(surah: 4, ayah: 1, ayahStartMs: 26225, ayahEndMs: 34425, words: words),
        },
      );

      // First occurrence
      final occ1 = timing.findActiveWordAtMs(26500);
      expect(occ1, isNotNull);
      expect(occ1!.wordIndex, 9);
      expect(occ1.occurrence, 1);

      // Middle word
      final mid = timing.findActiveWordAtMs(29000);
      expect(mid, isNotNull);
      expect(mid!.wordIndex, 10);

      // Second occurrence
      final occ2 = timing.findActiveWordAtMs(33500);
      expect(occ2, isNotNull);
      expect(occ2!.wordIndex, 9);
      expect(occ2.occurrence, 2);
    });
  });
}
