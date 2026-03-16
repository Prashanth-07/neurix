import 'package:flutter/material.dart';
import '../utils/constants.dart';

class StarfieldBackground extends StatelessWidget {
  final Widget child;

  const StarfieldBackground({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Subtle purple glow at center-top
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
          child,
        ],
      ),
    );
  }
}
