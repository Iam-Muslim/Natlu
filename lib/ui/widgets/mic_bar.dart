import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';

/// 2026 Floating Glassmorphic Command Dock (Dynamic Floating Island)
///
/// Features:
/// - Frosted glassmorphism capsule with 24px backdrop blur.
/// - Hero Recite/Listen action capsule with dynamic gradients and audio pulse glow.
/// - Instant one-tap Voice Search shortcut to recite any Ayah across the Quran.
/// - Reading Mode (Auto-scroll) toggle with live state indication.
/// - Directional RTL/LTR mirroring with 48dp+ accessibility touch targets.
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

class _BottomActionBarState extends State<BottomActionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (widget.isRecording) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BottomActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = AppState.instance;
    final isAr = app.isArabic;
    final isDark = app.isDarkMode;

    // ── 2026 Modern Dock: Buttons Identical to Top Bar Action Buttons ──
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 10, right: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Left: Tajweed button (identical to top bar buttons + label) ──
                  _buildTopBarMatchingButton(
                    icon: Icons.record_voice_over_rounded,
                    label: isAr ? 'التجويد' : 'Tajweed',
                    isActive: widget.isTajweed,
                    c: c,
                    isDark: isDark,
                    isAr: isAr,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onToggleTajweed();
                    },
                  ),

                  const SizedBox(width: 8),

                  // ── Center: Hero Record/Stop Capsule ──
                  _buildCenterHeroButton(c, app),

                  const SizedBox(width: 8),

                  // ── Right: Hide Verses button (identical to top bar buttons + label) ──
                  _buildTopBarMatchingButton(
                    icon: widget.isBlur
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    label: isAr ? 'إخفاء' : 'Hide',
                    isActive: widget.isBlur,
                    c: c,
                    isDark: isDark,
                    isAr: isAr,
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
    );
  }

  /// Auxiliary button identical in square geometry (48x48) to the top bar buttons:
  /// matching corner radius (15), surface styling, active glow border, with icon and label.
  Widget _buildTopBarMatchingButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required ThemeColors c,
    required bool isDark,
    required bool isAr,
    required VoidCallback onTap,
  }) {
    final Color activeColor = c.primary;
    final Color iconColor = isActive ? activeColor : c.textSecondary;
    final Color textColor = isActive
        ? (isDark ? activeColor : c.text)
        : c.textSecondary;

    // Identical surface styling to tracking_screen top bar buttons
    final Color bgColor = isActive
        ? activeColor.withValues(alpha: isDark ? 0.22 : 0.14)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white);

    final Color borderColor = isActive
        ? activeColor.withValues(alpha: isDark ? 0.50 : 0.38)
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : c.border.withValues(alpha: 0.55));

    return _TactileScaleButton(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: borderColor,
            width: 0.85,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: isDark ? 0.28 : 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
              color: iconColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: isAr ? 'HafsSmart' : null,
                color: textColor,
                fontSize: isAr ? 10.5 : 9.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterHeroButton(ThemeColors c, AppState app) {
    final bool isDark = app.isDarkMode;
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
      label = app.isArabic ? 'إنهاء التلاوة' : 'Stop';
      icon = Icons.stop_rounded;
      onTap = widget.onMic;
    } else if (isScroll) {
      gradientStart = c.gold;
      gradientEnd = const Color(0xFFB45309);
      label = app.isArabic ? 'إيقاف التمرير' : 'Pause';
      icon = Icons.pause_rounded;
      onTap = widget.onToggleAutoScroll;
    } else {
      gradientStart = c.emerald;
      gradientEnd = const Color(0xFF0D9488);
      label = app.isArabic ? 'ابدأ التلاوة' : 'Recite';
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStart, gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.25 : 0.45),
            width: 0.85,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientStart.withValues(alpha: isRec ? 0.38 : 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.isLoadingEngine && !isRec)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(icon, color: Colors.white, size: 21),
            if (isRec) ...[
              const SizedBox(width: 7),
              const _AnimatedAudioWaveform(color: Colors.white),
            ],
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: app.isArabic ? 'HafsSmart' : null,
                color: Colors.white,
                fontSize: app.isArabic ? 14.5 : 13,
                fontWeight: FontWeight.bold,
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
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final double v = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildBar(6 + 8 * v),
            const SizedBox(width: 2.5),
            _buildBar(14 - 8 * v),
            const SizedBox(width: 2.5),
            _buildBar(8 + 11 * v),
            const SizedBox(width: 2.5),
            _buildBar(16 - 9 * v),
            const SizedBox(width: 2.5),
            _buildBar(6 + 9 * (1.0 - v)),
          ],
        );
      },
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.5,
      height: height.clamp(4.0, 16.0),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
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

