import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../services/ayah_audio_service.dart';
import '../../state/app_state.dart';
import 'dialogs/error_detail_dialog.dart';
import 'helpers/verse_span_builder.dart';
import 'tajweed_tutorial_word.dart';

/// Displays a single Quranic verse (Ayah) with word-by-word highlighting.
///
/// Features:
/// - Fingerprint-based diffing for near-zero CPU / 60 FPS scrolling.
/// - Selective listener attachment (only active + adjacent Ayahs subscribe to ASR frames).
/// - Modular TextSpan rendering via [VerseSpanBuilder].
/// - Interactive Tajweed error breakdown via [ErrorDetailDialog].
class VerseRow extends StatefulWidget {
  final QuranVerse verse;
  final HighlightingController controller;
  final bool isRecording;
  final bool isAutoScrolling;
  final VoidCallback? onTap;
  final VoidCallback? onWordErrorTap;

  const VerseRow({
    super.key,
    required this.verse,
    required this.controller,
    this.isRecording = false,
    required this.isAutoScrolling,
    this.onTap,
    this.onWordErrorTap,
  });

  @override
  State<VerseRow> createState() => _VerseRowState();
}

class _VerseRowState extends State<VerseRow> {
  /// Cached fingerprint — only rebuilds when visual state changes.
  int _lastFingerprint = -1;

