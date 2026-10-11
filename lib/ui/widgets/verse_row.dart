import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';
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
  bool _isListeningToController = false;

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
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
    final bool isRecitingActive =
        activeMatch != null &&
        activeMatch.verse.surah == surah &&
        activeMatch.verse.ayah == ayah;
    final bool isSelected = ctrl.activeAyah.value == ayah;
    final bool isActive = isRecitingActive || isSelected;
    final bool isCompleted = ctrl.completedAyahs.contains(ayah);

    int hash = isActive ? 1 : 0;
    hash = hash * 31 + (isSelected ? 1 : 0);
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
    return number.toString().split('').map((e) => digits[int.parse(e)]).join('');
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = AppState.instance;
    final ThemeColors c = app.colors;
    final words = widget.verse.uthmaniWords;
    final activeMatch = widget.controller.currentMatchedVerse;
    final bool isRecitingActive =
        activeMatch != null &&
        activeMatch.verse.surah == widget.verse.surah &&
        activeMatch.verse.ayah == widget.verse.ayah;
    final bool isSelected = widget.controller.activeAyah.value == widget.verse.ayah;
    final bool isActive = isRecitingActive || isSelected;

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
        onTap: widget.isAutoScrolling ? null : () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? c.gold.withValues(alpha: app.isDarkMode ? 0.70 : 0.60)
                    : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    right: 12,
                    left: 42,
                    top: 8,
                    bottom: 8,
                  ),
                  child: CustomPaint(
                    painter: _cachedSpans != null && isActive && widget.isRecording
                        ? _ActiveWordHighlightPainter(
                            words: words,
                            ayah: widget.verse.ayah,
                            controller: widget.controller,
                            app: app,
                            cachedSpans: _cachedSpans!,
                          )
                        : null,
                    foregroundPainter: _cachedSpans != null && !app.hasClickedTajweedWord
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
                ),

                // Fixed Ayah number at bottom left of the card
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: Text(
                    _toArabicDigits(widget.verse.ayah),
                    style: TextStyle(
                      fontFamily: 'HafsSmart',
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? c.gold
                          : c.textSecondary.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

    final bool isBlack = app.isDarkMode;

    // Eye-comfortable color specifically adapted to Black vs White modes:
    // Soothing serene teal/cyan that eliminates harsh/dirty gold glare, provides
    // maximum eye comfort, and creates a tranquil focus aura.
    final Color highlightColor = app.colors.wordHighlight;

    // Slight, delicate opacity tuned for effortless readability without eye strain:
    final double opacity = isBlack ? 0.12 : 0.085;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(left - 4.0, top - 2.5, right + 4.0, bottom + 2.5),
      const Radius.circular(8),
    );

    final paint = Paint()
      ..color = highlightColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rrect, paint);
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _ActiveWordHighlightPainter oldDelegate) {
    return oldDelegate.ayah != ayah || oldDelegate.cachedSpans != cachedSpans;
  }
}

