import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppSizes {
  /// Figma frame width every design value is drawn against.
  static const double designWidth = 390;

  /// Linear scale of a Figma value for [screenWidth] (1.0 at 390).
  static double widthScale(double screenWidth) => screenWidth / designWidth;

  // Opt-in responsive values. Legacy fields below remain unchanged.
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

  // ---------------------------------------------------------------------------
  // Shared form controls (CustomTextField, CustomButton, input theme). Used
  // app-wide, so these stay fixed logical sizes rather than adaptive ones.
  // ---------------------------------------------------------------------------
  static const double fieldFont = 16;
  static const double fieldPadding = 16;
  static const double fieldLabelGap = 8;
  static const double fieldIconSize = 24;
  static const double fieldEyeTapSize = 48;

  /// Prefix icon → text gap; Material 3 already adds [fieldM3PrefixInset].
  static double get fieldIconGap => adaptiveWidth(8);
  static const double fieldM3PrefixInset = 4;
  static const double fieldRadius = 35;
  static const double fieldBorderWidth = 0.5;
  static const double buttonHeight = 48;
  static const double buttonLabelFont = 18;
  static const double buttonRadius = 32;

  // ---------------------------------------------------------------------------
  // Auth screens: Login, Sign Up, Verify Email, Forgot Password, Verify Code,
  // New Password and "Password updated!".
  // ---------------------------------------------------------------------------

  /// Body inset under the [AuthAppBar]; its top is the 24 gap below the bar.
  static EdgeInsets get authPagePadding => EdgeInsets.fromLTRB(
    adaptiveWidth(8),
    adaptiveHeight(24),
    adaptiveWidth(8),
    adaptiveHeight(8),
  );

  /// Recovery/verification screens (title-less bar): back button → heading.
  static double get authRecoveryHeaderGap => adaptiveHeight(40);

  /// [authPagePadding] with the recovery header gap on top.
  static EdgeInsets get authRecoveryPagePadding =>
      authPagePadding.copyWith(top: authRecoveryHeaderGap);

  // Headings and text.
  static double get authTitleFont => adaptiveFont(32);
  static double get authSmallTitleFont => adaptiveFont(20);
  static double get authSmallSubtitleFont => adaptiveFont(14);
  static double get authBodyFont => adaptiveFont(16);
  static double get authCaptionFont => adaptiveFont(14);
  static double get authHintFont => adaptiveFont(13);

  // Vertical rhythm.
  /// Auth title → subtitle.
  static double get authSubtitleGap => adaptiveHeight(8);

  /// Auth title (or subtitle) → first field.
  static double get authTitleGap => adaptiveHeight(24);

  /// Between stacked auth fields.
  static double get authFieldGap => adaptiveHeight(20);

  /// Last auth field (or its helper row) → main button; Login's footer gap.
  static double get authActionGap => adaptiveHeight(32);

  /// Field → small helper below it ("Forgot Password?", password hint).
  static double get authHelperGap => adaptiveHeight(8);

  /// Sign Up last field → consent checkbox.
  static double get authConsentGap => adaptiveHeight(12);

  /// Sign Up main button/social row → "Already have an account?".
  static double get authSignUpFooterGap => adaptiveHeight(16);

  // Icons.
  static double get authIconSize => adaptiveRadius(24);
  static double get authHintIconSize => adaptiveRadius(16);
  static double get authHintIconGap => adaptiveWidth(6);

  // Social sign-in.
  static double get authDividerGap => adaptiveWidth(12);
  static double get authSocialDividerGap => adaptiveHeight(20);
  static double get authSocialButtonGap => adaptiveWidth(16);
  static double get authSocialButtonHeight =>
      adaptiveHeight(50).clamp(50.0, 58.0);
  static double get authSocialButtonPadding => adaptiveWidth(12);
  static double get authSocialIconGap => adaptiveWidth(12);

  // Consent checkbox.
  static double get authCheckboxRadius => adaptiveRadius(2);
  static const double authCheckboxBorderWidth = 2;

  // 4-digit code entry.
  static double get authPinCellSize => adaptiveRadius(60);
  static double get authPinSpacing => adaptiveWidth(16);
  static double get authPinFont => adaptiveFont(22);
  static const double authPinBorderWidth = 1;
  static const double authPinFocusedBorderWidth = 1.5;
  static double get authResendPadding => adaptiveWidth(2);
  static double get authTimerGap => adaptiveHeight(6);

  // "Password updated!" badge.
  static double get authSuccessRingSize => adaptiveRadius(96);
  static double get authSuccessDotSize => adaptiveRadius(72);
  static double get authSuccessIconSize => adaptiveRadius(36);
  static const double authSuccessRingWidth = 1.5;

  // "Email already exists" dialog (Sign Up).
  static EdgeInsets get authDialogInset => EdgeInsets.symmetric(
    horizontal: adaptiveWidth(24),
    vertical: adaptiveHeight(20),
  );
  static double get authDialogMaxWidth => adaptiveWidth(340);
  static double get authDialogRadius => adaptiveRadius(30);
  static EdgeInsets get authDialogPadding => EdgeInsets.fromLTRB(
    adaptiveWidth(24),
    adaptiveHeight(24),
    adaptiveWidth(24),
    adaptiveHeight(16),
  );
  static double get authDialogArtSize => adaptiveRadius(80);
  static double get authDialogArtGap => adaptiveHeight(18);
  static double get authDialogTitleFont => adaptiveFont(20);
  static double get authDialogTitleGap => adaptiveHeight(12);
  static double get authDialogBodyFont => adaptiveFont(14);
  static double get authDialogActionsGap => adaptiveHeight(24);
  static double get authDialogButtonGap => adaptiveHeight(8);
  static const EdgeInsets authDialogButtonPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );

  // ---------------------------------------------------------------------------
  // Chat voice notes (docs/figma/chat/voice_*.png): recording/preview pill,
  // trash + send row, and voice message bubbles.
  // ---------------------------------------------------------------------------
  static double get chatVoicePillHeight => adaptiveHeight(48);
  static double get chatVoicePillRadius => adaptiveRadius(24);
  static EdgeInsetsDirectional get chatVoicePillPadding =>
      EdgeInsetsDirectional.only(
        start: adaptiveWidth(8),
        end: adaptiveWidth(16),
      );

  /// Stop / play circle inside a pill or bubble.
  static double get chatVoiceButtonSize => adaptiveRadius(32);
  static double get chatVoiceIconSize => adaptiveRadius(20);
  static double get chatVoiceStopSize => adaptiveRadius(12);

  /// Trash glass circle and the send button under the pill.
  static double get chatVoiceActionSize => adaptiveRadius(48);
  static double get chatVoiceActionIconSize => adaptiveRadius(22);
  static double get chatVoiceRowGap => adaptiveHeight(12);
  static double get chatVoiceGap => adaptiveWidth(12);
  static double get chatVoiceWaveHeight => adaptiveHeight(22);
  static double get chatVoiceBarWidth => adaptiveWidth(2.5);
  static double get chatVoiceBarGap => adaptiveWidth(2.5);
  static double get chatVoiceTimerFont => adaptiveFont(16);
  static double get chatVoiceLabelFont => adaptiveFont(12);

  /// Voice message bubble.
  static double get chatVoiceBubbleWidth => adaptiveWidth(200);
  static EdgeInsetsDirectional get chatVoiceBubblePadding =>
      EdgeInsetsDirectional.fromSTEB(
        adaptiveWidth(4),
        adaptiveHeight(2),
        adaptiveWidth(16),
        adaptiveHeight(2),
      );

  /// Play button tap target in a bubble (the visible circle is smaller).
  static const double chatVoiceTapTarget = 44;

  /// Font Sizes
  static final double sp8 = 8.sp;
  static final double sp12 = 12.sp;
  static final double sp13 = 13.sp;
  static final double sp14 = 14.sp;
  static final double sp15 = 15.sp;
  static final double sp16 = 16.sp;
  static final double sp17 = 17.sp;
  static final double sp18 = 18.sp;
  static final double sp20 = 20.sp;
  static final double sp22 = 22.sp;
  static final double sp24 = 24.sp;
  static final double sp28 = 28.sp;
  static final double sp32 = 32.sp;
  static final double sp40 = 40.sp;
  static final double sp11 = 11.sp;

  /// Heights
  static final double h2 = 2.h;
  static final double h4 = 4.h;
  static final double h0_5 = 0.5.h;
  static final double h8 = 8.h;
  static final double h6 = 6.h;
  static final double h10 = 10.h;
  static final double h12 = 12.h;

  static final double h16 = 16.h;
  static final double h20 = 20.h;
  static final double h22 = 22.h;
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
  static final double h1 = 1.h;
  static final double h121 = 121.h;
  static final double h128 = 128.h;
  static final double h18 = 18.h;
  static final double h220 = 220.h;
  static final double h26 = 26.h;
  static final double h68 = 68.h;
  static final double h76 = 76.h;

  /// Width
  static final double w1 = 1.w;
  static final double w2 = 2.w;
  static final double w4 = 4.w;
  static final double w8 = 8.w;
  static final double w10 = 10.w;
  static final double w12 = 12.w;
  static final double w14 = 14.w;
  static final double w16 = 16.w;
  static final double w20 = 20.w;
  static final double w22 = 22.w;
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
  static final double w100 = 100.w;
  static final double w140 = 140.w;
  static final double w160 = 160.w;
  static final double w180 = 180.w;
  static final double w200 = 200.w;
  static final double w240 = 240.w;
  static final double w112 = 112.w;
  static final double w120 = 120.w;
  static final double w128 = 128.w;
  static final double w136 = 136.w;
  static final double w170 = 170.w;
  static final double w18 = 18.w;
  static final double w1_5 = 1.5.w;
  static final double w210 = 210.w;
  static final double w220 = 220.w;
  static final double w290 = 290.w;
  static final double w3 = 3.w;
  static final double w30 = 30.w;
  static final double w300 = 300.w;
  static final double w36 = 36.w;
  static final double w6 = 6.w;

  /// Padding Height
  static final double ph4 = 4.h;
  static final double ph6 = 6.h;
  static final double ph8 = 8.h;
  static final double ph10 = 10.h;
  static final double ph12 = 12.h;
  static final double ph14 = 14.h;
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
  static final double ph2 = 2.h;
  static final double ph28 = 28.h;

  /// Padding Width
  static final double pw6 = 6.w;
  static final double pw8 = 8.w;
  static final double pw12 = 12.w;
  static final double pw14 = 14.w;
  static final double pw16 = 16.w;
  static final double pw18 = 18.w;
  static final double pw20 = 20.w;
  static final double pw24 = 24.w;
  static final double pw10 = 10.w;
  static final double pw32 = 32.w;

  /// Radius
  static final double r2 = 2.r;
  static final double r4 = 4.r;
  static final double r8 = 8.r;
  static final double r10 = 10.r;
  static final double r12 = 12.r;
  static final double r16 = 16.r;
  static final double r20 = 20.r;
  static final double r22 = 22.r;
  static final double r24 = 24.r;
  static final double r26 = 26.r;
  static final double r28 = 28.r;
  static final double r30 = 30.r;
  static final double r50 = 50.r;
  static final double r60 = 60.r;
  static final double r64 = 64.r;
  static final double r11 = 11.r;
  static final double r48 = 48.r;
  static final double r6 = 6.r;
}
