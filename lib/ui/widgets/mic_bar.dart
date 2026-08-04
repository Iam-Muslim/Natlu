import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_state.dart';

/// Bottom floating action bar — primary interaction point for Recite, Stop, and AutoScroll.
class BottomActionBar extends StatefulWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final bool isAutoScrolling;
  final ThemeColors c;
  final VoidCallback onMic;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onSettingsTap;
  final bool isVoiceSearching;

  const BottomActionBar({
    super.key,
    required this.isRecording,
    this.isLoadingEngine = false,
    required this.isAutoScrolling,
    required this.c,
    required this.onMic,
    required this.onToggleAutoScroll,
    required this.onSettingsTap,
    this.isVoiceSearching = false,
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
      duration: const Duration(milliseconds: 1500),
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

    Widget actionButton;
    if (widget.isAutoScrolling) {
      // ── AutoScroll Pause Button ──
      actionButton = _buildFloatingButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onToggleAutoScroll();
        },
        gradient: LinearGradient(
          colors: [c.gold, c.gold.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shadowColor: c.gold.withValues(alpha: 0.3),
        icon: Icons.pause_rounded,
        label: app.isArabic ? 'إيقاف' : 'Pause',
      );
    } else {
      // ── Record / Stop Button ──
      final Color buttonColor = widget.isRecording ? c.red : c.green;
      actionButton = _buildFloatingButton(
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onMic();
        },
        gradient: LinearGradient(
          colors: [buttonColor, buttonColor.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shadowColor: buttonColor.withValues(alpha: 0.25),
        shadowBlur: 16,
        shadowSpread: 2,
        icon: widget.isLoadingEngine
            ? null
            : (widget.isRecording ? Icons.stop_rounded : Icons.mic_rounded),
        isLoading: widget.isLoadingEngine,
        label: widget.isRecording
            ? (app.isArabic ? 'انتهي' : 'End')
            : (app.isArabic ? 'اتلو' : 'Recite'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24, right: 24, left: 24),
      child: Align(alignment: Alignment.bottomLeft, child: actionButton),
    );
  }

  Widget _buildFloatingButton({
    required VoidCallback onTap,
    required Gradient gradient,
    required Color shadowColor,
    double shadowBlur = 16,
    double shadowSpread = 2,
    IconData? icon,
    bool isLoading = false,
    required String label,
  }) {
    final app = AppState.instance;
    final c = widget.c;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: shadowBlur,
                  spreadRadius: shadowSpread,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : (icon != null
                      ? Icon(icon, color: Colors.white, size: 30)
                      : const SizedBox.shrink()),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: app.isArabic ? 'HafsSmart' : null,
            color: c.text,
            fontSize: app.isArabic ? 15 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
