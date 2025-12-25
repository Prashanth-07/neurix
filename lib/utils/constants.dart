import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF6750A4);
  static const Color secondary = Color(0xFF625B71);
  static const Color background = Color(0xFFF6F5F5);
  static const Color text = Color(0xFF1D1B20);
  static const Color textLight = Color(0xFF49454F);
  static const Color error = Color(0xFFB3261E);
}

class AppTextStyles {
  static const TextStyle heading = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.text,
  );

  static const TextStyle subheading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: AppColors.text,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 14,
    color: AppColors.textLight,
  );
}

class AppSizes {
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double borderRadius = 12.0;
}

class AppInputDecorations {
  static InputDecoration textField({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        borderSide: BorderSide(color: AppColors.primary.withOpacity(0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        borderSide: BorderSide(color: AppColors.error, width: 2),
      ),
    );
  }
} 