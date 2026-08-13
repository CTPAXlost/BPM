import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AuroraBackground extends StatelessWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: AppColors.background),
        IgnorePointer(child: CustomPaint(painter: _AuroraPainter())),
        child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cyan = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.cyan.withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.78, size.height * 0.16),
          radius: math.max(size.width, size.height) * 0.45,
        ),
      );
    canvas.drawRect(Offset.zero & size, cyan);

    final violet = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          AppColors.violet.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.15, size.height * 0.68),
          radius: math.max(size.width, size.height) * 0.48,
        ),
      );
    canvas.drawRect(Offset.zero & size, violet);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
