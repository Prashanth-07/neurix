import 'package:flutter/material.dart';
import '../utils/constants.dart';

class SlideToStop extends StatefulWidget {
  final VoidCallback onSlideComplete;
  final String label;

  const SlideToStop({
    super.key,
    required this.onSlideComplete,
    this.label = 'Slide to stop',
  });

  @override
  State<SlideToStop> createState() => _SlideToStopState();
}

class _SlideToStopState extends State<SlideToStop> {
  double _dragPosition = 0;
  double _maxDragDistance = 0;
  bool _isCompleted = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDragDistance = constraints.maxWidth - 70;

        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Stack(
            children: [
              // Label in center
              Center(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Draggable thumb
              Positioned(
                left: 5 + _dragPosition,
                top: 5,
                child: GestureDetector(
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isCompleted) return;

    setState(() {
      _dragPosition += details.delta.dx;
      _dragPosition = _dragPosition.clamp(0, _maxDragDistance);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isCompleted) return;

    if (_dragPosition >= _maxDragDistance * 0.8) {
      setState(() {
        _isCompleted = true;
        _dragPosition = _maxDragDistance;
      });
      widget.onSlideComplete();
    } else {
      setState(() {
        _dragPosition = 0;
      });
    }
  }
}
