import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSizes {
  // Opt-in responsive values for Home. Legacy fields below remain unchanged.
  static double get w64 => 64.w;
  static double get h64 => 64.h;
  static double adaptiveWidth(double value) =>
      value.w.clamp(value * .85, value * 1.15);
  static double adaptiveHeight(double value) =>
      value.h.clamp(value * .85, value * 1.15);
  static double adaptiveRadius(double value) =>
      value.r.clamp(value * .85, value * 1.15);
  static double adaptiveFont(double value) =>
      value.sp.clamp(value * .9, value * 1.1);

  /// Font Sizes
  static final double sp8 = 8.sp;
  static final double sp12 = 12.sp;
  static final double sp14 = 14.sp;
  static final double sp16 = 16.sp;
  static final double sp18 = 18.sp;
  static final double sp20 = 20.sp;
  static final double sp22 = 22.sp;
  static final double sp24 = 24.sp;
  static final double sp28 = 28.sp;
  static final double sp32 = 32.sp;
  static final double sp40 = 40.sp;

  /// Heights
  static final double h2 = 2.h;
  static final double h4 = 4.h;
  static final double h0_5 = 0.5.h;
  static final double h8 = 8.h;
  static final double h6 = 6.h;
  static final double h12 = 12.h;

  static final double h16 = 16.h;
  static final double h20 = 20.h;
  static final double h24 = 24.h;
  static final double h28 = 28.h;
  static final double h32 = 32.h;
  static final double h35 = 35.h;
  static final double h36 = 36.h;
  static final double h38 = 38.h;
  static final double h40 = 40.h;
  static final double h42 = 42.h;
  static final double h44 = 44.h;
  static final double h45 = 45.h;
  static final double h48 = 48.h;
  static final double h52 = 52.h;
  static final double h56 = 56.h;
  static final double h60 = 60.h;
  static final double h62 = 62.h;
  static final double h70 = 70.h;
  static final double h72 = 72.h;
  static final double h74 = 74.h;
  static final double h80 = 80.h;
  static final double h95 = 95.h;
  static final double h100 = 100.h;
  static final double h140 = 140.h;
  static final double h160 = 160.h;
  static final double h180 = 180.h;
  static final double h190 = 190.h;
  static final double h198 = 198.h;
  static final double h200 = 200.h;
  static final double h240 = 240.h;
  static final double h330 = 330.h;
  static final double h369 = 369.h;
  static final double h400 = 400.h;

  /// Width
  static final double w1 = 1.w;
  static final double w2 = 2.w;
  static final double w4 = 4.w;
  static final double w8 = 8.w;
  static final double w12 = 12.w;
  static final double w16 = 16.w;
  static final double w20 = 20.w;
  static final double w24 = 24.w;
  static final double w28 = 28.w;
  static final double w32 = 32.w;
  static final double w35 = 35.w;
  static final double w38 = 38.w;
  static final double w40 = 40.w;
  static final double w42 = 42.w;
  static final double w44 = 44.w;
  static final double w45 = 45.w;
  static final double w48 = 48.w;
  static final double w52 = 52.w;
  static final double w54 = 54.w;
  static final double w56 = 56.w;
  static final double w60 = 60.w;
  static final double w62 = 62.w;
  static final double w70 = 70.w;
  static final double w72 = 72.w;
  static final double w74 = 74.w;
  static final double w80 = 80.w;
  static final double w95 = 95.w;
  static final double w140 = 140.w;
  static final double w160 = 160.w;
  static final double w180 = 180.w;
  static final double w200 = 200.w;
  static final double w240 = 240.w;

  /// Padding Height
  static final double ph4 = 4.h;
  static final double ph6 = 6.h;
  static final double ph8 = 8.h;
  static final double ph12 = 12.h;
  static final double ph16 = 16.h;
  static final double ph20 = 20.h;
  static final double ph24 = 24.h;
  static final double ph30 = 30.h;
  static final double ph40 = 40.h;
  static final double ph60 = 60.h;
  static final double ph62 = 62.h;

  static final double ph70 = 70.h;
  static final double ph80 = 80.h;
  static final double ph100 = 100.h;
  static final double ph112 = 112.h;

  /// Padding Width
  static final double pw6 = 6.w;
  static final double pw8 = 8.w;
  static final double pw12 = 12.w;
  static final double pw16 = 16.w;
  static final double pw18 = 18.w;
  static final double pw24 = 24.w;

  /// Radius
  static final double r4 = 4.r;
  static final double r8 = 8.r;
  static final double r10 = 10.r;
  static final double r12 = 12.r;
  static final double r16 = 16.r;
  static final double r20 = 20.r;
  static final double r22 = 22.r;
  static final double r24 = 24.r;
  static final double r26 = 26.r;
  static final double r30 = 30.r;
  static final double r50 = 50.r;
  static final double r60 = 60.r;
  static final double r64 = 64.r;
}