  /// Cached TextSpan list — avoids re-allocating on every build.
  List<InlineSpan>? _cachedSpans;
  late String _ayahArabicDigits;
  bool _isListeningToController = false;

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _ayahArabicDigits = _toArabicDigits(widget.verse.ayah);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    widget.controller.globalRevision.addListener(_onStateChanged);
    AppState.instance.addListener(_onStateChanged);
    _updateSubscription();
  }

  @override
  void didUpdateWidget(VerseRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.activeAyah.removeListener(_onActiveAyahChanged);
      oldWidget.controller.globalRevision.removeListener(_onStateChanged);
      if (_isListeningToController) {
        oldWidget.controller.removeListener(_onStateChanged);
      }
      widget.controller.activeAyah.addListener(_onActiveAyahChanged);
      widget.controller.globalRevision.addListener(_onStateChanged);
      _isListeningToController = false;
      _updateSubscription();
      _invalidate();
    }
    if (oldWidget.isAutoScrolling != widget.isAutoScrolling) {
      _invalidate();
      _onStateChanged();
    }
    if (oldWidget.isRecording != widget.isRecording) {
      _invalidate();
      _onStateChanged();
    }
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    widget.controller.globalRevision.removeListener(_onStateChanged);
    if (_isListeningToController) {
      widget.controller.removeListener(_onStateChanged);
    }
    AppState.instance.removeListener(_onStateChanged);
    _disposeRecognizers();
    super.dispose();
  }

  void _onActiveAyahChanged() {
    _updateSubscription();
    _onStateChanged();
  }

  void _updateSubscription() {
    final int? active = widget.controller.activeAyah.value;
    final int myAyah = widget.verse.ayah;

    // Listen to highlights if we are the active, preceding, or upcoming Ayah
    bool shouldListen = false;
    if (active != null) {
      if (myAyah == active || myAyah == active - 1 || myAyah == active + 1) {
        shouldListen = true;
      }
    }
    if (shouldListen && !_isListeningToController) {
      widget.controller.addListener(_onStateChanged);
      _isListeningToController = true;
    } else if (!shouldListen && _isListeningToController) {
      widget.controller.removeListener(_onStateChanged);
      _isListeningToController = false;
    }
  }

  void _invalidate() {
    _lastFingerprint = -1;
    _cachedSpans = null;
  }

  void _onStateChanged() {
    final fp = _computeFingerprint();
    if (fp != _lastFingerprint) {
      _lastFingerprint = fp;
      _cachedSpans = null;
      if (mounted) {
        if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        } else {
          setState(() {});
        }
      }
    }
  }

  /// Compact hash representing active state, word colors, blur, theme, and font size.
  int _computeFingerprint() {
    final ctrl = widget.controller;
    final app = AppState.instance;
    final ayah = widget.verse.ayah;
    final surah = widget.verse.surah;
    final activeMatch = ctrl.currentMatchedVerse;
    final bool isActive =
        activeMatch != null &&
        activeMatch.verse.surah == surah &&
        activeMatch.verse.ayah == ayah;
    final bool isCompleted = ctrl.completedAyahs.contains(ayah);

    int hash = isActive ? 1 : 0;
    hash = hash * 31 + (isCompleted ? 1 : 0);
    hash = hash * 31 + (widget.isRecording ? 1 : 0);

    final wordCount = widget.verse.uthmaniWords.length;
    for (int i = 0; i < wordCount; i++) {
      if (ctrl.isWordGreen(ayah, i)) hash = hash * 31 + (i + 1) * 7;
      if (ctrl.isWordRed(ayah, i)) hash = hash * 31 + (i + 1) * 13;
      if (ctrl.isWordYellow(ayah, i)) hash = hash * 31 + (i + 1) * 17;
    }

    hash = hash * 31 + (app.isBlurMode ? 1 : 0);
    hash = hash * 31 + (app.isBlurMode && widget.isAutoScrolling ? 1 : 0);
    hash = hash * 31 + app.fontSize.hashCode;
    hash = hash * 31 + app.theme.index;
    hash = hash * 31 + (app.hasClickedTajweedWord ? 1 : 0);

    hash = hash * 31 + (widget.isAutoScrolling ? 1 : 0);

    return hash;
  }

  void _handleWordErrorTap(int ayah, int wordIdx, String word) {
    AppState.instance.markTajweedWordClicked();
    final errors = widget.controller.getWordErrors(ayah, wordIdx);
    if (errors != null && errors.isNotEmpty) {
      ErrorDetailDialog.show(context, word: word, errors: errors);
      widget.onWordErrorTap?.call();
    }
  }

  static String _toArabicDigits(int number) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((e) => digits[int.parse(e)])
        .join('');
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.instance;
    final ThemeColors c = app.colors;
    final words = widget.verse.uthmaniWords;
    final activeMatch = widget.controller.currentMatchedVerse;
    final bool isActive =
        activeMatch != null &&
        activeMatch.verse.surah == widget.verse.surah &&
        activeMatch.verse.ayah == widget.verse.ayah;

    if (_cachedSpans == null) {
      _disposeRecognizers();
      _cachedSpans = VerseSpanBuilder.buildSpans(
        words: words,
        ayah: widget.verse.ayah,
        isActive: isActive,
        isAutoScrolling: widget.isAutoScrolling,
        controller: widget.controller,
        app: app,
        colors: c,
        recognizersSink: _recognizers,
        onVerseTap: widget.onTap,
        onWordErrorTap: _handleWordErrorTap,
      );
    }

    return ExcludeSemantics(
      child: GestureDetector(
        onTap: widget.isAutoScrolling ? null : widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: CustomPaint(
            painter: _ActiveAyahBorderPainter(
              isActive: isActive,
              outerColor: c.ayahOutline,
              innerColor: c.gold.withValues(alpha: app.isDarkMode ? 0.10 : 0.05),
              isDark: app.isDarkMode,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // ── Verse Text ──
              CustomPaint(
                painter: _cachedSpans != null && isActive && widget.isRecording
                    ? _ActiveWordHighlightPainter(
                        words: words,
                        ayah: widget.verse.ayah,
                        controller: widget.controller,
                        app: app,
                        cachedSpans: _cachedSpans!,
                      )
                    : null,
                foregroundPainter: _cachedSpans != null
                    ? TajweedTooltipPainter(
                        words: words,
                        ayah: widget.verse.ayah,
                        controller: widget.controller,
                        app: app,
                        cachedSpans: _cachedSpans!,
                      )
                    : null,
                child: RichText(
                  textAlign: TextAlign.justify,
                  textDirection: TextDirection.rtl,
                  text: TextSpan(children: _cachedSpans),
                ),
              ),

              // ── Ayah Number Badge & Audio Play Button ──
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _ayahArabicDigits,
                        style: TextStyle(
                          fontFamily: 'HafsSmart',
                          fontSize: app.fontSize * 0.75,
                          fontWeight: FontWeight.w600,
                          color: isActive ? c.gold : c.muted.withValues(alpha: 0.6),
                        ),
                      ),
                      // Non-distracting play button: hidden in Read Mode (auto-scroll) and during recording
                      if (!widget.isAutoScrolling && !widget.isRecording) ...[
                        const SizedBox(width: 8),
                        _AyahPlayButton(
                          surah: widget.verse.surah,
                          ayah: widget.verse.ayah,
                          colors: c,
                          isDarkMode: app.isDarkMode,
                          isArabic: app.isArabic,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }
}

/// Compact, reverent, non-distracting audio button for Sheikh Al-Husary recitation.
/// Automatically converts into an eye-friendly Stop button when active with 0ms lag.
/// Uses [ListenableBuilder] to isolate updates to this 24x24 button with zero parent rebuilds.
class _AyahPlayButton extends StatelessWidget {
  final int surah;
  final int ayah;
  final ThemeColors colors;
  final bool isDarkMode;
  final bool isArabic;

  const _AyahPlayButton({
    required this.surah,
    required this.ayah,
    required this.colors,
    required this.isDarkMode,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AyahAudioService.instance,
      builder: (context, _) {
        final audio = AyahAudioService.instance;
        final bool isActive = audio.isAyahActive(surah, ayah);

        // Completely non-distracting button design:
        // Maintains the calm, neutral frame of the card so peripheral vision is never drawn away.
        final Color activeMutedGold = Color.lerp(
          colors.muted,
          colors.gold,
          0.25,
        )!.withValues(alpha: isDarkMode ? 0.68 : 0.62);

        final Color iconColor = isActive
            ? activeMutedGold
            : colors.muted.withValues(alpha: 0.50);

        final Color bgColor = colors.surfaceHigh.withValues(
          alpha: isDarkMode ? 0.35 : 0.50,
        );

        final Color borderColor = colors.border.withValues(
          alpha: isDarkMode ? 0.25 : 0.40,
        );

        return Semantics(
          label: isActive
              ? (isArabic ? 'إيقاف التلاوة' : 'Stop recitation')
              : (isArabic ? 'استماع للآية' : 'Play Ayah'),
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              if (isActive) {
                audio.stop();
              } else {
                audio.playAyah(surah, ayah);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 0.9),
              ),
              child: Center(
                child: Icon(
                  isActive
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  size: isActive ? 10.5 : 13,
                  color: iconColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints a tight, rounded background pill behind the current active target word.
/// Fits the word's actual font bounds instead of the entire line height.
class _ActiveWordHighlightPainter extends CustomPainter {
  final List<String> words;
  final int ayah;
  final HighlightingController controller;
  final AppState app;
  final List<InlineSpan> cachedSpans;

  _ActiveWordHighlightPainter({
    required this.words,
    required this.ayah,
    required this.controller,
    required this.app,
    required this.cachedSpans,
  });

  @override
  void paint(Canvas canvas, Size size) {
    int targetIndex = -1;
    for (int i = 0; i < words.length; i++) {
      if (!controller.isWordGreen(ayah, i) &&
          !controller.isWordRed(ayah, i) &&
          !controller.isWordYellow(ayah, i) &&
          !controller.isWordNeutral(ayah, i)) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex == -1) return;

    final painter = TextPainter(
      text: TextSpan(children: cachedSpans),
      textAlign: TextAlign.justify,
      textDirection: TextDirection.rtl,
    )..layout(minWidth: size.width, maxWidth: size.width);

    int charOffset = 0;
    for (int i = 0; i < targetIndex; i++) {
      charOffset += words[i].length + 1;
    }

    final rects = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: charOffset,
        extentOffset: charOffset + words[targetIndex].length,
      ),
    );
    if (rects.isEmpty) return;

    final paint = Paint()
      ..color = app.colors.gold.withValues(alpha: app.isDarkMode ? 0.20 : 0.14)
      ..style = PaintingStyle.fill;

    double left = rects.first.left;
    double right = rects.first.right;
    double top = rects.first.top;
    double bottom = rects.first.bottom;

    for (int k = 1; k < rects.length; k++) {
      final r = rects[k];
      if (r.left < left) left = r.left;
      if (r.right > right) right = r.right;
      if (r.top < top) top = r.top;
      if (r.bottom > bottom) bottom = r.bottom;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left - 3, top - 2, right + 3, bottom + 2),
        const Radius.circular(6),
      ),
      paint,
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _ActiveWordHighlightPainter oldDelegate) {
    return oldDelegate.ayah != ayah || oldDelegate.cachedSpans != cachedSpans;
  }

  @override
  bool shouldRebuildSemantics(covariant _ActiveWordHighlightPainter oldDelegate) => false;
}

/// Renders a crisp outer outline along the Ayah card boundary and an inner stroke
/// with lighter opacity immediately inside it. Zero background color fill.
class _ActiveAyahBorderPainter extends CustomPainter {
  final bool isActive;
  final Color outerColor;
  final Color innerColor;
  final bool isDark;

  const _ActiveAyahBorderPainter({
    required this.isActive,
    required this.outerColor,
    required this.innerColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive || size.isEmpty) return;

    final rrectOuter = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );

    // 1. Subtle, slim inward stroke: glowing halo in dark mode, clean crisp gilded stroke in light mode
    canvas.save();
    canvas.clipRRect(rrectOuter);
    final innerGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isDark ? 5.0 : 2.0
      ..color = innerColor
      ..maskFilter = isDark
          ? const MaskFilter.blur(BlurStyle.normal, 1.8)
          : null;
    canvas.drawRRect(rrectOuter, innerGlowPaint);
    canvas.restore();

    // 2. Crisp, delicate outer boundary line
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = outerColor;
    canvas.drawRRect(rrectOuter, outerPaint);
  }

  @override
  bool shouldRepaint(covariant _ActiveAyahBorderPainter oldDelegate) {
    return oldDelegate.isActive != isActive ||
        oldDelegate.outerColor != outerColor ||
        oldDelegate.innerColor != innerColor ||
        oldDelegate.isDark != isDark;
  }
}
