import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants.dart';

class CategorySpend {
  const CategorySpend({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;
}

/// Spend-by-category bars drawn by hand. A charting package would be the single
/// largest addition to the bundle for something this small.
class CategoryBarsChart extends StatelessWidget {
  const CategoryBarsChart({super.key, required this.data});

  final List<CategorySpend> data;

  static const double _rowHeight = 28;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Nothing spent in this month yet.',
          style: TextStyle(color: kTextMuted, fontSize: 13),
        ),
      );
    }
    return CustomPaint(
      size: Size(double.infinity, data.length * _rowHeight),
      painter: _CategoryBarsPainter(data),
    );
  }
}

class _CategoryBarsPainter extends CustomPainter {
  _CategoryBarsPainter(this.data);

  final List<CategorySpend> data;

  static const double _labelWidth = 104;
  static const double _valueWidth = 96;
  static const double _gap = 10;
  static const double _barHeight = 10;
  static const double _rowHeight = CategoryBarsChart._rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final double maxAmount = data
        .map((CategorySpend e) => e.amount)
        .fold<double>(0, (double a, double b) => math.max(a, b));
    final double trackLeft = _labelWidth + _gap;
    final double trackWidth =
        math.max(24, size.width - trackLeft - _valueWidth - _gap);
    final Paint trackPaint = Paint()..color = kSurfaceAlt;

    for (int i = 0; i < data.length; i++) {
      final CategorySpend entry = data[i];
      final double top = i * _rowHeight;
      final double barTop = top + (_rowHeight - _barHeight) / 2 - 2;

      _drawText(canvas, entry.label, Offset(0, top + 4), _labelWidth, kText);

      final RRect track = RRect.fromRectAndRadius(
        Rect.fromLTWH(trackLeft, barTop, trackWidth, _barHeight),
        const Radius.circular(5),
      );
      canvas.drawRRect(track, trackPaint);

      if (maxAmount > 0 && entry.amount > 0) {
        final double filled =
            math.max(4, trackWidth * (entry.amount / maxAmount));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(trackLeft, barTop, filled, _barHeight),
            const Radius.circular(5),
          ),
          Paint()..color = entry.color,
        );
      }

      _drawText(
        canvas,
        formatMoney(entry.amount, withSymbol: false),
        Offset(trackLeft + trackWidth + _gap, top + 4),
        _valueWidth,
        kTextMuted,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    Color color,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 12),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
    painter.dispose();
  }

  @override
  bool shouldRepaint(_CategoryBarsPainter oldDelegate) =>
      oldDelegate.data != data;
}
