import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/auth/widgets/auth_heading.dart';
import 'package:travibe/features/auth/widgets/auth_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/forgetpass/create_new_password_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';

class ResetPasswordOtpScreen extends StatefulWidget {
  final String email;

  const ResetPasswordOtpScreen({super.key, required this.email});

  @override
  State<ResetPasswordOtpScreen> createState() => _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends State<ResetPasswordOtpScreen> {
  final PinInputController _pinController = PinInputController();
  final AuthRepo _authRepo = AuthRepo();

  Timer? _timer;
  int _secondsRemaining = 0;
  bool get _canResend => _secondsRemaining == 0;
  String _enteredOtp = '';
  bool _isVerifying = false;
  final _attempts = OtpAttempts();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _secondsRemaining = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  String get _formattedTime {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get _maskedEmail {
    final parts = widget.email.split('@');
    if (parts.length != 2 || parts[0].length < 2) return widget.email;
    final name = parts[0];
    final visible = name.substring(0, 2);
    final masked = '*' * (name.length - 2).clamp(0, 8);
    return '$visible$masked@${parts[1]}';
  }

  Future<void> _verify() async {
    if (_enteredOtp.length < 4 || _isVerifying) return;
    if (_attempts.locked) {
      TravibeToast.show(
        context,
        const TravibeToastData.error(otpTooManyMessage),
      );
      // Not synchronously: this runs inside the field's onCompleted, and a
      // clear there leaves the field thinking it is still full, so the next
      // code would never complete.
      scheduleMicrotask(() {
        if (mounted) _retype();
      });
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final token = await _authRepo.verifyResetCode(
        email: widget.email,
        code: _enteredOtp,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CreateNewPasswordScreen(email: widget.email, token: token),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TravibeToast.show(context, TravibeToastData.error(_attempts.fail(e)));
      _retype();
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  /// Empties the boxes and focuses the first so the user can type again.
  void _retype() {
    _enteredOtp = '';
    _pinController
      ..clear()
      ..requestFocus();
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;

    try {
      await _authRepo.forgotPassword(email: widget.email);
      _attempts.reset();
      _startTimer();
      if (!mounted) return;
      _retype();
      TravibeToast.show(
        context,
        const TravibeToastData.success(
          'A new code has been sent to your email',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TravibeToast.show(context, TravibeToastData.error(ApiError.messageOf(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage.recovery(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthHeading.small(
            'Verify your email',
            subtitle: 'Please enter the 4-digit code we sent to your email',
          ),
          SizedBox(height: AppSizes.authSubtitleGap),
          SizedBox(
            width: double.infinity,
            child: Text(
              _maskedEmail,
              textAlign: TextAlign.center,
              style: AuthHeading.smallSubtitleStyle.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(height: AppSizes.authTitleGap),
          Center(
            child: MaterialPinField(
              length: 4,
              pinController: _pinController,
              autoFocus: true,
              onChanged: (value) => _enteredOtp = value,
              onCompleted: (value) {
                _enteredOtp = value;
                _verify();
              },
              theme: MaterialPinTheme(
                shape: MaterialPinShape.circle,
                cellSize: Size.square(AppSizes.authPinCellSize),
                spacing: AppSizes.authPinSpacing,
                borderWidth: AppSizes.authPinBorderWidth,
                focusedBorderWidth: AppSizes.authPinFocusedBorderWidth,
                borderColor: const Color(0xFF2E2E2E),
                focusedBorderColor: DarkColors.primaryColor,
                filledBorderColor: DarkColors.primaryColor,
                fillColor: const Color(0xFF1C1C1C),
                focusedFillColor: const Color(0xFF1C1C1C),
                filledFillColor: const Color(0xFF1C1C1C),
                textStyle: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.authPinFont,
                  fontWeight: FontWeight.w600,
                ),
                // Error state is a thin danger border, never a fill.
                cursorColor: Colors.white,
                errorColor: DarkColors.dangerColor,
                errorFillColor: const Color(0xFF1C1C1C),
                enableErrorShake: false,
              ),
            ),
          ),
          SizedBox(height: AppSizes.authActionGap),
          CustomButton(
            title: _isVerifying ? 'Verifying...' : 'Verify',
            onPressed: _isVerifying || _attempts.locked ? null : _verify,
          ),
          SizedBox(height: AppSizes.authActionGap),
          Center(child: _buildResendRow()),
        ],
      ),
    );
  }

  Widget _buildResendRow() {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              "Didn't get OTP? ",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: AppSizes.authCaptionFont,
              ),
            ),
            TextButton(
              onPressed: _resendOtp,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.authResendPadding,
                ),
                minimumSize: const Size(
                  kMinInteractiveDimension,
                  kMinInteractiveDimension,
                ),
              ),
              child: Text(
                'Resend OTP',
                style: TextStyle(
                  color: _canResend
                      ? DarkColors.primaryColor
                      : DarkColors.primaryColor.withValues(alpha: 0.4),
                  fontSize: AppSizes.authCaptionFont,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSizes.authTimerGap),
        Text(
          _formattedTime,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: AppSizes.authCaptionFont,
          ),
        ),
      ],
    );
  }
}
