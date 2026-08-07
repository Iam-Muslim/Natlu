import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

/// AutoScroll speed slider tile for Reading mode.
class AutoScrollSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const AutoScrollSliderTile({
    super.key,
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<AutoScrollSliderTile> createState() => _AutoScrollSliderTileState();
}

class _AutoScrollSliderTileState extends State<AutoScrollSliderTile> {
  late double _localSpeed;

  @override
  void initState() {
    super.initState();
    _localSpeed = widget.app.autoScrollSpeed.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isAr = widget.isAr;

    const labels = ['0.25x', '0.5x', '1x', '1.5x', '2x', '2.5x', '3x'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.speed_rounded, color: c.gold, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isAr ? 'سرعة التمرير التلقائي' : 'Auto-Scroll Speed',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                labels[_localSpeed.toInt()],
                style: TextStyle(
                  color: c.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 4,
              activeTrackColor: c.gold,
              inactiveTrackColor: c.border.withValues(alpha: 0.5),
              thumbColor: c.gold,
              overlayColor: c.gold.withValues(alpha: 0.15),
              tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
              activeTickMarkColor: c.surface,
              inactiveTickMarkColor: c.border,
            ),
            child: Slider(
              value: _localSpeed,
              min: 0,
              max: (labels.length - 1).toDouble(),
              divisions: labels.length - 1,
              label: labels[_localSpeed.toInt()],
              onChanged: (v) {
                setState(() => _localSpeed = v);
              },
              onChangeEnd: (v) {
                app.setAutoScrollSpeed(v.toInt());
              },
            ),
          ),
        ],
      ),
    );
  }
}
