// lib/tracking/tajweed/error_explainer.dart
// ═══════════════════════════════════════════════════════════════════════════════
// ERROR EXPLAINER MODULE (DIRECT V2 SCHEMA ENGINE - ZERO HEURISTICS)
//
// Evaluates reciter phoneme alignment and acoustic holding durations directly:
//   Phase 1: Base Consonant & Deletion/Insertion Verification (`ErrorCategory.normal`).
//   Phase 2: Harakat & Tashkeel Modification Verification (`ErrorCategory.tashkeel`).
//   Phase 3: Direct Tajweed Duration Evaluation (`ErrorCategory.tajweed`):
//     - Madd (1-7): 2, 4, 6 Harakat evaluated against acoustic timestamps.
//     - Mushaddad Ghunnah (10): 2 Harakat evaluated on Mushaddad Noon & Meem.
//     - Shaddah (9): Consonant closure & holding duration (~1.5 Harakat).
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:math';

import '../../data/quran_data.dart';
import '../../utils/debug_logger.dart';
import 'tajweed_rules.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1: DATA MODELS & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

/// Broad classification of reciter errors used by UI color highlighting and statistics.
enum ErrorCategory {
  /// Acoustic duration or Shaddah doubling mismatch (`Yellow highlight`).
  tajweed,

  /// Base letter replacement, total deletion, or insertion (`Red highlight`).
  normal,

  /// Same base consonant but incorrect diacritics/vowels (`Yellow highlight`).
  tashkeel,
}

/// Specific speech modification operation detected during phoneme alignment.
enum SpeechErrorType {
  /// Reciter added an extra phoneme or syllable not present in reference.
  insert,

  /// Reciter skipped or swallowed a required phoneme or syllable.
  delete,

  /// Reciter substituted a phoneme with a different sound or diacritic.
  replace,
}

/// Immutable diagnostic record detailing a detected recitation mismatch.
class ReciterError {
  final ErrorCategory errorType;
  final SpeechErrorType speechErrorType;
  final TajweedDurationStatus? durationStatus;
  final String expectedPh;
  final String predictedPh;
  final TajweedRule? expectedRule;
  final TajweedRule? predictedRule;
  final double? expectedDuration;
  final double? actualDuration;

  ReciterError({
    required this.errorType,
    required this.speechErrorType,
    this.durationStatus,
    required this.expectedPh,
    required this.predictedPh,
    this.expectedRule,
    this.predictedRule,
    this.expectedDuration,
    this.actualDuration,
  });

  @override
  String toString() {
    return 'ReciterError(type: $errorType, action: $speechErrorType, status: $durationStatus, expected: "$expectedPh", predicted: "$predictedPh", expectedRule: ${expectedRule?.name.en}, expDur: $expectedDuration, actDur: $actualDuration)';
  }

  Map<String, dynamic> toMap() {
    return {
      'errorType': errorType.index,
      'speechErrorType': speechErrorType.index,
      'durationStatus': durationStatus?.index,
      'expectedPh': expectedPh,
      'predictedPh': predictedPh,
      'expectedRule': _ruleToMap(expectedRule),
      'predictedRule': _ruleToMap(predictedRule),
      'expectedDuration': expectedDuration,
      'actualDuration': actualDuration,
    };
  }

