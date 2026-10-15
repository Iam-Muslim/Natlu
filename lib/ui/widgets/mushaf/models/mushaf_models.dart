import 'dart:ui';
import 'package:flutter/material.dart';

/// Desktop & Mobile friendly scroll behavior allowing mouse/touch drag on PageView
class MushafScrollBehavior extends MaterialScrollBehavior {
  const MushafScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

/// Fast typed word reference within a Mushaf page
class MushafWordRef {
  final int surah;
  final int ayah;
  final int wordIndex1;
  final int wordIndex0;

  const MushafWordRef(this.surah, this.ayah, this.wordIndex1, this.wordIndex0);
}

/// Lightweight reference for zero-allocation line-level tap dispatch
class MushafLineChild {
  final bool isMarker;
  final int surah;
  final int ayah;
  final int wordIndex0;
  final String wordText;

  const MushafLineChild.word({
    required this.surah,
    required this.ayah,
    required this.wordIndex0,
    required this.wordText,
  })  : isMarker = false;

  const MushafLineChild.marker({
    required this.surah,
    required this.ayah,
  })  : isMarker = true,
        wordIndex0 = -1,
        wordText = '';
}

/// In-memory parsed data bundle produced from mushaf_pages.json
class MushafParsedData {
  final Map<int, List<Map<String, dynamic>>> pages;
  final Map<String, int> ayahMap;
  final Map<int, (int, int)> firstAyahMap;
  final Map<int, MushafWordRef> lastWordMap;
  final Map<int, Set<String>> pageAyahsMap;
  final Map<int, Set<int>> pageSurahsMap;
  final Map<int, int> dominantSurahMap;

  MushafParsedData({
    required this.pages,
    required this.ayahMap,
    required this.firstAyahMap,
    required this.lastWordMap,
    required this.pageAyahsMap,
    required this.pageSurahsMap,
    required this.dominantSurahMap,
  });
}
