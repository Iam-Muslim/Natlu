import 'package:flutter/material.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../../state/app_state.dart';

/// Modal bottom sheet presenting an interactive, detailed breakdown
/// of Tajweed, Tashkeel, or phonetic pronunciation errors for a specific word.
class ErrorDetailDialog extends StatelessWidget {
  final String word;
  final List<ReciterError> errors;

  const ErrorDetailDialog({
    super.key,
    required this.word,
    required this.errors,
  });

  /// Static helper to display the modal bottom sheet cleanly.
  static void show(
    BuildContext context, {
    required String word,
    required List<ReciterError> errors,
  }) {
    if (errors.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ErrorDetailDialog(word: word, errors: errors),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isAr = app.isArabic;
    final isDark = app.isDarkMode;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.58,
      ),
      decoration: BoxDecoration(
        color: isDark ? c.surface : const Color(0xFFFFFDF9),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? c.gold.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.10),
            blurRadius: 36,
            spreadRadius: 0,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle Bar ──
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? c.border : const Color(0xFFD6CCC0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Scrollable Content ──
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header: Word & Error Count ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? c.gold.withValues(alpha: 0.06)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? c.gold.withValues(alpha: 0.15)
                              : const Color(0xFFEDE4D6),
                          width: 1,
                        ),
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            word,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontFamily: 'HafsSmart',
                              fontSize: 26,
                              color: c.text,
                              height: 1.3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? c.red.withValues(alpha: 0.12)
                                  : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? c.red.withValues(alpha: 0.25)
                                    : const Color(0xFFFCA5A5),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              errors.length == 1
                                  ? (isAr ? '1 خطأ' : '1 Error')
                                  : (isAr
                                      ? '${errors.length} أخطاء'
                                      : '${errors.length} Errors'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? c.red : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Error Cards Layout ──
                    ..._buildErrorCardsLayout(errors, c, isAr, isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cleans phonetic markers to show readable Arabic characters.
  static String _cleanPhonetic(String input) {
    return input
        .replaceAll('\u06e5', 'و')
        .replaceAll('\u06e6', 'ي')
        .replaceAll('\u06ba', 'ن')
        .replaceAll('\u06fe', 'م')
        .replaceAll('\u0687', '')
        .replaceAll('ڇ', '')
        .replaceAll('ۜ', '')
        .replaceAll('۪', '')
        .replaceAll('ؙ', '')
        .replaceAll('ٲ', 'أ')
        .replaceAll('\u0640', '');
  }

  /// Returns action badge text for speech errors.
  static String _actionBadge(SpeechErrorType type, bool isAr) {
    switch (type) {
      case SpeechErrorType.delete:
        return isAr ? 'حذف' : 'Skipped';
      case SpeechErrorType.insert:
        return isAr ? 'زيادة' : 'Added';
      case SpeechErrorType.replace:
        return isAr ? 'تبديل' : 'Changed';
    }
  }

  List<Widget> _buildErrorCardsLayout(
    List<ReciterError> errors,
    ThemeColors c,
    bool isAr,
    bool isDark,
  ) {
    if (errors.length == 1) {
      return [_buildErrorCard(errors[0], c, isAr, isDark, isCompact: false)];
    }
    List<Widget> rows = [];
    int i = 0;
    while (i < errors.length) {
      if (i + 1 < errors.length) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildErrorCard(
                      errors[i],
                      c,
                      isAr,
                      isDark,
                      isCompact: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildErrorCard(
                      errors[i + 1],
                      c,
                      isAr,
                      isDark,
                      isCompact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        i += 2;
      } else {
        rows.add(_buildErrorCard(errors[i], c, isAr, isDark, isCompact: false));
        i += 1;
      }
    }
    return rows;
  }

  Widget _buildErrorCard(
    ReciterError e,
    ThemeColors c,
    bool isAr,
    bool isDark, {
    bool isCompact = false,
  }) {
    final expected = e.expectedPh.isEmpty ? '—' : _cleanPhonetic(e.expectedPh);
    final predicted = e.predictedPh.isEmpty
        ? '—'
        : _cleanPhonetic(e.predictedPh);
    final bool isDurationErr =
        e.expectedDuration != null && e.actualDuration != null;

    String title;
    IconData icon;
    Color accent;
    String desc;
    String advice = '';
    String? statusBadge;

    if (e.errorType == ErrorCategory.tajweed) {
      String ruleName = isAr
          ? (e.expectedRule?.name.ar ?? '')
          : (e.expectedRule?.name.en ?? '');
      if (ruleName.isEmpty) {
        ruleName = isAr ? 'حكم تجويد' : 'Tajweed Rule';
      }
      title = ruleName;
      icon = Icons.auto_stories_rounded;
      accent = isDark ? c.gold : const Color(0xFFCA8A04); // Vibrant true golden-yellow

      desc = isAr ? e.messageAr : e.messageEn;
      advice = isAr ? e.adviceAr : e.adviceEn;

      if (e.durationStatus == TajweedDurationStatus.underheld) {
        statusBadge = isAr ? 'نقص' : 'Underheld';
      } else if (e.durationStatus == TajweedDurationStatus.overheld) {
        statusBadge = isAr ? 'زيادة' : 'Overheld';
      }
    } else if (e.errorType == ErrorCategory.tashkeel) {
      title = isAr ? 'خطأ في التشكيل' : 'Vowel Mark Error';
      icon = Icons.spellcheck_rounded;
      accent = isDark ? const Color(0xFF5B8DEF) : const Color(0xFF2563EB); // Royal/Azure Blue
      desc = isAr ? e.messageAr : e.messageEn;
      advice = isAr ? e.adviceAr : e.adviceEn;
    } else {
      if (e.speechErrorType == SpeechErrorType.insert) {
        title = isAr ? 'إضافة حرف زائد' : 'Extra Letter Added';
      } else {
        title = isAr ? 'خطأ في النطق' : 'Pronunciation Error';
      }
      icon = Icons.record_voice_over_rounded;
      accent = isDark ? c.red : const Color(0xFFDC2626); // Vibrant Coral Red
      desc = isAr ? e.messageAr : e.messageEn;
      advice = isAr ? e.adviceAr : e.adviceEn;
    }

    final Color correctGreen = isDark ? c.green : const Color(0xFF059669);
    final Color errorRed = isDark ? c.red : const Color(0xFFDC2626);

    return Container(
      margin: isCompact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? c.surfaceHigh : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.28),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: 0.08),
                  blurRadius: 14,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.08 : 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.15 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: accent, size: isCompact ? 14 : 16),
                ),
                SizedBox(width: isCompact ? 6 : 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: isCompact ? 2 : null,
                    overflow: isCompact ? TextOverflow.ellipsis : null,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: isCompact ? 13 : 15,
                    ),
                  ),
                ),
                if (statusBadge != null) ...[
                  SizedBox(width: isCompact ? 4 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 6 : 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.25 : 0.25),
                      ),
                    ),
                    child: Text(
                      statusBadge,
                      style: TextStyle(
                        color: accent,
                        fontSize: isCompact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ] else if (e.errorType == ErrorCategory.normal) ...[
                  SizedBox(width: isCompact ? 4 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 6 : 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.25 : 0.25),
                      ),
                    ),
                    child: Text(
                      _actionBadge(e.speechErrorType, isAr),
                      style: TextStyle(
                        color: accent,
                        fontSize: isCompact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Card Body ──
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 12 : 16,
              isCompact ? 10 : 12,
              isCompact ? 12 : 16,
              isCompact ? 12 : 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  maxLines: isCompact ? 3 : null,
                  overflow: isCompact ? TextOverflow.ellipsis : null,
                  style: TextStyle(
                    color: isDark ? c.muted : const Color(0xFF4A4036),
                    fontSize: isCompact ? 12 : 13,
                    height: isCompact ? 1.35 : 1.45,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.w500,
                  ),
                ),
                if (advice.isNotEmpty) ...[
                  SizedBox(height: isCompact ? 6 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 8 : 10,
                      vertical: isCompact ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.08 : 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.20 : 0.22),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: isCompact ? 14 : 16,
                          color: accent,
                        ),
                        SizedBox(width: isCompact ? 6 : 8),
                        Expanded(
                          child: Text(
                            advice,
                            style: TextStyle(
                              color: isDark ? c.text : const Color(0xFF2C1810),
                              fontSize: isCompact ? 11 : 12,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: isCompact ? 8 : 12),

                if (isDurationErr) ...[
                  _buildDurationBar(
                    e.expectedDuration!,
                    e.actualDuration!,
                    accent,
                    c,
                    isAr,
                    isCompact: isCompact,
                    durationStatus: e.durationStatus,
                    isDark: isDark,
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
                ],

                if (isDurationErr || e.errorType == ErrorCategory.tajweed) ...[
                  if (expected != '—' && expected.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isCompact ? 8 : 12),
                      decoration: BoxDecoration(
                        color: isDark ? c.bg : const Color(0xFFFBF8F4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? c.border.withValues(alpha: 0.25)
                              : const Color(0xFFE8DFD3),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        expected,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: c.text,
                          fontSize: isCompact ? 24 : 28,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'HafsSmart',
                        ),
                      ),
                    ),
                ] else ...[
                  if (expected != '—' || predicted != '—')
                    Container(
                      padding: EdgeInsets.all(isCompact ? 8 : 12),
                      decoration: BoxDecoration(
                        color: isDark ? c.bg : const Color(0xFFFBF8F4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? c.border.withValues(alpha: 0.25)
                              : const Color(0xFFE8DFD3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: correctGreen,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        isAr ? 'الصواب' : 'Correct',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: correctGreen,
                                          fontSize: isCompact ? 10 : 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  expected,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: isCompact ? 20 : 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'HafsSmart',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 4 : 8,
                            ),
                            child: Icon(
                              isAr
                                  ? Icons.arrow_back_rounded
                                  : Icons.arrow_forward_rounded,
                              color: isDark ? c.border : const Color(0xFFA89F91),
                              size: isCompact ? 14 : 18,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: errorRed,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        isAr ? 'نطقك' : 'Yours',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: errorRed,
                                          fontSize: isCompact ? 10 : 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  predicted,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: isCompact ? 20 : 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'HafsSmart',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationBar(
    double expected,
    double actual,
    Color accent,
    ThemeColors c,
    bool isAr, {
    bool isCompact = false,
    TajweedDurationStatus? durationStatus,
    required bool isDark,
  }) {
    double ratio = expected > 0 ? (actual / expected).clamp(0.0, 1.0) : 0.0;
    final bool isUnderheld = durationStatus == TajweedDurationStatus.underheld ||
        (durationStatus == null && actual < expected);
    final bool isOverheld = durationStatus == TajweedDurationStatus.overheld ||
        (durationStatus == null && actual > expected);

    final String statusLabel = isUnderheld
        ? (isAr ? 'نقص' : 'Underheld')
        : isOverheld
            ? (isAr ? 'زيادة' : 'Overheld')
            : (isAr ? 'صحيح' : 'Valid');

    final Color statusColor = isUnderheld
        ? (isDark ? c.red : const Color(0xFFDC2626))
        : isOverheld
            ? (isDark ? c.gold : const Color(0xFFCA8A04))
            : (isDark ? c.green : const Color(0xFF15803D));

    return Container(
      padding: EdgeInsets.all(isCompact ? 8 : 12),
      decoration: BoxDecoration(
        color: isDark ? c.bg : const Color(0xFFFBF8F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? c.border.withValues(alpha: 0.25)
              : const Color(0xFFE8DFD3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            spacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAr ? 'مدة النطق:' : 'Duration:',
                    style: TextStyle(
                      color: isDark ? c.muted : const Color(0xFF6B5E4F),
                      fontSize: isCompact ? 10.5 : 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: isDark ? 0.12 : 0.10),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: statusColor.withValues(alpha: isDark ? 0.25 : 0.25),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: isCompact ? 9.5 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${actual.toStringAsFixed(2)}s',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: isCompact ? 11 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' / ${expected.toStringAsFixed(2)}s',
                    style: TextStyle(
                      color: isDark ? c.muted : const Color(0xFF8B7D6B),
                      fontSize: isCompact ? 10 : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: isCompact ? 6 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? c.border.withValues(alpha: 0.25)
                          : const Color(0xFFE2DCD2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: isDark ? 0.85 : 0.95),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(height: 6),
            Text(
              isUnderheld
                  ? (isAr ? 'نقص: أطِل مد الصوت أكثر ↑' : 'Underheld: Hold sound longer ↑')
                  : isOverheld
                      ? (isAr ? 'زيادة: لا تبالغ في مد الصوت ↓' : 'Overheld: Avoid overextending sound ↓')
                      : (isAr ? 'المدة صحيحة ✓' : 'Duration is valid ✓'),
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
