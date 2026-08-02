import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_great_quran/tracking/word/quran_normalizer.dart';
import 'package:the_great_quran/data/quran_data.dart';

void main() {
  test('Mining Sherpa Biases', () async {
    print('===========================================');
    print('⛏️ MINING SHERPA SUBSTITUTION BIASES');
    print('===========================================');

    final dbFile = File('assets/model/ordered_quran_phonemes.json');
    if (!dbFile.existsSync()) {
      print('Database not found.');
      return;
    }
    
    final dbData = await dbFile.readAsString();
    final Map<String, dynamic> phonemesList = jsonDecode(dbData);
    
    List<QuranVerse> verses = [];
    for (final entry in phonemesList.entries) {
      final keyParts = entry.key.split(':');
      if (keyParts.length == 2) {
        final surahNum = int.tryParse(keyParts[0]) ?? 1;
        final ayahNum = int.tryParse(keyParts[1]) ?? 1;
        final phonemeObj = entry.value as Map<String, dynamic>;
        verses.add(QuranVerse.fromJson(surahNum, ayahNum, phonemeObj));
      }
    }
    
    final testDataFile = File('simulate testing/batch_streaming_test_data.json');
    if (!testDataFile.existsSync()) {
      print('batch_streaming_test_data.json not found.');
      return;
    }
    
    final batchData = jsonDecode(await testDataFile.readAsString()) as List;
    Map<String, int> substitutionFrequencies = {};

    for (var scenario in batchData) {
      int surah = scenario['surah'];
      int startAyah = scenario['start_ayah'];
      int endAyah = scenario['end_ayah'];
      List<dynamic> frames = scenario['frames'];
      
      final List<String> refChunks = [];
      for (int ayah = startAyah; ayah <= endAyah; ayah++) {
        final verse = verses.firstWhere((v) => v.surah == surah && v.ayah == ayah, orElse: () => verses.first);
        if (verse.surah != surah) continue;
        for (int i = 0; i < verse.phonemeWords.length; i++) {
          String wordPhoneme = verse.phonemeWords[i];
          if (wordPhoneme.isEmpty) continue;
          refChunks.addAll(QuranNormalizer.chunkPhonemes(wordPhoneme));
        }
      }
      
      // Get the final fully transcribed frame text for this scenario
      String finalAsrText = frames.last['text'] as String;
      if (finalAsrText.isEmpty) continue;
      
      final List<String> asrChunks = QuranNormalizer.chunkPhonemes(finalAsrText)
          .where((t) => t.trim().isNotEmpty && t != '<blank>' && t != 'ؙ')
          .toList();

      int n = refChunks.length;
      int m = asrChunks.length;
      List<List<int>> dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));

      for (int i = 0; i <= n; i++) dp[i][0] = i;
      for (int j = 0; j <= m; j++) dp[0][j] = j;

      for (int i = 1; i <= n; i++) {
        for (int j = 1; j <= m; j++) {
          if (refChunks[i - 1] == asrChunks[j - 1]) {
            dp[i][j] = dp[i - 1][j - 1];
          } else {
            dp[i][j] = 1 + [
              dp[i - 1][j],    // Delete
              dp[i][j - 1],    // Insert
              dp[i - 1][j - 1] // Substitute
            ].reduce((a, b) => a < b ? a : b);
          }
        }
      }

      int i = n, j = m;
      while (i > 0 && j > 0) {
        if (refChunks[i - 1] == asrChunks[j - 1]) {
          i--; j--;
        } else if (dp[i][j] == dp[i - 1][j - 1] + 1) { // Substitution
          String refP = refChunks[i - 1];
          String predP = asrChunks[j - 1];
          String baseRef = refP.isNotEmpty ? refP[0] : '';
          String basePred = predP.isNotEmpty ? predP[0] : '';
          
          if (baseRef != basePred && baseRef.isNotEmpty && basePred.isNotEmpty) {
              final vowels = const ['ا', 'و', 'ي', 'ى', 'ۦ', 'ۥ', '۪', 'ں', 'َ', 'ِ', 'ُ'];
              if (!vowels.contains(baseRef) && !vowels.contains(basePred)) {
                  String pairKey = '$baseRef -> $basePred';
                  substitutionFrequencies[pairKey] = (substitutionFrequencies[pairKey] ?? 0) + 1;
              }
          }
          i--; j--;
        } else if (dp[i][j] == dp[i - 1][j] + 1) { // Deletion
          i--;
        } else { // Insertion
          j--;
        }
      }
    }
    
    print('\n📊 EMPIRICAL SUBSTITUTION FREQUENCIES (Base Consonants Only):');
    
    var sortedKeys = substitutionFrequencies.keys.toList()
      ..sort((k1, k2) => substitutionFrequencies[k2]!.compareTo(substitutionFrequencies[k1]!));
      
    for (var key in sortedKeys) {
      if (substitutionFrequencies[key]! >= 1) {
         print('   ${key.padRight(8)} : ${substitutionFrequencies[key]} times');
      }
    }
    print('===========================================\n');
  });
}