  static ReciterError fromMap(Map<String, dynamic> map) {
    return ReciterError(
      errorType: ErrorCategory.values[map['errorType']],
      speechErrorType: SpeechErrorType.values[map['speechErrorType']],
      durationStatus: map['durationStatus'] != null
          ? TajweedDurationStatus.values[map['durationStatus']]
          : null,
      expectedPh: map['expectedPh'] as String? ?? '',
      predictedPh: map['predictedPh'] as String? ?? '',
      expectedRule: _ruleFromMap(map['expectedRule'] as Map<String, dynamic>?),
      predictedRule:
          _ruleFromMap(map['predictedRule'] as Map<String, dynamic>?),
      expectedDuration: (map['expectedDuration'] as num?)?.toDouble(),
      actualDuration: (map['actualDuration'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic>? _ruleToMap(TajweedRule? rule) {
    if (rule == null) return null;
    return {
      'type': rule.runtimeType.toString(),
      'nameAr': rule.name.ar,
      'nameEn': rule.name.en,
      'goldenLen': rule.goldenLen,
    };
  }

  static TajweedRule? _ruleFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final String type = map['type'] as String? ?? '';
    final String nameAr = map['nameAr'] as String? ?? '';
    final String nameEn = map['nameEn'] as String? ?? '';
    final int goldenLen = map['goldenLen'] as int? ?? 2;

    if (type == 'LazemMaddRule') return const LazemMaddRule();
    if (type == 'LeenMaddRule') return const LeenMaddRule();
    if (type == 'AaredMaddRule') return const AaredMaddRule();
    if (type == 'MonfaselMaddRule') return const MonfaselMaddRule();
    if (type == 'MottaselMaddRule') return const MottaselMaddRule();
    if (type == 'MottaselMaddPauseRule') return const MottaselMaddPauseRule();
    if (type == 'NormalMaddRule') return const NormalMaddRule();
    if (type == 'MushaddadGhunnahRule') {
      return MushaddadGhunnahRule.withNames(nameAr: nameAr, nameEn: nameEn);
    }
    if (type == 'ShaddahRule') return const ShaddahRule();

    return MaddRule(
      name: LangName(ar: nameAr, en: nameEn),
      goldenLen: goldenLen,
    );
  }
}

/// Represents the alignment opcode between a single reference phoneme group and predicted phoneme group.
class PhonemeGroupAlignment {
  final String opType; // 'match', 'replace', 'delete', 'insert'
  final int refIdx;
  final int predIdx;

  PhonemeGroupAlignment({
    required this.opType,
    required this.refIdx,
    required this.predIdx,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2: ERROR EXPLAINER ENGINE (DIRECT EVALUATION)
// ═══════════════════════════════════════════════════════════════════════════════

class ErrorExplainer {
  /// Evaluates pre-aligned phoneme traces for a specific committed word window.
  static Map<int, List<ReciterError>> evaluatePreAlignedWords({
    required List<PhonemeGroupAlignment> alignments,
    required String fullPhonemes,
    required List<int> wordBoundaries,
    required String currentAsrText,
    required List<double> trackingTimestamps,
    required int bestAsrStartIdx,
    required int targetCharCursor,
    required int startWordId,
    required int nextWordId,
    required int totalAyahWords,
    List<WordTajweedRule> expectedWordRules = const [],
  }) {
    final Map<int, List<ReciterError>> errorsByWord = {};
    final Map<int, List<String>> wordErrorDescMap = {};

    int getWordIndex(int charIdx) {
      if (wordBoundaries.isEmpty) return 0;
      for (int w = 0; w < wordBoundaries.length - 1; w++) {
        if (charIdx >= wordBoundaries[w] && charIdx < wordBoundaries[w + 1]) {
          return w;
        }
      }
      return max(0, wordBoundaries.length - 2);
    }

    String getWordText(int wIdx) {
      if (wIdx < 0 || wIdx >= wordBoundaries.length - 1) return '';
      final start = wordBoundaries[wIdx];
      final end = (wIdx + 1 < wordBoundaries.length)
          ? wordBoundaries[wIdx + 1]
          : fullPhonemes.length;
      return fullPhonemes.substring(start, min(end, fullPhonemes.length));
    }

    for (var align in alignments) {
      if (align.refIdx < 0 && align.predIdx < 0) continue;
      int absRefIdx = targetCharCursor + align.refIdx;
      int wIdx = -1;
      if (absRefIdx >= 0 && absRefIdx < fullPhonemes.length) {
        wIdx = getWordIndex(absRefIdx);
      } else if (align.refIdx == -1 && targetCharCursor < fullPhonemes.length) {
        wIdx = getWordIndex(targetCharCursor);
      }
      if (wIdx < startWordId || wIdx >= nextWordId) {
        continue; // Out of bounds of the committed match
      }

      String refChunk = '';
      if (absRefIdx >= 0 && absRefIdx < fullPhonemes.length) {
        refChunk = fullPhonemes[absRefIdx];
      }

      int absPredIdx = bestAsrStartIdx + align.predIdx;
      String predChunk = '';
      if (absPredIdx >= 0 && absPredIdx < currentAsrText.length) {
        predChunk = currentAsrText[absPredIdx];
      }

      // Calculate chunk duration
      double chunkDuration = 0.0;
      if (absPredIdx >= 0 && absPredIdx < trackingTimestamps.length) {
        chunkDuration = trackingTimestamps[absPredIdx];
      }
      if (chunkDuration <= 0.0) chunkDuration = 0.15;

      wordErrorDescMap.putIfAbsent(wIdx, () => []);
      List<ReciterError> chunkErrors = _evaluateChunkAlignment(
        align: align,
        refChunk: refChunk,
        predChunk: predChunk,
        chunkDuration: chunkDuration,
        wordIdx: wIdx,
        wordErrorDesc: wordErrorDescMap[wIdx]!,
        expectedWordRules: expectedWordRules,
        wordText: getWordText(wIdx),
      );

      if (chunkErrors.isNotEmpty) {
        errorsByWord.putIfAbsent(wIdx, () => []).addAll(chunkErrors);
      }
    }

    // Sort errors by UI priority
    errorsByWord.forEach(
      (_, list) => list.sort(
        (a, b) => _getErrorPriority(a).compareTo(_getErrorPriority(b)),
      ),
    );

    // Filter out normal phoneme substitutions and surplus duration
    errorsByWord.forEach((wIdx, list) {
      list.removeWhere((e) {
        return e.errorType == ErrorCategory.normal ||
            e.durationStatus == TajweedDurationStatus.surplus;
      });
    });

    errorsByWord.forEach((wIdx, list) {
      final String wordStr = getWordText(wIdx);
      for (var e in list) {
        String ruleInfo = e.expectedRule != null
            ? ' | Rule: ${e.expectedRule!.name.en} (req: ${e.expectedDuration?.toStringAsFixed(2)}s, got: ${e.actualDuration?.toStringAsFixed(2)}s)'
            : '';
        DebugLogger.log(
          'Error',
          '🚨 [ERROR LOG] Word "$wordStr" ($wIdx) | ${e.errorType.name.toUpperCase()} -> ${e.speechErrorType.name.toUpperCase()} (Exp: "${e.expectedPh}" vs Got: "${e.predictedPh}")$ruleInfo',
        );
      }
    });

    errorsByWord.removeWhere((wIdx, list) => list.isEmpty);
    return errorsByWord;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2.2 DIRECT CHUNK EVALUATION PIPELINE
  // ───────────────────────────────────────────────────────────────────────────
  static List<ReciterError> _evaluateChunkAlignment({
    required PhonemeGroupAlignment align,
    required String refChunk,
    required String predChunk,
    required double chunkDuration,
    required int wordIdx,
    required List<String> wordErrorDesc,
    required List<WordTajweedRule> expectedWordRules,
    required String wordText,
  }) {
    // ── Phase 1A: Complete Insertion Error ──
    if (align.opType == 'insert') {
      return [
        ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.insert,
          expectedPh: '',
          predictedPh: predChunk,
        ),
      ];
    }

    // ── Phase 1B: Complete Deletion Error ──
    if (align.opType == 'delete') {
      wordErrorDesc.add('Delete(ref:$refChunk)');
      return [
        ReciterError(
          errorType: ErrorCategory.normal,
          speechErrorType: SpeechErrorType.delete,
          expectedPh: refChunk,
          predictedPh: '',
        ),
      ];
    }

    List<ReciterError> chunkErrors = [];

    // ── Phase 1C: Base Consonant Replacement Error ──
    if (refChunk.isNotEmpty &&
        predChunk.isNotEmpty &&
        refChunk[0] != predChunk[0]) {
      if (_getSubCost(refChunk[0], predChunk[0]) > 6) {
        wordErrorDesc.add('Replace(ref:$refChunk got:$predChunk)');
        return [
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
          ),
        ];
      } else {
        wordErrorDesc.add('Replace(ref:$refChunk got:$predChunk)');
        chunkErrors.add(
          ReciterError(
            errorType: ErrorCategory.normal,
            speechErrorType: SpeechErrorType.replace,
            expectedPh: refChunk,
            predictedPh: predChunk,
          ),
        );
      }
    }

    // ── Phase 2: Tashkeel & Harakat Verification ──
    if (refChunk.isNotEmpty &&
        predChunk.isNotEmpty &&
        refChunk[0] == predChunk[0] &&
        refChunk.replaceAll(refChunk[0], '') !=
            predChunk.replaceAll(predChunk[0], '')) {
      wordErrorDesc.add('Tashkeel(ref:$refChunk got:$predChunk)');
      chunkErrors.add(
        ReciterError(
          errorType: ErrorCategory.tashkeel,
          speechErrorType: SpeechErrorType.replace,
          expectedPh: refChunk,
          predictedPh: predChunk,
        ),
      );
    }

    // ── Phase 3: Direct Duration & Doubling Tajweed Evaluation ──
    // Match the active chunk against pre-assigned rules for this word
    final bool isMaddChunk = refChunk.isNotEmpty && 'اۥۦ'.contains(refChunk[0]);
    final bool isNasalChunk = refChunk.isNotEmpty && 'نم'.contains(refChunk[0]);
    final bool isDoubledChunk =
        refChunk.length >= 2 && refChunk[1] == refChunk[0];

    for (final wRule in expectedWordRules) {
      final rule = _instantiateTajweedRule(wRule);

      // 1. Madd duration check
      if (rule is MaddRule && isMaddChunk) {
        final TajweedDurationStatus durStatus =
            rule.checkDurationStatus(chunkDuration);
        final double req = rule.getRequiredDuration();

        if (durStatus == TajweedDurationStatus.defect) {
          wordErrorDesc.add(
            '${rule.name.en}Defect(got:${chunkDuration.toStringAsFixed(2)}s need:>=${req.toStringAsFixed(2)}s)',
          );
          chunkErrors.add(
            ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: align.opType == 'delete'
                  ? SpeechErrorType.delete
                  : SpeechErrorType.replace,
              durationStatus: durStatus,
              expectedPh: refChunk,
              predictedPh: predChunk,
              expectedRule: rule,
              expectedDuration: req,
              actualDuration: chunkDuration,
            ),
          );
        }
      }

      // 2. Mushaddad Noon & Meem Ghunnah duration check
      if (rule is MushaddadGhunnahRule && isNasalChunk) {
        final TajweedDurationStatus durStatus =
            rule.checkDurationStatus(chunkDuration);
        final double req = rule.getRequiredDuration();

        if (durStatus == TajweedDurationStatus.defect) {
          wordErrorDesc.add(
            '${rule.name.en}Defect(got:${chunkDuration.toStringAsFixed(2)}s need:>=${req.toStringAsFixed(2)}s)',
          );
          chunkErrors.add(
            ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: align.opType == 'delete'
                  ? SpeechErrorType.delete
                  : SpeechErrorType.replace,
              durationStatus: durStatus,
              expectedPh: refChunk,
              predictedPh: predChunk,
              expectedRule: rule,
              expectedDuration: req,
              actualDuration: chunkDuration,
            ),
          );
        }
      }

      // 3. Shaddah closure & duration check
      if (rule is ShaddahRule && isDoubledChunk && !isMaddChunk && !isNasalChunk) {
        final bool predDoubled =
            predChunk.length >= 2 && predChunk[1] == predChunk[0];
        final TajweedDurationStatus durStatus =
            rule.checkDurationStatus(chunkDuration);
        final double req = rule.getRequiredDuration();

        if (!predDoubled || durStatus == TajweedDurationStatus.defect) {
          wordErrorDesc.add(
            '${rule.name.en}Defect(doubled:$predDoubled, got:${chunkDuration.toStringAsFixed(2)}s need:>=${req.toStringAsFixed(2)}s)',
          );
          chunkErrors.add(
            ReciterError(
              errorType: ErrorCategory.tajweed,
              speechErrorType: align.opType == 'delete'
                  ? SpeechErrorType.delete
                  : SpeechErrorType.replace,
              durationStatus: durStatus,
              expectedPh: refChunk,
              predictedPh: predChunk,
              expectedRule: rule,
              expectedDuration: req,
              actualDuration: chunkDuration,
            ),
          );
        }
      }
    }

    return chunkErrors;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2.3 HELPER METHODS
  // ───────────────────────────────────────────────────────────────────────────

  static TajweedRule _instantiateTajweedRule(WordTajweedRule wRule) {
    switch (wRule.ruleId) {
      case 1:
        return const NormalMaddRule();
      case 2:
        return const MonfaselMaddRule();
      case 3:
        return const MottaselMaddRule();
      case 4:
        return const MottaselMaddPauseRule();
      case 5:
        return const AaredMaddRule();
      case 6:
        return const LazemMaddRule();
      case 7:
        return const LeenMaddRule();
      case 9:
        return const ShaddahRule();
      case 10:
        return MushaddadGhunnahRule.withNames(
          nameAr: wRule.nameAr,
          nameEn: wRule.nameEn,
        );
      default:
        return MaddRule(
          name: LangName(ar: wRule.nameAr, en: wRule.nameEn),
          goldenLen: wRule.goldenLen,
        );
    }
  }

  static int _getErrorPriority(ReciterError e) {
    if (e.errorType == ErrorCategory.tashkeel) return 1;
    if (e.expectedRule is MaddRule) return 2;
    if (e.expectedRule is MushaddadGhunnahRule) return 3;
    if (e.expectedRule is ShaddahRule) return 4;
    return 5;
  }

  static int _getSubCost(String c1, String c2) {
    if (c1 == c2) return 0;
    if (c1.isEmpty || c2.isEmpty) return 10;
    const groups = [
      "ذدضتط",
      "ظزذصسث",
      "جزش",
      "ءأإآاهعحغخ",
      "ةهت",
      "ۦي",
      "ۥو",
      "ںن۾م",
      "قكغ",
      "فبم",
    ];
    for (final g in groups) {
      if (g.contains(c1) && g.contains(c2)) return 6;
    }
    return 12;
  }
}
