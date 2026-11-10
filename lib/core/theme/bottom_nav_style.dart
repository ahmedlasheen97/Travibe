import 'package:flutter/material.dart';

class BottomNavStyle extends ThemeExtension<BottomNavStyle> {
  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final double height;

  const BottomNavStyle({
    required this.backgroundColor,
    required this.borderColor,
    required this.borderWidth,
    required this.radius,
    required this.height,
  });

  @override
  BottomNavStyle copyWith({
    Color? backgroundColor,
    Color? borderColor,
    double? borderWidth,
    double? radius,
    double? height,
  }) {
    return BottomNavStyle(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      radius: radius ?? this.radius,
      height: height ?? this.height,
    );
  }

  @override
  BottomNavStyle lerp(ThemeExtension<BottomNavStyle>? other, double t) {
    if (other is! BottomNavStyle) return this;
    return BottomNavStyle(
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      borderWidth: borderWidth,
      radius: radius,
      height: height,
    );
  }
}