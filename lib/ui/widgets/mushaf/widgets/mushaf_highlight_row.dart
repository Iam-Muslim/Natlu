import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Specialized Flex widget that paints a seamless, continuous background ribbon
/// behind active Ayah items (spanning across words and their justification gaps)
/// without disturbing flex layout, word justification, or causing any overflow.
class MushafHighlightRow extends Flex {
  final int? highlightStartIndex;
  final int? highlightEndIndex;
  final Color? highlightColor;
  final Color? highlightBorderColor;

  const MushafHighlightRow({
    super.key,
    required super.children,
    super.mainAxisAlignment = MainAxisAlignment.spaceBetween,
    super.crossAxisAlignment = CrossAxisAlignment.center,
    super.mainAxisSize = MainAxisSize.min,
    super.textDirection = TextDirection.rtl,
    this.highlightStartIndex,
    this.highlightEndIndex,
    this.highlightColor,
    this.highlightBorderColor,
  }) : super(direction: Axis.horizontal);

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return RenderMushafHighlightFlex(
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: getEffectiveTextDirection(context),
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      clipBehavior: clipBehavior,
      highlightStartIndex: highlightStartIndex,
      highlightEndIndex: highlightEndIndex,
      highlightColor: highlightColor,
      highlightBorderColor: highlightBorderColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMushafHighlightFlex renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.highlightStartIndex = highlightStartIndex;
    renderObject.highlightEndIndex = highlightEndIndex;
    renderObject.highlightColor = highlightColor;
    renderObject.highlightBorderColor = highlightBorderColor;
  }
}

class RenderMushafHighlightFlex extends RenderFlex {
  int? _highlightStartIndex;
  int? _highlightEndIndex;
  Color? _highlightColor;
  Color? _highlightBorderColor;
  static const double _highlightRadius = 6.0;

  static final Paint _highlightFillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _highlightBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  RenderMushafHighlightFlex({
    super.direction = Axis.horizontal,
    super.mainAxisSize = MainAxisSize.max,
    super.mainAxisAlignment = MainAxisAlignment.start,
    super.crossAxisAlignment = CrossAxisAlignment.center,
    super.textDirection,
    super.verticalDirection = VerticalDirection.down,
    super.textBaseline,
    super.clipBehavior = Clip.none,
    int? highlightStartIndex,
    int? highlightEndIndex,
    Color? highlightColor,
    Color? highlightBorderColor,
  })  : _highlightStartIndex = highlightStartIndex,
        _highlightEndIndex = highlightEndIndex,
        _highlightColor = highlightColor,
        _highlightBorderColor = highlightBorderColor;

  /// Fast horizontal hit calculation to find the closest child word or marker
  /// to a tap coordinate in O(N) where N <= 15 with zero allocations.
  int findClosestChildIndex(double x) {
    RenderBox? child = firstChild;
    int index = 0;
    int bestIndex = 0;
    double minDistance = double.infinity;

    while (child != null) {
      final parentData = child.parentData as FlexParentData;
      final childLeft = parentData.offset.dx;
      final childRight = childLeft + child.size.width;

      final double distance;
      if (x >= childLeft && x <= childRight) {
        return index;
      } else if (x < childLeft) {
        distance = childLeft - x;
      } else {
        distance = x - childRight;
      }

      if (distance < minDistance) {
        minDistance = distance;
        bestIndex = index;
      }

      child = childAfter(child);
      index++;
    }
    return bestIndex;
  }

  int? get highlightStartIndex => _highlightStartIndex;
  set highlightStartIndex(int? value) {
    if (_highlightStartIndex != value) {
      _highlightStartIndex = value;
      markNeedsPaint();
    }
  }

  int? get highlightEndIndex => _highlightEndIndex;
  set highlightEndIndex(int? value) {
    if (_highlightEndIndex != value) {
      _highlightEndIndex = value;
      markNeedsPaint();
    }
  }

  Color? get highlightColor => _highlightColor;
  set highlightColor(Color? value) {
    if (_highlightColor != value) {
      _highlightColor = value;
      markNeedsPaint();
    }
  }

  Color? get highlightBorderColor => _highlightBorderColor;
  set highlightBorderColor(Color? value) {
    if (_highlightBorderColor != value) {
      _highlightBorderColor = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_highlightColor != null &&
        _highlightStartIndex != null &&
        _highlightEndIndex != null &&
        _highlightStartIndex! <= _highlightEndIndex!) {
      int index = 0;
      RenderBox? child = firstChild;
      double? minX;
      double? maxX;
      double? minY;
      double? maxY;

      while (child != null) {
        if (index >= _highlightStartIndex! && index <= _highlightEndIndex!) {
          final parentData = child.parentData as FlexParentData;
          final childOffset = offset + parentData.offset;
          final childSize = child.size;

          final left = childOffset.dx;
          final right = childOffset.dx + childSize.width;
          final top = childOffset.dy;
          final bottom = childOffset.dy + childSize.height;

          minX = minX == null ? left : math.min(minX, left);
          maxX = maxX == null ? right : math.max(maxX, right);
          minY = minY == null ? top : math.min(minY, top);
          maxY = maxY == null ? bottom : math.max(maxY, bottom);
        }
        child = childAfter(child);
        index++;
      }

      if (minX != null && maxX != null && minY != null && maxY != null) {
        // Expand horizontally and vertically slightly for a comfortable breathing room
        final clampLeft =
            (minX - 3.0).clamp(offset.dx, offset.dx + size.width);
        final clampRight =
            (maxX + 3.0).clamp(offset.dx, offset.dx + size.width);
        final clampTop =
            (minY - 2.0).clamp(offset.dy, offset.dy + size.height);
        final clampBottom =
            (maxY + 2.0).clamp(offset.dy, offset.dy + size.height);

        if (clampRight > clampLeft && clampBottom > clampTop) {
          final rect =
              Rect.fromLTRB(clampLeft, clampTop, clampRight, clampBottom);
          final rrect =
              RRect.fromRectAndRadius(rect, const Radius.circular(_highlightRadius));

          _highlightFillPaint.color = _highlightColor!;
          context.canvas.drawRRect(rrect, _highlightFillPaint);

          if (_highlightBorderColor != null) {
            _highlightBorderPaint.color = _highlightBorderColor!;
            context.canvas.drawRRect(rrect, _highlightBorderPaint);
          }
        }
      }
    }

    super.paint(context, offset);
  }
}
