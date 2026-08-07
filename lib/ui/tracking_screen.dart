import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../tracking/word/highlighting_controller.dart';
import '../utils/debug_logger.dart';
import 'widgets/dialogs/voice_search_dialog.dart';
import 'widgets/mic_bar.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/surah_picker.dart';
import 'widgets/verse_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Main interactive screen for real-time recitation tracking and reading.
/// Manages scrolling, distraction-free reading headers, and mode switches.
class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final String voiceSearchText;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    this.voiceSearchText = '',
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final AutoScrollController _scroll = AutoScrollController();
  final Map<int, GlobalKey> _keys = {};
  final ValueNotifier<String> _voiceSearchNotifier = ValueNotifier('');

  int? _lastAyah;
  int? _lastSurah;
  bool _isAutoScrolling = false;
  
  bool _hasClickedTajweedWord = true;
  bool _showTajweedHint = false;

  @override
  void initState() {
    super.initState();
    _checkTajweedHint();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerUpdate);
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    _scroll.dispose();
    _voiceSearchNotifier.dispose();
    WakelockPlus.disable();
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

    if (widget.voiceSearchText != oldWidget.voiceSearchText) {
      _voiceSearchNotifier.value = widget.voiceSearchText;
    }

    if (widget.isVoiceSearching && !oldWidget.isVoiceSearching) {
      _voiceSearchNotifier.value = widget.voiceSearchText;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          VoiceSearchDialog.show(context, onStop: widget.onVoiceSearchToggle);
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
      _lastSurah = widget.controller.targetSurah;
      _keys.clear();
      _lastAyah = null;

      if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    }
    
    // Check for yellow words to show hint
    if (!_hasClickedTajweedWord && !_showTajweedHint && widget.isRecording) {
      // We check if any yellow word exists using a workaround since _yellowWordsByVerse is private
      bool hasYellow = false;
      try {
        // Just checking if we can find any yellow word in the current ayah
        final active = widget.controller.activeAyah.value;
        if (active != null) {
          final verses = widget.controller.repository.getSurah(widget.controller.targetSurah);
          final verse = verses.firstWhere((v) => v.ayah == active);
          for (int i = 0; i < verse.uthmaniWords.length; i++) {
            if (widget.controller.isWordYellow(active, i)) {
              hasYellow = true;
              break;
            }
          }
        }
      } catch (e) {
        // Ignore
      }
      
      if (hasYellow && mounted) {
        setState(() {
          _showTajweedHint = true;
        });
      }
    }
  }

  Future<void> _checkTajweedHint() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasClickedTajweedWord = prefs.getBool('has_clicked_tajweed_word') ?? false;
    });
  }

  Future<void> _markTajweedWordClicked() async {
    if (!_hasClickedTajweedWord) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_clicked_tajweed_word', true);
      setState(() {
        _hasClickedTajweedWord = true;
        _showTajweedHint = false;
      });
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
    _scroll.scrollToIndex(
      ayah,
      duration: const Duration(milliseconds: 100),
      preferPosition: AutoScrollPosition.middle,
    );
  }

  void _toggleAutoScroll() {
    if (_isAutoScrolling) {
      setState(() => _isAutoScrolling = false);
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.pixels);
      }
      WakelockPlus.disable();
    } else {
      widget.controller.clearHighlights();
      widget.controller.finalize();
      setState(() => _isAutoScrolling = true);
      _startAutoScrollLoop();
      WakelockPlus.enable();
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
      WakelockPlus.disable();
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
              WakelockPlus.disable();
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
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: app,
      builder: (_, _) {
        final c = app.colors;

        return Directionality(
          textDirection: TextDirection.rtl,
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
                  bottom: MediaQuery.of(context).viewPadding.bottom,
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
                      isVoiceSearching: widget.isVoiceSearching,
                      isAutoScrolling: _isAutoScrolling,
                      c: c,
                      onMic: widget.isVoiceSearching
                          ? widget.onVoiceSearchToggle
                          : widget.onToggleRecord,
                      onToggleAutoScroll: _toggleAutoScroll,
                      onSettingsTap: _showSettingsDialog,
                    ),
                  ),
                ),

                // Tajweed Hint Overlay
                if (_showTajweedHint && app.currentMode == AppMode.tajweed)
                  Positioned(
                    bottom: 120,
                    left: 24,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.gold,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: c.gold.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              app.isArabic 
                                  ? 'اضغط على الكلمة الصفراء لمعرفة خطأ التجويد!'
                                  : 'Tap on the yellow word to see the Tajweed error!',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
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
      return const SizedBox.shrink(key: ValueKey('empty_header'));
    }

    return Padding(
      key: const ValueKey('header_main'),
      padding: EdgeInsets.only(top: top + 10, left: 14, right: 14, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Surah Selector
            Flexible(
              flex: 4,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: GestureDetector(
                  onTap: _showSurahPicker,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final displayVerses = widget.controller.repository
                                  .getSurah(widget.controller.targetSurah);
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: app.isArabic
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Text(
                                  app.isArabic
                                      ? displayVerses.first.surahName
                                      : displayVerses.first.surahNameEn,
                                  style: TextStyle(
                                    fontFamily: app.isArabic
                                        ? 'HafsSmart'
                                        : null,
                                    color: c.gold,
                                    fontSize: app.isArabic ? 18 : 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: c.gold,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Action Buttons
            Expanded(
              flex: 6,
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionBtn(
                      icon: Icons.auto_stories_rounded,
                      label: app.isArabic ? 'قراءة' : 'Read',
                      color: c.text,
                      onTap: _toggleAutoScroll,
                    ),
                  ),
                  Expanded(
                    child: _buildActionBtn(
                      icon: app.isBlurMode
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      label: app.isArabic ? 'إخفاء' : 'Hide',
                      color: app.isBlurMode ? c.green : c.text,
                      onTap: app.toggleBlurMode,
                    ),
                  ),
                  Expanded(
                    child: _buildActionBtn(
                      icon: Icons.format_color_text_rounded,
                      label: app.isArabic ? 'تجويد' : 'Tajweed',
                      color: app.currentMode == AppMode.tajweed
                          ? c.green
                          : c.text,
                      onTap: () {
                        final newMode = app.currentMode == AppMode.tajweed
                            ? AppMode.wordChecker
                            : AppMode.tajweed;
                        app.setMode(newMode);
                        widget.controller.setTajweedMode(
                          newMode == AppMode.tajweed,
                        );

                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              app.currentMode == AppMode.tajweed
                                  ? (app.isArabic
                                        ? 'تم تفعيل وضع التجويد'
                                        : 'Tajweed Mode Enabled')
                                  : (app.isArabic
                                        ? 'تم إيقاف وضع التجويد'
                                        : 'Tajweed Mode Disabled'),
                              style: TextStyle(color: c.text),
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: c.surfaceHigh,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildActionBtn(
                      icon: Icons.settings_rounded,
                      label: app.isArabic ? 'إعدادات' : 'Settings',
                      color: c.text,
                      onTap: _showSettingsDialog,
                      onLongPress: () async {
                        try {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Preparing logs...')),
                          );
                          String allLogs = globalSessionLogs.join('\n');
                          final directory = await getTemporaryDirectory();
                          final logFile = File(
                            '${directory.path}/recite_quran_logs.txt',
                          );
                          await logFile.writeAsString(allLogs);
                          // ignore: deprecated_member_use
                          await Share.shareXFiles([
                            XFile(logFile.path),
                          ], text: 'Logs');
                        } catch (e) {
                          DebugLogger.logSimple(
                            'TrackingScreen',
                            "Error preparing logs: $e",
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
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

        final bool isMainRec = widget.isRecording;
        final topPadding = (isMainRec || _isAutoScrolling)
            ? top + 16
            : top + 72;
        final bottomPadding = (isMainRec || _isAutoScrolling) ? 140.0 : 200.0;

        return ListView.builder(
          controller: _scroll,
          physics: _isAutoScrolling
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: displayVerses.length + 2,
          itemBuilder: (_, i) {
            if (i == 0) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                height: topPadding,
              );
            }

            if (i == displayVerses.length + 1) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                height: bottomPadding,
              );
            }

            final v = displayVerses[i - 1];

            return AutoScrollTag(
              key: ValueKey(v.ayah),
              controller: _scroll,
              index: v.ayah,
              child: VerseRow(
                key: ValueKey('verse_${v.surah}_${v.ayah}'),
                verse: v,
                controller: widget.controller,
                isAutoScrolling: _isAutoScrolling,
                onTap: () {
                  widget.controller.setManualAyah(v.surah, v.ayah);
                },
                onWordErrorTap: () {
                  _markTajweedWordClicked();
                },
              ),
            );
          },
        );
      },
    );
  }
}
