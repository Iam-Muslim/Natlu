import 'dart:convert';
import 'dart:io';

import '../../lib/data/quran_data.dart';
import '../../lib/tracking/word/phoneme_matrix.dart';

/// Offline Quran data loader for test harnesses without Flutter framework dependencies.
class SimulationQuranDataLoader {
  final Map<String, dynamic> rawJson;
  final List<String> tokenVocabulary;

  SimulationQuranDataLoader({
    required this.rawJson,
    required this.tokenVocabulary,
  });

  static Future<SimulationQuranDataLoader> loadFromProjectRoot([String projectRoot = '.']) async {
    final jsonFile = File('$projectRoot/assets/model/ordered_quran_phonemes.json');
    if (!jsonFile.existsSync()) {
      throw FileSystemException('Cannot find Quran phonemes at: ${jsonFile.path}');
    }
    final rawText = await jsonFile.readAsString();
    final jsonMap = jsonDecode(rawText) as Map<String, dynamic>;

    final tokensFile = File('$projectRoot/assets/model/tokens.txt');
    final List<String> tokens = [];
    if (tokensFile.existsSync()) {
      final tokenLines = await tokensFile.readAsLines();
      for (final line in tokenLines) {
        final parts = line.split(' ');
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty && parts[0] != '<blank>') {
          tokens.add(parts[0].trim());
        }
      }
    }

    // Pre-heat the global PhonemeMatrix
    PhonemeMatrix.reset();
    if (tokens.isNotEmpty) {
      PhonemeMatrix.preheat(tokens);
    }

    return SimulationQuranDataLoader(
      rawJson: jsonMap,
      tokenVocabulary: tokens,
    );
  }

  /// Returns all verses for a given Surah (1..114).
  List<QuranVerse> getSurahVerses(int surah) {
    final List<QuranVerse> verses = [];
    for (int ayah = 1; ayah <= 300; ayah++) {
      final key = '$surah:$ayah';
      final phonemeObj = rawJson[key];
      if (phonemeObj != null) {
        verses.add(QuranVerse.fromJson(surah, ayah, phonemeObj));
      } else {
        break;
      }
    }
    return verses;
  }

  /// Returns all continuous words for a given Surah.
  List<ContinuousQuranWord> getSurahWords(int surah) {
    final verses = getSurahVerses(surah);
    final List<ContinuousQuranWord> words = [];
    int globalIdx = 0;

    for (final verse in verses) {
      for (int i = 0; i < verse.phonemeWords.length; i++) {
        final uthmani = i < verse.uthmaniWords.length ? verse.uthmaniWords[i] : '';
        words.add(
          ContinuousQuranWord(
            globalIndex: globalIdx++,
            surah: verse.surah,
            ayah: verse.ayah,
            wordInAyah: i,
            uthmani: uthmani,
            phoneme: verse.phonemeWords[i],
          ),
        );
      }
    }
    return words;
  }

  /// Calculates contiguous word boundaries in characters for a list of words.
  List<int> calculateBoundaries(List<String> words) {
    final List<int> bounds = [];
    int cursor = 0;
    for (final w in words) {
      bounds.add(cursor);
      cursor += w.replaceAll(' ', '').length;
    }
    bounds.add(cursor);
    return bounds;
  }
}
