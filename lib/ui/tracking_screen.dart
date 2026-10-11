import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:recite_quran/recite_quran.dart';
import '../state/app_state.dart';
import 'widgets/dialogs/voice_search_dialog.dart';
import 'widgets/mic_bar.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/surah_picker.dart';
import 'widgets/verse_row.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/dialogs/speed_selection_dialog.dart';

/// Main interactive screen for real-time recitation tracking and reading.
/// Manages scrolling, distraction-free reading headers, and mode switches.
class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final String voiceSearchText;
  final ValueListenable<String>? voiceSearchTextNotifier;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;
  final bool isLoadingEngine;
  final ValueNotifier<bool>? isVoiceSearchLoading;
  final VoiceSearchController? voiceSearchController;
  final void Function(int surah, int ayah)? onSelectVoiceCandidate;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    this.voiceSearchText = '',
    this.voiceSearchTextNotifier,
    this.voiceSearchController,
    this.onSelectVoiceCandidate,
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
    this.isLoadingEngine = false,
    this.isVoiceSearchLoading,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final ListController _listController = ListController();
  final Map<int, GlobalKey> _keys = {};
  final ValueNotifier<String> _voiceSearchNotifier = ValueNotifier('');

  int? _lastAyah;
  int? _lastSurah;
  bool _isAutoScrolling = false;

  bool _showTajweedBanner = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      try {
        WakelockPlus.enable();
      } catch (_) {}
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (widget.isRecording) {
        widget.onToggleRecord();
      }
      if (widget.isVoiceSearching) {
        widget.onVoiceSearchToggle();
      }
      if (_isAutoScrolling) {
        _toggleAutoScroll();
      }
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      try {
        WakelockPlus.disable();
      } catch (_) {}
    }
    widget.controller.removeListener(_onControllerUpdate);
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    _scroll.dispose();
    _voiceSearchNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _lastAyah = null;
      final match = widget.controller.currentMatchedVerse;
      if (match != null && match.verse.surah == widget.controller.targetSurah) {
        _forceScrollToAyah(match.verse.ayah);
      }
    }

    if (widget.isVoiceSearching && !oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          VoiceSearchDialog.show(
            context,
            onStop: widget.onVoiceSearchToggle,
            isLoading: widget.isVoiceSearchLoading,
            asrTextNotifier:
                widget.voiceSearchTextNotifier ?? _voiceSearchNotifier,
            searchResultNotifier: widget.voiceSearchController?.currentResult,
            onSelectCandidate: widget.onSelectVoiceCandidate,
          );
        }
      });
    } else if (!widget.isVoiceSearching && oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _onControllerUpdate() {
    if (widget.controller.targetSurah != _lastSurah) {
      void applyUpdate() {
        if (!mounted) return;
        setState(() {
          _lastSurah = widget.controller.targetSurah;
          _keys.clear();
          _lastAyah = null;
        });

        if (_scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      }

      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => applyUpdate());
      } else {
        applyUpdate();
      }
    }
  }

  void _onActiveAyahChanged() {
    final active = widget.controller.activeAyah.value;
    final match = widget.controller.currentMatchedVerse;
    if (active != null &&
        active != _lastAyah &&
        match != null &&
        match.verse.surah == widget.controller.targetSurah) {
      _lastAyah = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _forceScrollToAyah(active);
        }
      });
    }
  }

  void _forceScrollToAyah(int ayah) {
    if (!_scroll.hasClients) return;

    if (ayah == 1) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _listController.jumpToItem(
      index: ayah,
      scrollController: _scroll,
      alignment: 0.5,
    );
  }

  void _toggleAutoScroll() async {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.pixels);
      }
      if (!kIsWeb) {
        try {
          WakelockPlus.disable();
        } catch (_) {}
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final hasChosenSpeed = prefs.getBool('has_chosen_speed') ?? false;
      if (!hasChosenSpeed && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => SpeedSelectionDialog(
            onSpeedSelected: () {
              prefs.setBool('has_chosen_speed', true);
              Navigator.of(ctx).pop();
              _toggleAutoScroll();
            },
          ),
        );
        return;
      }

      widget.controller.clearHighlights();
      widget.controller.finalize();
      setState(() => _isAutoScrolling = true);
      _startAutoScrollLoop();
      if (!kIsWeb) {
        try {
          WakelockPlus.enable();
        } catch (_) {}
      }
    }
  }

  void _startAutoScrollLoop() {
    if (!_isAutoScrolling || !mounted || !_scroll.hasClients) return;

    double baseSpeed =
        ((AppState.instance.fontSize / 24.0) * 1.5) * (16.0 / 50.0);
    const speedMultipliers = [0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0];
    int speedIndex = AppState.instance.autoScrollSpeed.clamp(
      0,
      speedMultipliers.length - 1,
    );
    double speedPerFrame = baseSpeed * speedMultipliers[speedIndex];
    final double pixelsPerSec = speedPerFrame * 60;

    final position = _scroll.position;
    final distance = position.maxScrollExtent - position.pixels;

    if (distance <= 0.5) {
      setState(() => _isAutoScrolling = false);
      if (!kIsWeb) {
        try {
          WakelockPlus.disable();
        } catch (_) {}
      }
      return;
    }

    final durationSeconds = distance / pixelsPerSec;

    _scroll
        .animateTo(
      position.maxScrollExtent,
      duration: Duration(milliseconds: (durationSeconds * 1000).toInt()),
      curve: Curves.linear,
    )
        .then((_) {
      if (mounted && _isAutoScrolling) {
        if (_scroll.hasClients &&
            (_scroll.position.maxScrollExtent - _scroll.position.pixels) >
                2.0) {
          _startAutoScrollLoop();
        } else {
          setState(() => _isAutoScrolling = false);
          if (!kIsWeb) {
            try {
              WakelockPlus.disable();
            } catch (_) {}
          }
        }
      }
    });
  }

  void _showSurahPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SurahPickerSheet(
        current: widget.controller.targetSurah,
        controller: widget.controller,
        isRecording: widget.isRecording,
        isVoiceSearching: widget.isVoiceSearching,
        onToggleRecord: widget.onToggleRecord,
        onVoiceSearchToggle: widget.onVoiceSearchToggle,
        onPick: (n, {ayah}) async {
          if (widget.isRecording) {
            widget.onToggleRecord();
          }
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
          if (_scroll.hasClients) {
            _scroll.jumpTo(0);
          }

          await widget.controller.setTargetSurah(n);
          if (ayah != null) {
            widget.controller.setManualAyah(n, ayah);
          }

          setState(() {
            _keys.clear();
            _lastAyah = null;
          });
        },
      ),
    );
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SettingsDialog(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: app,
      builder: (context, child) {
        final c = app.colors;

        return Directionality(
          textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: c.bg,
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Main Verse Content
                Positioned.fill(child: _buildVerseContent(c, app, top)),

                // Top Floating Header
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: _buildHeader(c, app, top),
                  ),
                ),

                // Bottom Action Bar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: BottomActionBar(
                      key: const ValueKey('word_checker_bar'),
                      isRecording: widget.isRecording,
                      isLoadingEngine: widget.isLoadingEngine,
                      isAutoScrolling: _isAutoScrolling,
                      c: c,
                      onMic: () {
                        if (_showTajweedBanner)
                          setState(() => _showTajweedBanner = false);
                        if (widget.isVoiceSearching) {
                          widget.onVoiceSearchToggle();
                        } else {
                          widget.onToggleRecord();
                        }
                      },
                      onToggleAutoScroll: () {
                        if (_showTajweedBanner)
                          setState(() => _showTajweedBanner = false);
                        _toggleAutoScroll();
                      },
                      onSettingsTap: _showSettingsDialog,
                      isTajweed: app.currentMode == AppMode.tajweed,
                      onToggleTajweed: () {
                        final bool newIsTajweed =
                            app.currentMode != AppMode.tajweed;
                        if (newIsTajweed) {
                          app.setMode(AppMode.tajweed);
                          widget.controller.setTajweedMode(true);
                          ScaffoldMessenger.of(context).clearSnackBars();
                          setState(() => _showTajweedBanner = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted)
                              setState(() => _showTajweedBanner = false);
                          });
                        } else {
                          app.setMode(AppMode.wordChecker);
                          widget.controller.setTajweedMode(false);
                          if (_showTajweedBanner) {
                            setState(() => _showTajweedBanner = false);
                          }
                        }
                      },
                      isBlur: app.isBlurMode,
                      onToggleBlur: () {
                        app.toggleBlurMode();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeColors c, AppState app, double top) {
    if (widget.isRecording || _isAutoScrolling) {
      return const SizedBox.shrink(key: ValueKey('header_hidden'));
    }

    return Padding(
      key: const ValueKey('header_main'),
      padding: EdgeInsetsDirectional.only(
        top: top + 10,
        start: 14,
        end: 14,
        bottom: 8,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Dropdown Banner
          AnimatedPositioned(
            duration: Duration(milliseconds: _showTajweedBanner ? 600 : 300),
            curve: _showTajweedBanner ? Curves.elasticOut : Curves.easeOutCubic,
            top: _showTajweedBanner
                ? 54
                : 0, // Slides out from beneath the container
            left: 16,
            right: 16,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _showTajweedBanner ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.only(
                    top: 16, bottom: 8, left: 12, right: 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                  border: Border(
                    bottom: BorderSide(color: c.gold.withValues(alpha: 0.3)),
                    left: BorderSide(color: c.gold.withValues(alpha: 0.3)),
                    right: BorderSide(color: c.gold.withValues(alpha: 0.3)),
                  ),
                ),
                child: Text(
                  app.isArabic
                      ? 'تم تفعيل التجويد و يمكنك الضغط على الكلمات باللون الاصفر لمعرفة نوع الخطأ'
                      : 'Tajweed Enabled. Tap on yellow words to see error details.',
                  style: TextStyle(
                      color: c.text,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  textAlign: TextAlign.center,
                  textDirection:
                      app.isArabic ? TextDirection.rtl : TextDirection.ltr,
                ),
              ),
            ),
          ),

          // The Actual Header Container
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: c.glassSurface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: app.isDarkMode
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.black.withValues(alpha: 0.12),
                    width: 0.9,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: app.isDarkMode ? 0.35 : 0.06),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // ── 1. 2026 Surah Selector — Clean Frosted Capsule ──
                    Expanded(
                      child: _TactileScaleButton(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _showSurahPicker();
                        },
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: app.isDarkMode
                                ? Colors.white.withValues(alpha: 0.06)
                                : c.surfaceHigh.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: app.isDarkMode
                                  ? Colors.white.withValues(alpha: 0.10)
                                  : c.border.withValues(alpha: 0.55),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Mini emerald icon badge
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: c.primary.withValues(alpha: app.isDarkMode ? 0.18 : 0.10),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.menu_book_rounded,
                                  color: c.primary,
                                  size: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Builder(
                                  builder: (context) {
                                    final displayVerses =
                                        widget.controller.repository.getSurah(
                                            widget.controller.targetSurah);
                                    return Text(
                                      app.isArabic
                                          ? (displayVerses.isNotEmpty
                                              ? displayVerses.first.surahName
                                              : '')
                                          : (displayVerses.isNotEmpty
                                              ? displayVerses.first.surahNameEn
                                              : ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily:
                                            app.isArabic ? 'HafsSmart' : null,
                                        color: c.text,
                                        fontSize: app.isArabic ? 16 : 14.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: c.textSecondary.withValues(alpha: 0.65),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // ── 2. Read (Auto-Scroll) Action Button ──
                    _buildIconActionButton(
                      icon: _isAutoScrolling
                          ? Icons.pause_rounded
                          : Icons.auto_stories_rounded,
                      isActive: _isAutoScrolling,
                      c: c,
                      tooltip: app.isArabic
                          ? (_isAutoScrolling
                              ? 'إيقاف التمرير'
                              : 'قراءة تلقائية')
                          : (_isAutoScrolling
                              ? 'Pause Reading'
                              : 'Auto-scroll Read'),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        if (_showTajweedBanner) {
                          setState(() => _showTajweedBanner = false);
                        }
                        _toggleAutoScroll();
                      },
                    ),

                    const SizedBox(width: 4),

                    // ── 3. Voice Search Action Button (Small Toolbar Icon) ──
                    _buildIconActionButton(
                      icon: Icons.graphic_eq_rounded,
                      isActive: widget.isVoiceSearching,
                      c: c,
                      tooltip: app.isArabic ? 'بحث صوتي' : 'Voice Search',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (_showTajweedBanner) {
                          setState(() => _showTajweedBanner = false);
                        }
                        widget.onVoiceSearchToggle();
                      },
                    ),

                    const SizedBox(width: 4),

                    // ── 4. Settings Action ──
                    _buildIconActionButton(
                      icon: Icons.settings_rounded,
                      isActive: false,
                      c: c,
                      tooltip: app.isArabic ? 'الإعدادات' : 'Settings',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showSettingsDialog();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconActionButton({
    required IconData icon,
    required bool isActive,
    required ThemeColors c,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final bool isDark = AppState.instance.isDarkMode;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: _TactileScaleButton(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? c.primary.withValues(alpha: isDark ? 0.22 : 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isActive
                  ? c.primary.withValues(alpha: isDark ? 0.50 : 0.38)
                  : Colors.transparent,
              width: 0.85,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: c.primary.withValues(alpha: isDark ? 0.28 : 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isActive ? c.primary : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildVerseContent(ThemeColors c, AppState app, double top) {
    return Builder(
      key: const ValueKey('verse_list_content'),
      builder: (context) {
        final displayVerses = widget.controller.repository.getSurah(
          widget.controller.targetSurah,
        );

        final bool isFullscreenMode = widget.isRecording || _isAutoScrolling;
        final topPadding = isFullscreenMode ? top + 10.0 : top + 74.0;
        final bottomPadding = isFullscreenMode ? 40.0 : 88.0;

        return CustomScrollView(
          controller: _scroll,
          physics: _isAutoScrolling
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          slivers: [
            SuperSliverList(
              listController: _listController,
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  if (i == 0) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      height: topPadding,
                    );
                  }

                  if (i == displayVerses.length + 2) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      height: bottomPadding,
                    );
                  }

                  if (i == displayVerses.length + 1) {
                    return _buildEndOfSurahSection(c, app);
                  }

                  final v = displayVerses[i - 1];

                  return RepaintBoundary(
                    child: VerseRow(
                      key: ValueKey('verse_${v.surah}_${v.ayah}'),
                      verse: v,
                      controller: widget.controller,
                      isRecording: widget.isRecording,
                      isAutoScrolling: _isAutoScrolling,
                      onTap: () {
                        widget.controller.setManualAyah(v.surah, v.ayah);
                      },
                      onWordErrorTap: null,
                    ),
                  );
                },
                childCount: displayVerses.length + 3,
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToSurah(int newSurah) async {
    if (newSurah < 1 || newSurah > 114) return;
    HapticFeedback.mediumImpact();

    if (widget.isRecording) {
      widget.onToggleRecord();
    }
    if (_isAutoScrolling) {
      _toggleAutoScroll();
    }
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }

    await widget.controller.setTargetSurah(newSurah);

    if (mounted) {
      setState(() {
        _keys.clear();
        _lastAyah = null;
      });
    }
  }

  void _scrollToTop() {
    HapticFeedback.lightImpact();
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 2026 End-of-Surah Navigation Section:
  /// - Minimalist 3-button navigation capsule (Previous, Go to Top, Next).
  /// - Exact theme and color token conformity. Zero scroll overhead.
  Widget _buildEndOfSurahSection(ThemeColors c, AppState app) {
    final int currentSurah = widget.controller.targetSurah;
    final bool hasPrev = currentSurah > 1;
    final bool hasNext = currentSurah < 114;
    final bool isAr = app.isArabic;
    final bool isDark = app.isDarkMode;

    final metadataList = widget.controller.repository.surahMetadata;
    final prevMeta = hasPrev ? metadataList[currentSurah - 2] : null;
    final nextMeta = hasNext ? metadataList[currentSurah] : null;

    // Outer-edge directional chevrons:
    // Left side of screen always points left (<)
    // Right side of screen always points right (>)
    final IconData prevIcon =
        isAr ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    final IconData nextIcon =
        isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;

    return Padding(
      padding: const EdgeInsets.only(top: 64, bottom: 8, left: 16, right: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Container(
            height: 50,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? c.surfaceHigh.withValues(alpha: 0.75)
                  : c.surfaceHigh.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : c.border.withValues(alpha: 0.60),
                width: 0.85,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Child 0: Visual Left in LTR (Previous), Visual Right in RTL (السابقة)
                Expanded(
                  child: _buildSurahNavButton(
                    icon: prevIcon,
                    label: isAr ? 'السابقة' : 'Previous',
                    hint: prevMeta != null
                        ? (isAr ? prevMeta.surahName : prevMeta.surahNameEn)
                        : null,
                    isEnabled: hasPrev,
                    iconOnLeft: !isAr,
                    c: c,
                    isDark: isDark,
                    onTap: () => _navigateToSurah(currentSurah - 1),
                  ),
                ),

                // Subtle Vertical Divider
                Container(
                  width: 1,
                  height: 24,
                  color: (isDark ? Colors.white : c.border).withValues(alpha: 0.15),
                ),

                // Scroll to Top (Go Up) Center Button (NO default highlight)
                Expanded(
                  child: _buildSurahNavButton(
                    icon: Icons.arrow_upward_rounded,
                    label: isAr ? 'للأعلى' : 'Top',
                    hint: null,
                    isEnabled: true,
                    iconOnLeft: false,
                    c: c,
                    isDark: isDark,
                    onTap: _scrollToTop,
                  ),
                ),

                // Subtle Vertical Divider
                Container(
                  width: 1,
                  height: 24,
                  color: (isDark ? Colors.white : c.border).withValues(alpha: 0.15),
                ),

                // Child 2: Visual Right in LTR (Next), Visual Left in RTL (التالية)
                Expanded(
                  child: _buildSurahNavButton(
                    icon: nextIcon,
                    label: isAr ? 'التالية' : 'Next',
                    hint: nextMeta != null
                        ? (isAr ? nextMeta.surahName : nextMeta.surahNameEn)
                        : null,
                    isEnabled: hasNext,
                    iconOnLeft: isAr,
                    c: c,
                    isDark: isDark,
                    onTap: () => _navigateToSurah(currentSurah + 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSurahNavButton({
    required IconData icon,
    required String label,
    required String? hint,
    required bool isEnabled,
    required bool iconOnLeft,
    required ThemeColors c,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final Color textColor =
        !isEnabled ? c.muted.withValues(alpha: 0.35) : c.text;
    final Color iconColor =
        !isEnabled ? c.muted.withValues(alpha: 0.35) : c.textSecondary;

    final Widget iconWidget = Icon(icon, size: 18, color: iconColor);
    final Widget textWidget = Text(
      label,
      style: TextStyle(
        fontFamily: null,
        fontSize: 12.0,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.0,
      ),
    );

    final Widget content = Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: iconOnLeft
              ? [
                  iconWidget,
                  const SizedBox(width: 4),
                  textWidget,
                ]
              : [
                  textWidget,
                  const SizedBox(width: 4),
                  iconWidget,
                ],
        ),
      ),
    );

    if (!isEnabled) {
      return Opacity(opacity: 0.40, child: content);
    }

    return Tooltip(
      message: hint != null
          ? (AppState.instance.isArabic ? 'سورة $hint' : 'Surah $hint')
          : label,
      waitDuration: const Duration(milliseconds: 500),
      child: _TactileScaleButton(
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// 2026 Spring-scale tactile feedback button wrapper.
class _TactileScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _TactileScaleButton({required this.child, required this.onTap});

  @override
  State<_TactileScaleButton> createState() => _TactileScaleButtonState();
}

class _TactileScaleButtonState extends State<_TactileScaleButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) => setState(() => _isDown = false),
      onTapCancel: () => setState(() => _isDown = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isDown ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: _isDown ? Curves.easeOutQuad : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
