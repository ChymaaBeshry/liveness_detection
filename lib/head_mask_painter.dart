import 'package:flutter/material.dart';

class HeadMaskPainter extends CustomPainter {
  final double maskRadius;

  const HeadMaskPainter({
    this.maskRadius = 0.4,
  }); // تقدرِ تتحكمي في حجم الدائرة لو حبيتي

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * maskRadius;

    final path =
        Path()
          ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
          ..addOval(Rect.fromCircle(center: center, radius: radius))
          ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
