import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';

/// 2026 Unified Glassmorphic Floating Command Dock (Dynamic Floating Island)
///
/// Design Architecture:
/// - Single unified frosted capsule dock with 20px backdrop blur (ImageFilter).
/// - Prominent Hero Recite action centerpiece with stacked icon + micro-label ("اتلو" / "قف"),
///   vibrant emerald-to-teal / ruby gradient, ambient bloom glow, and animated audio equalizer.
/// - Symmetrical, clean iconographic secondary toggles for Tajweed and Hide (Hifz memorization),
///   featuring dynamic state icons (e.g. visibility / visibility_off), micro-labels,
///   luminous active state indicator pips, and tactile spring feedback.
/// - Adaptive light (warm linen velvet) and dark (OLED obsidian glass) palettes.
class BottomActionBar extends StatefulWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final bool isAutoScrolling;
  final ThemeColors c;
  final VoidCallback onMic;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onSettingsTap;
  final bool isTajweed;
  final VoidCallback onToggleTajweed;
  final bool isBlur;
  final VoidCallback onToggleBlur;

  const BottomActionBar({
    super.key,
    required this.isRecording,
    this.isLoadingEngine = false,
    required this.isAutoScrolling,
    required this.c,
    required this.onMic,
    required this.onToggleAutoScroll,
    required this.onSettingsTap,
    required this.isTajweed,
    required this.onToggleTajweed,
    required this.isBlur,
    required this.onToggleBlur,
  });

  @override
  State<BottomActionBar> createState() => _BottomActionBarState();
}

class _BottomActionBarState extends State<BottomActionBar> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = AppState.instance;
    final isAr = app.isArabic;
    final isDark = app.isDarkMode;

    // ── Unified Floating Island Dock ──
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isDark
                          ? [
                              c.surfaceHigh.withValues(alpha: 0.72),
                              c.surface.withValues(alpha: 0.86),
                            ]
                          : [
                              Colors.white.withValues(alpha: 0.92),
                              c.surfaceHigh.withValues(alpha: 0.80),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : c.border.withValues(alpha: 0.65),
                      width: 0.85,
                    ),
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 22,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.90),
                              blurRadius: 2,
                              offset: const Offset(0, -1),
                            ),
                          ],
                  ),
                  child: Directionality(
                    textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Subordinate Satellite 1: Tajweed Toggle ──
                        _buildSecondaryToggle(
                          icon: widget.isTajweed
                              ? Icons.record_voice_over_rounded
                              : Icons.record_voice_over_outlined,
                          tooltip: isAr
                              ? 'أحكام التجويد ومخارج الحروف'
                              : 'Tajweed & Pronunciation Rules',
                          isActive: widget.isTajweed,
                          c: c,
                          isDark: isDark,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onToggleTajweed();
                          },
                        ),

                        const SizedBox(width: 8),

                        // ── Dominant Hero Centerpiece: Recite / Stop ──
                        _buildHeroReciteButton(c, app, isDark, isAr),

                        const SizedBox(width: 8),

                        // ── Subordinate Satellite 2: Hide Verses Toggle ──
                        _buildSecondaryToggle(
                          icon: widget.isBlur
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          tooltip: isAr ? 'إخفاء الآيات للتسميع' : 'Hide Verses for Memorization',
                          isActive: widget.isBlur,
                          c: c,
                          isDark: isDark,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onToggleBlur();
                          },
                        ),
                      ],
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

  /// Compact Eye-Comfortable Secondary Utility Toggle Button:
  /// - Minimalist 34x34dp circular/squircle satellite footprint.
  /// - Refined 18dp icon with zero text clutter.
  /// - Soft illuminated tint & border when active.
  Widget _buildSecondaryToggle({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required ThemeColors c,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final Color activeColor = c.primary;
    final Color contentColor = isActive
        ? activeColor
        : (isDark ? c.text.withValues(alpha: 0.60) : c.text.withValues(alpha: 0.65));

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: _TactileScaleButton(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withValues(alpha: isDark ? 0.22 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isActive
                  ? activeColor.withValues(alpha: isDark ? 0.45 : 0.35)
                  : Colors.transparent,
              width: 0.75,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: contentColor,
            size: 18,
          ),
        ),
      ),
    );
  }

  /// 2026 Hero Recite / Stop Action Centerpiece:
  /// - Streamlined 86x46dp capsule with vibrant gradients and ambient bloom.
  /// - Idle: Glowing mic + "اتلو" / "Recite".
  /// - Recording: ONLY dancing audio wave + "قف" / "Stop" (no square icon).
  /// - Auto-scroll: Pause icon + "إيقاف" / "Pause".
  Widget _buildHeroReciteButton(
    ThemeColors c,
    AppState app,
    bool isDark,
    bool isAr,
  ) {
    final bool isRec = widget.isRecording;
    final bool isScroll = widget.isAutoScrolling;

    final Color gradientStart;
    final Color gradientEnd;
    final String label;
    final IconData icon;
    final VoidCallback onTap;

    if (isRec) {
      gradientStart = const Color(0xFFEF4444);
      gradientEnd = const Color(0xFFDC2626);
      label = isAr ? 'قف' : 'Stop';
      icon = Icons.stop_rounded;
      onTap = widget.onMic;
    } else if (isScroll) {
      gradientStart = c.gold;
      gradientEnd = const Color(0xFFB45309);
      label = isAr ? 'إيقاف' : 'Pause';
      icon = Icons.pause_rounded;
      onTap = widget.onToggleAutoScroll;
    } else {
      gradientStart = c.emerald;
      gradientEnd = const Color(0xFF0D9488);
      label = isAr ? 'اتلو' : 'Recite';
      icon = Icons.mic_rounded;
      onTap = widget.onMic;
    }

    return _TactileScaleButton(
      onTap: () {
        HapticFeedback.heavyImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 86,
        height: 46,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStart, gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.30 : 0.45),
            width: 0.85,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientStart.withValues(alpha: isRec ? 0.42 : 0.36),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top: Fixed 18dp slot so button and label stay 100% rock-solid and static!
            SizedBox(
              height: 18,
              child: Center(
                child: isRec
                    ? const _AnimatedAudioWaveform(color: Colors.white)
                    : (widget.isLoadingEngine
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            icon,
                            color: Colors.white,
                            size: 20,
                          )),
              ),
            ),
            const SizedBox(height: 2),
            // Bottom: Crisp Micro-Label (completely stationary)
            Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: null,
                color: Colors.white,
                fontSize: isAr ? 11.5 : 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: isAr ? 0.2 : 0.5,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic animated equalizer soundwave for live recitation indication.
class _AnimatedAudioWaveform extends StatefulWidget {
  final Color color;
  const _AnimatedAudioWaveform({required this.color});

  @override
  State<_AnimatedAudioWaveform> createState() => _AnimatedAudioWaveformState();
}

class _AnimatedAudioWaveformState extends State<_AnimatedAudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final double v = _ctrl.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildBar(3.5 + 5.5 * v),
                const SizedBox(width: 2.2),
                _buildBar(8.5 - 4.5 * v),
                const SizedBox(width: 2.2),
                _buildBar(5.0 + 7.5 * v),
                const SizedBox(width: 2.2),
                _buildBar(11.0 - 6.5 * v),
                const SizedBox(width: 2.2),
                _buildBar(4.0 + 5.5 * (1.0 - v)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.2,
      height: height.clamp(3.0, 13.0),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(1.5),
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
        scale: _isDown ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: _isDown ? Curves.easeOutQuad : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
