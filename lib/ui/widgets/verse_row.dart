import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:recite_quran/recite_quran.dart';
import '../../services/quran_audio_service.dart';
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
  final bool? isAudioPlaying;
  final VoidCallback? onAudioPlayToggle;
  final void Function(int ayah, int wordIndex, Rect globalWordRect)?
      onActiveWordPositioned;

  const VerseRow({
    super.key,
    required this.verse,
    required this.controller,
    this.isRecording = false,
    required this.isAutoScrolling,
    this.onTap,
    this.onWordErrorTap,
    this.isAudioPlaying,
    this.onAudioPlayToggle,
    this.onActiveWordPositioned,
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
  bool _wasAudioActive = false;

  final List<TapGestureRecognizer> _recognizers = [];
  final GlobalKey _textKey = GlobalKey();
  bool _positionCheckScheduled = false;
  Timer? _delayedWordPositionTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    widget.controller.globalRevision.addListener(_onStateChanged);
    AppState.instance.addListener(_onStateChanged);
    AppState.instance.isAudioPlaying.addListener(_onAudioStateChanged);
    AppState.instance.activeAudioAyah.addListener(_onAudioStateChanged);
    AppState.instance.activeAudioSurah.addListener(_onAudioStateChanged);
    AppState.instance.activeAudioWordIndex.addListener(_onAudioWordChanged);
    _updateSubscription();
    _scheduleWordPositionCheck();
    _scheduleWordPositionCheck(delay: const Duration(milliseconds: 450));
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
      _scheduleWordPositionCheck();
    }
    if (oldWidget.isAudioPlaying != widget.isAudioPlaying) {
      _scheduleWordPositionCheck();
      setState(() {});
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
    AppState.instance.isAudioPlaying.removeListener(_onAudioStateChanged);
    AppState.instance.activeAudioAyah.removeListener(_onAudioStateChanged);
    AppState.instance.activeAudioSurah.removeListener(_onAudioStateChanged);
    AppState.instance.activeAudioWordIndex.removeListener(_onAudioWordChanged);
    _delayedWordPositionTimer?.cancel();
    _disposeRecognizers();
    super.dispose();
  }

  void _onAudioStateChanged() {
    final app = AppState.instance;
    final bool isAudioActive = (app.isAudioPlaying.value || QuranAudioService.instance.isPaused) &&
        app.activeAudioSurah.value == widget.verse.surah &&
        app.activeAudioAyah.value == widget.verse.ayah;
    if (isAudioActive != _wasAudioActive) {
      _wasAudioActive = isAudioActive;
      _invalidate();
      if (mounted) setState(() {});
    }
    _scheduleWordPositionCheck();
  }

  void _onAudioWordChanged() {
    final app = AppState.instance;
    final bool isAudioActive = (app.isAudioPlaying.value || QuranAudioService.instance.isPaused) &&
        app.activeAudioSurah.value == widget.verse.surah &&
        app.activeAudioAyah.value == widget.verse.ayah;
    if (isAudioActive) {
      _scheduleWordPositionCheck();
    }
  }

  void _onActiveAyahChanged() {
    _updateSubscription();
    _onStateChanged();
    _scheduleWordPositionCheck();
    _scheduleWordPositionCheck(delay: const Duration(milliseconds: 450));
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
            if (mounted) {
              setState(() {});
              _scheduleWordPositionCheck();
            }
          });
        } else {
          setState(() {});
          _scheduleWordPositionCheck();
        }
      }
    }
  }

  int _getActiveTargetIndex() {
    final app = AppState.instance;
    final surah = widget.verse.surah;
    final ayah = widget.verse.ayah;

    final bool isAudioActive = (app.isAudioPlaying.value || QuranAudioService.instance.isPaused) &&
        app.activeAudioSurah.value == surah &&
        app.activeAudioAyah.value == ayah;

    if (isAudioActive) {
      return app.activeAudioWordIndex.value ?? 0;
    }

    final activeMatch = widget.controller.currentMatchedVerse;
    final bool isRecitingActive = activeMatch != null &&
        activeMatch.verse.surah == surah &&
        activeMatch.verse.ayah == ayah;
    final bool isSelected = widget.controller.activeAyah.value == ayah;
    final bool isReciting = widget.isRecording && (isRecitingActive || isSelected);

    if (!isReciting) {
      return -1;
    }

    final words = widget.verse.uthmaniWords;
    int lastMatched = -1;
    for (int i = 0; i < words.length; i++) {
      if (widget.controller.isWordGreen(ayah, i) ||
          widget.controller.isWordRed(ayah, i) ||
          widget.controller.isWordYellow(ayah, i) ||
          widget.controller.isWordNeutral(ayah, i)) {
        lastMatched = i;
      }
    }

    // If words have been recited, track the current/most recent recited word.
    // If no word is recited yet in this active Ayah, focus is on index 0 (first word).
    return lastMatched >= 0 ? lastMatched : 0;
  }

  void _scheduleWordPositionCheck({Duration? delay}) {
    if (!mounted || widget.isAutoScrolling || widget.onActiveWordPositioned == null) {
      return;
    }

    if (delay != null) {
      _delayedWordPositionTimer?.cancel();
      _delayedWordPositionTimer = Timer(delay, () {
        if (!mounted) return;
        _checkActiveWordPosition();
      });
      return;
    }

    if (_positionCheckScheduled) return;
    _positionCheckScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionCheckScheduled = false;
      if (!mounted) return;
      _checkActiveWordPosition();
    });
  }

  void _checkActiveWordPosition() {
    if (!mounted || widget.isAutoScrolling || widget.onActiveWordPositioned == null) {
      return;
    }

    final targetIndex = _getActiveTargetIndex();
    if (targetIndex < 0) return;

    final textBox = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (textBox == null || !textBox.hasSize || !textBox.attached) return;

    final localRect = _calculateWordRect(targetIndex, textBox.size.width);
    if (localRect == null) return;

    final globalTopLeft = textBox.localToGlobal(localRect.topLeft);
    final globalBottomRight = textBox.localToGlobal(localRect.bottomRight);
    final globalRect = Rect.fromPoints(globalTopLeft, globalBottomRight);

    widget.onActiveWordPositioned?.call(
      widget.verse.ayah,
      targetIndex,
      globalRect,
    );
  }

  Rect? _calculateWordRect(int targetIndex, double maxWidth) {
    if (_cachedSpans == null ||
        targetIndex < 0 ||
        targetIndex >= widget.verse.uthmaniWords.length ||
        maxWidth <= 0) {
      return null;
    }

    final painter = TextPainter(
      text: TextSpan(children: _cachedSpans),
      textAlign: TextAlign.justify,
      textDirection: TextDirection.rtl,
    )..layout(minWidth: maxWidth, maxWidth: maxWidth);

    int charOffset = 0;
    final words = widget.verse.uthmaniWords;
    for (int i = 0; i < targetIndex; i++) {
      charOffset += words[i].length + 1;
    }

    final rects = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: charOffset,
        extentOffset: charOffset + words[targetIndex].length,
      ),
    );
    painter.dispose();

    if (rects.isEmpty) return null;
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

    return Rect.fromLTRB(left, top, right, bottom);
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
    final bool isAudioActive = (app.isAudioPlaying.value || QuranAudioService.instance.isPaused) &&
        app.activeAudioSurah.value == surah &&
        app.activeAudioAyah.value == ayah;
    final bool isActive = isRecitingActive || isSelected || isAudioActive;
    final bool isCompleted = ctrl.completedAyahs.contains(ayah);

    int hash = isActive ? 1 : 0;
    hash = hash * 31 + (isSelected ? 1 : 0);
    hash = hash * 31 + (isAudioActive ? 1 : 0);
    hash = hash * 31 + (isCompleted ? 1 : 0);
    hash = hash * 31 + (widget.isRecording ? 1 : 0);
    hash = hash * 31 + (app.activeAudioWordIndex.value ?? -1);

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
      ErrorDetailDialog.show(
        context,
        word: word,
        errors: errors,
        surah: widget.verse.surah,
        ayah: ayah,
        wordIndex: wordIdx,
      );
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
    final bool isAudioActive = (app.isAudioPlaying.value || QuranAudioService.instance.isPaused) &&
        app.activeAudioSurah.value == widget.verse.surah &&
        app.activeAudioAyah.value == widget.verse.ayah;
    final bool isActive = isRecitingActive || isSelected || isAudioActive;
    _wasAudioActive = isAudioActive;

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
        onWordAudioTap: (ayah, wordIdx) {
          widget.controller.setManualAyah(widget.verse.surah, ayah);
          QuranAudioService.instance.playWord(
            surah: widget.verse.surah,
            ayah: ayah,
            wordIndex: wordIdx,
          );
        },
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
              horizontal: 10,
              vertical: 3.5,
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
                    right: 8,
                    left: 26,
                    top: 6,
                    bottom: 6,
                  ),
                  child: CustomPaint(
                    painter: _cachedSpans != null &&
                            ((isActive && widget.isRecording) || isAudioActive)
                        ? _ActiveWordHighlightPainter(
                            words: words,
                            ayah: widget.verse.ayah,
                            controller: widget.controller,
                            app: app,
                            cachedSpans: _cachedSpans!,
                            isAudioMode: isAudioActive,
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
                      key: _textKey,
                      textAlign: TextAlign.justify,
                      textDirection: TextDirection.rtl,
                      text: TextSpan(children: _cachedSpans),
                    ),
                  ),
                ),

                // Injected Ayah number & audio play button pushed tightly to the outer edge
                Positioned(
                  left: 3,
                  bottom: 6,
                  width: 22,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!widget.isAutoScrolling) ...[
                        _VerseAudioButton(
                          surah: widget.verse.surah,
                          ayah: widget.verse.ayah,
                          colors: c,
                          isDark: app.isDarkMode,
                          isActiveVerse: isActive,
                          isRecording: widget.isRecording,
                          controller: widget.controller,
                          onTapVerse: widget.onTap,
                          explicitIsPlaying: widget.isAudioPlaying,
                          onExplicitToggle: widget.onAudioPlayToggle,
                        ),
                        const SizedBox(height: 1),
                      ],
                      Text(
                        _toArabicDigits(widget.verse.ayah),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'HafsSmart',
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? c.gold
                              : c.textSecondary.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
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

/// Injected minimal audio play/pause button located above the Ayah number.
///
/// Designed with:
/// - Zero disruption to verse layout & typography (fitted inside the 42px left margin).
/// - Eye-comfortable palettes adaptive to both White (Linen) and Black (OLED) themes.
/// - Fluid animated play/pause state ready for backend audio engine binding.
class _VerseAudioButton extends StatelessWidget {
  final int surah;
  final int ayah;
  final ThemeColors colors;
  final bool isDark;
  final bool isActiveVerse;
  final bool isRecording;
  final HighlightingController controller;
  final VoidCallback? onTapVerse;
  final bool? explicitIsPlaying;
  final VoidCallback? onExplicitToggle;

  const _VerseAudioButton({
    required this.surah,
    required this.ayah,
    required this.colors,
    required this.isDark,
    required this.isActiveVerse,
    required this.isRecording,
    required this.controller,
    this.onTapVerse,
    this.explicitIsPlaying,
    this.onExplicitToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (explicitIsPlaying != null) {
      return _buildButton(context, explicitIsPlaying!);
    }

    final app = AppState.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.activeAudioAyah,
        app.activeAudioSurah,
        app.isAudioPlaying,
        app.isAudioBuffering,
      ]),
      builder: (context, _) {
        final bool isThisAyah = app.activeAudioSurah.value == surah &&
            app.activeAudioAyah.value == ayah;
        final bool isPlaying = isThisAyah && app.isAudioPlaying.value;
        final bool isBuffering = isThisAyah && app.isAudioBuffering.value;
        return _buildButton(context, isPlaying, isBuffering: isBuffering);
      },
    );
  }

  Widget _buildButton(BuildContext context, bool isPlaying, {bool isBuffering = false}) {
    final Color iconColor;
    final Color bgColor;
    final Color borderColor;

    if (isPlaying || isBuffering) {
      // Active / Connecting state: Serene, dignified emerald accent across both themes
      if (isDark) {
        bgColor = colors.primary.withValues(alpha: 0.22);
        borderColor = colors.primary.withValues(alpha: 0.60);
        iconColor = colors.primary;
      } else {
        bgColor = colors.primary.withValues(alpha: 0.12);
        borderColor = colors.primary.withValues(alpha: 0.45);
        iconColor = colors.primary;
      }
    } else {
      // Idle state: Subtle, gentle, eye-comforting — never competing with the Quran text
      // (Kept neutral and never tinted gold, so only the Ayah number and card border highlight)
      if (isDark) {
        bgColor = colors.surfaceHigh.withValues(alpha: 0.35);
        borderColor = colors.border.withValues(alpha: 0.28);
        iconColor = colors.textSecondary.withValues(alpha: 0.60);
      } else {
        bgColor = colors.surfaceHigh.withValues(alpha: 0.50);
        borderColor = colors.border.withValues(alpha: 0.55);
        iconColor = colors.textSecondary.withValues(alpha: 0.65);
      }
    }

    return Semantics(
      button: true,
      label: isPlaying ? 'إيقاف مؤقت' : 'تشغيل التلاوة',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // If already attempting to connect/buffer this Ayah, ignore duplicate rapid tap
          if (AppState.instance.isAudioBuffering.value &&
              AppState.instance.activeAudioSurah.value == surah &&
              AppState.instance.activeAudioAyah.value == ayah) {
            return;
          }
          HapticFeedback.selectionClick();
          controller.setManualAyah(surah, ayah);
          onTapVerse?.call();
          if (onExplicitToggle != null) {
            onExplicitToggle!();
          } else {
            AppState.instance.toggleVerseAudio(
              surah: surah,
              ayah: ayah,
              continuous: !isRecording,
            );
          }
        },
        child: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 19.5,
              height: 19.5,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: 0.75,
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: isBuffering
                      ? SizedBox(
                          key: const ValueKey('buffering'),
                          width: 9.5,
                          height: 9.5,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.4,
                            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                          ),
                        )
                      : Padding(
                          key: ValueKey(isPlaying),
                          padding: EdgeInsets.only(left: isPlaying ? 0 : 0.8),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 11.5,
                            color: iconColor,
                          ),
                        ),
                ),
              ),
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
  final bool isAudioMode;

  _ActiveWordHighlightPainter({
    required this.words,
    required this.ayah,
    required this.controller,
    required this.app,
    required this.cachedSpans,
    this.isAudioMode = false,
  }) : super(repaint: isAudioMode ? Listenable.merge([app.activeAudioWordIndex, app.isAudioPlaying]) : null);

  @override
  void paint(Canvas canvas, Size size) {
    int targetIndex = -1;
    if (isAudioMode) {
      targetIndex = app.activeAudioWordIndex.value ?? -1;
    } else {
      for (int i = 0; i < words.length; i++) {
        if (!controller.isWordGreen(ayah, i) &&
            !controller.isWordRed(ayah, i) &&
            !controller.isWordYellow(ayah, i) &&
            !controller.isWordNeutral(ayah, i)) {
          targetIndex = i;
          break;
        }
      }
    }
    if (targetIndex < 0 || targetIndex >= words.length) return;

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
    return oldDelegate.ayah != ayah ||
        oldDelegate.cachedSpans != cachedSpans ||
        oldDelegate.isAudioMode != isAudioMode;
  }
}

