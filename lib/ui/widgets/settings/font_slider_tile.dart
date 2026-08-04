import 'package:flutter/material.dart';
import '../../../state/app_state.dart';

/// Font size slider tile with live Arabic preview markers.
class FontSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const FontSliderTile({
    super.key,
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<FontSliderTile> createState() => _FontSliderTileState();
}

class _FontSliderTileState extends State<FontSliderTile> {
  late double _localSize;

  @override
  void initState() {
    super.initState();
    _localSize = widget.app.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isAr = widget.isAr;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.format_size_rounded, color: c.gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              isAr ? 'حجم الخط' : 'Font Size',
              style: TextStyle(
                color: c.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(
                  'أ',
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    color: c.muted,
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      trackHeight: 4,
                      activeTrackColor: c.gold,
                      inactiveTrackColor: c.border.withValues(alpha: 0.5),
                      thumbColor: c.gold,
                      overlayColor: c.gold.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _localSize,
                      min: 16.0,
                      max: 42.0,
                      onChanged: (v) {
                        setState(() => _localSize = v);
                      },
                      onChangeEnd: (v) {
                        app.setFontSize(v);
                      },
                    ),
                  ),
                ),
                Text(
                  'أ',
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    color: c.muted,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
