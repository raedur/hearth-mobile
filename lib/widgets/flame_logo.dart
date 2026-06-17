import 'package:flutter/material.dart';

/// Replicates the Hearth flame SVG from the landing page:
/// outer gradient #FDE68A → #F97316 → #92400E, inner glow #FEF3C7 @ 70%.
class FlameLogo extends StatelessWidget {
  final double size;
  const FlameLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * (68 / 52),
      child: CustomPaint(painter: _FlamePainter()),
    );
  }
}

class _FlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Scale from SVG viewBox 52×68
    final sx = size.width / 52;
    final sy = size.height / 68;

    // Outer flame path (from SVG d="M26 4C22 13 10 22 10 36...")
    final outer = Path()
      ..moveTo(26 * sx, 4 * sy)
      ..cubicTo(22 * sx, 13 * sy, 10 * sx, 22 * sy, 10 * sx, 36 * sy)
      ..cubicTo(10 * sx, 50 * sy, 17 * sx, 64 * sy, 26 * sx, 66 * sy)
      ..cubicTo(35 * sx, 64 * sy, 42 * sx, 50 * sy, 42 * sx, 36 * sy)
      ..cubicTo(42 * sx, 22 * sy, 30 * sx, 13 * sy, 26 * sx, 4 * sy)
      ..close();

    final outerRect = Rect.fromLTWH(0, 4 * sy, size.width, 64 * sy);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: const [0.0, 0.45, 1.0],
      colors: const [Color(0xFFFDE68A), Color(0xFFF97316), Color(0xFF92400E)],
    );

    final outerPaint = Paint()
      ..shader = gradient.createShader(outerRect)
      ..style = PaintingStyle.fill;

    canvas.drawPath(outer, outerPaint);

    // Inner glow path
    final inner = Path()
      ..moveTo(26 * sx, 26 * sy)
      ..cubicTo(24 * sx, 31 * sy, 20 * sx, 35 * sy, 20 * sx, 41 * sy)
      ..cubicTo(20 * sx, 48 * sy, 22 * sx, 54 * sy, 26 * sx, 56 * sy)
      ..cubicTo(30 * sx, 54 * sy, 32 * sx, 48 * sy, 32 * sx, 41 * sy)
      ..cubicTo(32 * sx, 35 * sy, 28 * sx, 31 * sy, 26 * sx, 26 * sy)
      ..close();

    final innerPaint = Paint()
      ..color = const Color(0xFFFEF3C7).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    canvas.drawPath(inner, innerPaint);
  }

  @override
  bool shouldRepaint(_FlamePainter old) => false;
}
