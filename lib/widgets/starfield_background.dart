import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class Star {
  double x;
  double y;
  double size;
  double opacity;
  double speed;
  double twinkleSpeed;
  double twinklePhase;

  Star({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.twinkleSpeed,
    required this.twinklePhase,
  });
}

class StarfieldBackground extends StatefulWidget {
  final Widget child;

  const StarfieldBackground({Key? key, required this.child}) : super(key: key);

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Star> _stars;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _stars = _generateStars(150);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  List<Star> _generateStars(int count) {
    return List.generate(count, (_) {
      return Star(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        size: _random.nextDouble() * 2.0 + 0.5, // 0.5 - 2.5
        opacity: _random.nextDouble() * 0.6 + 0.2, // 0.2 - 0.8
        speed: _random.nextDouble() * 0.0003 + 0.0001, // very slow drift
        twinkleSpeed: _random.nextDouble() * 2.0 + 1.0,
        twinklePhase: _random.nextDouble() * pi * 2,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Stars layer
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _StarfieldPainter(
                  stars: _stars,
                  animationValue: _controller.value,
                ),
                size: Size.infinite,
              );
            },
          ),
          // Purple glow at center-top
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, -0.5),
                    radius: 1.2,
                    colors: [
                      AppColors.primary.withOpacity(0.08),
                      AppColors.primary.withOpacity(0.03),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Content
          widget.child,
        ],
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final List<Star> stars;
  final double animationValue;

  _StarfieldPainter({required this.stars, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      // Slow vertical drift (stars drift upward and wrap)
      final dy = (star.y - animationValue * star.speed * 1000) % 1.0;
      final dx = star.x;

      // Twinkle effect
      final twinkle = (sin(animationValue * pi * 2 * star.twinkleSpeed + star.twinklePhase) + 1) / 2;
      final currentOpacity = star.opacity * (0.5 + 0.5 * twinkle);

      final paint = Paint()
        ..color = Colors.white.withOpacity(currentOpacity.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, star.size * 0.5);

      canvas.drawCircle(
        Offset(dx * size.width, dy * size.height),
        star.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => true;
}
