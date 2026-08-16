import 'dart:io';

class WordMatchDetail {
  final int wordId;
  final String uthmani;
  final String phoneme;
  final bool isGreen;
  final bool isRed;
  final String asrChunk;
  final double score;
  final double threshold;
  final double coverage;

  WordMatchDetail({
    required this.wordId,
    required this.uthmani,
    required this.phoneme,
    required this.isGreen,
    required this.isRed,
    required this.asrChunk,
    required this.score,
    required this.threshold,
    required this.coverage,
  });
}

class TestScenarioResult {
  final String scenarioName;
  final int surah;
  final int ayah;
  final int totalWordsExpected;
  final int wordsRecited;
  final int greenWords;
  final int redWords;
  final int falseGreens;
  final int falseReds;
  final bool stalled;
  final String details;
  final double elapsedMs;
  final List<WordMatchDetail> wordDetails;
  final List<String> errorLogs;

  TestScenarioResult({
    required this.scenarioName,
    required this.surah,
    required this.ayah,
    required this.totalWordsExpected,
    required this.wordsRecited,
    required this.greenWords,
    required this.redWords,
    required this.falseGreens,
    required this.falseReds,
    required this.stalled,
    required this.details,
    required this.elapsedMs,
    this.wordDetails = const [],
    this.errorLogs = const [],
  });

  bool get isSuccess => falseGreens == 0 && falseReds == 0 && !stalled;
}

class TestReporter {
  final String logFilePath;
  final String failureFilePath;
  final List<TestScenarioResult> results = [];
  final Stopwatch globalStopwatch = Stopwatch();

  TestReporter({
    this.logFilePath = 'test/matching_simulation/matching_analysis_log.txt',
    this.failureFilePath = 'test/matching_simulation/matching_failures.txt',
  }) {
    globalStopwatch.start();
  }

  void recordResult(TestScenarioResult result) {
    results.add(result);
  }

  Future<void> flushToDisk() async {
    final logFile = File(logFilePath);
    final failFile = File(failureFilePath);

    final logSink = logFile.openWrite();
    final failSink = failFile.openWrite();

    int totalTests = results.length;
    int successfulTests = 0;
    int totalFalseGreens = 0;
    int totalFalseReds = 0;
    int totalStalls = 0;
    double totalTimeMs = globalStopwatch.elapsedMilliseconds.toDouble();

    final Map<String, int> scenarioTotal = {};
    final Map<String, int> scenarioPassed = {};

    for (final r in results) {
      scenarioTotal[r.scenarioName] = (scenarioTotal[r.scenarioName] ?? 0) + 1;
      if (r.isSuccess) {
        successfulTests++;
        scenarioPassed[r.scenarioName] = (scenarioPassed[r.scenarioName] ?? 0) + 1;
      } else {
        totalFalseGreens += r.falseGreens;
        totalFalseReds += r.falseReds;
        if (r.stalled) totalStalls++;

        failSink.writeln('╔══════════════════════════════════════════════════════════════════════════════');
        failSink.writeln('║ ❌ FAILURE in [${r.scenarioName}] | Surah ${r.surah}:${r.ayah}');
        failSink.writeln('╠══════════════════════════════════════════════════════════════════════════════');
        failSink.writeln('║ Expected Words: ${r.totalWordsExpected} | Recited Words: ${r.wordsRecited}');
        failSink.writeln('║ Matched Summary: Green=${r.greenWords}, Red=${r.redWords}');
        failSink.writeln('║ Discrepancies: FalseGreen=${r.falseGreens}, FalseRed=${r.falseReds}, Stalled=${r.stalled}');
        failSink.writeln('║ Duration: ${r.elapsedMs.toStringAsFixed(1)}ms');
        failSink.writeln('║ Summary: ${r.details}');
        
        if (r.errorLogs.isNotEmpty) {
          failSink.writeln('╟──────────────────────────────────────────────────────────────────────────────');
          failSink.writeln('║ Internal Logs:');
          for (final err in r.errorLogs) {
            failSink.writeln('║   • $err');
          }
        }

        if (r.wordDetails.isNotEmpty) {
          failSink.writeln('╟──────────────────────────────────────────────────────────────────────────────');
          failSink.writeln('║ Word-by-Word Trace:');
          for (final wd in r.wordDetails) {
            final String status = wd.isGreen ? '🟩 GREEN' : (wd.isRed ? '🟥 RED' : '⚪ UNMATCHED');
            failSink.writeln(
              '║   Word ${wd.wordId.toString().padRight(4)}: ${status.padRight(12)} | "${wd.uthmani}" (${wd.phoneme}) | ASR: "${wd.asrChunk}" | Score: ${wd.score.toStringAsFixed(3)} / Thresh: ${wd.threshold.toStringAsFixed(3)} | Cov: ${(wd.coverage * 100).toStringAsFixed(0)}%',
            );
          }
        }

        failSink.writeln('╚══════════════════════════════════════════════════════════════════════════════\n');
      }
    }

    final double successRate = totalTests > 0 ? (successfulTests / totalTests) * 100.0 : 100.0;

    logSink.writeln('════════════════════════════════════════════════════════════════════════════════');
    logSink.writeln('                 QURAN MATCHING SYSTEM EXHAUSTIVE SIMULATION REPORT             ');
    logSink.writeln('════════════════════════════════════════════════════════════════════════════════');
    logSink.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
    logSink.writeln('Total Execution Time: ${(totalTimeMs / 1000).toStringAsFixed(2)}s');
    logSink.writeln('Total Scenarios Tested: $totalTests');
    logSink.writeln('Passed Scenarios: $successfulTests / $totalTests (${successRate.toStringAsFixed(2)}%)');
    logSink.writeln('Total False Greens (Wrong Word Accepted): $totalFalseGreens');
    logSink.writeln('Total False Reds (Correct Word Flagged Red): $totalFalseReds');
    logSink.writeln('Total Stalls / Cursor Freezes: $totalStalls');
    logSink.writeln('════════════════════════════════════════════════════════════════════════════════');
    logSink.writeln('SCENARIO BREAKDOWN:');
    for (final entry in scenarioTotal.entries) {
      final passed = scenarioPassed[entry.key] ?? 0;
      final pct = (passed / entry.value) * 100.0;
      logSink.writeln(' - ${entry.key.padRight(28)}: $passed / ${entry.value} (${pct.toStringAsFixed(1)}%)');
    }
    logSink.writeln('════════════════════════════════════════════════════════════════════════════════');

    await logSink.flush();
    await logSink.close();

    await failSink.flush();
    await failSink.close();
  }

  void printSummary() {
    int totalTests = results.length;
    int successfulTests = results.where((r) => r.isSuccess).length;
    final double successRate = totalTests > 0 ? (successfulTests / totalTests) * 100.0 : 100.0;
    print('\n📊 SIMULATION SUMMARY: $successfulTests / $totalTests passed (${successRate.toStringAsFixed(2)}%) in ${(globalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
    print('📝 Logs written to: $logFilePath and $failureFilePath\n');
  }
}
