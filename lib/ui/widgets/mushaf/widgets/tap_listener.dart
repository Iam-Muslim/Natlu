import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Tracks the timestamp of the most recent word or marker tap to prevent
/// the background line tap from firing on the same touch.
abstract final class MushafTapState {
  static int _lastTapTime = 0;

  static void recordTap() {
    _lastTapTime = DateTime.now().millisecondsSinceEpoch;
  }

  static bool get wasRecentlyTapped =>
      (DateTime.now().millisecondsSinceEpoch - _lastTapTime) < 220;
}

/// A hyper-lightweight pointer tap listener that does NOT enter the Flutter
/// Gesture Arena. This eliminates all competition with [PageView]'s horizontal drag,
/// enabling silky-smooth 120 FPS swiping with zero touch latency.
class MushafTapListener extends StatefulWidget {
  final Widget child;
  final HitTestBehavior behavior;
  final bool checkRecentlyTapped;
  final void Function(Offset localPosition)? onTapUp;
  final VoidCallback? onTap;

  const MushafTapListener({
    super.key,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
    this.checkRecentlyTapped = false,
    this.onTap,
    this.onTapUp,
  });

  @override
  State<MushafTapListener> createState() => _MushafTapListenerState();
}

class _MushafTapListenerState extends State<MushafTapListener> {
  Offset? _downPos;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior,
      onPointerDown: (e) => _downPos = e.position,
      onPointerUp: (e) {
        final down = _downPos;
        _downPos = null;
        if (down != null && (e.position - down).distance <= kTouchSlop) {
          if (widget.checkRecentlyTapped && MushafTapState.wasRecentlyTapped) {
            return;
          }
          MushafTapState.recordTap();
          widget.onTap?.call();
          widget.onTapUp?.call(e.localPosition);
        }
      },
      onPointerCancel: (_) => _downPos = null,
      child: widget.child,
    );
  }
}
