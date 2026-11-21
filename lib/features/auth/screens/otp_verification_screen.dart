import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/auth/widgets/auth_heading.dart';
import 'package:travibe/features/auth/widgets/auth_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/features/auth/screens/auth_navigation.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';

/// Toast text for a failed signup/reset code. Any 422 (wrong, invalid or
/// expired code; the server sends one generic "Invalid or expired code.") is
/// a wrong code. Other failures show their user-facing message.
String otpFailureMessage(Object error) {
  if (error is! ApiError || error.statusCode != 422) {
    return ApiError.messageOf(error);
  }
  return otpWrongMessage;
}

const otpWrongMessage = 'Wrong OTP Try Again';
const otpTooManyMessage = 'Too many attempts. Tap Resend OTP';

/// The server invalidates a code after five wrong attempts.
const otpMaxAttempts = 5;

/// Wrong attempts on the current code, counted on the device because the
/// server does not report them.
class OtpAttempts {
  int _wrong = 0;

  int get wrong => _wrong;

  /// The code is spent: Verify stays disabled until a new code is sent.
  bool get locked => _wrong >= otpMaxAttempts;

  /// A new code was sent (resend): attempts back to zero.
  void reset() => _wrong = 0;

  /// Records a failed verify and returns the toast text. Only a wrong code
  /// (a 422) counts; the fifth one locks.
  String fail(Object error) {
    final message = otpFailureMessage(error);
    if (message != otpWrongMessage) return message;
    _wrong++;
    return locked ? otpTooManyMessage : otpWrongMessage;
  }
}

/// 4-digit code entry. Defaults to signup verification (then Profile setup);
/// other flows (e.g. changing email) pass [onVerify], [onResend] and
/// [onVerified].
class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String title;
  final AuthRepo? authRepo;

  /// Verifies the code; throws (e.g. [ApiError]) when it is wrong.
  final Future<void> Function(String code)? onVerify;

  /// Sends a fresh code.
  final Future<void> Function()? onResend;

  /// Runs after a successful [onVerify]; defaults to popping `true`.
  final void Function(BuildContext context)? onVerified;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    this.title = 'Verify your email',
    this.authRepo,
    this.onVerify,
    this.onResend,
    this.onVerified,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final PinInputController _pinController = PinInputController();
  late final AuthRepo _authRepo = widget.authRepo ?? AuthRepo();
  bool get _custom => widget.onVerify != null;

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
    if (!_custom && _attempts.locked) {
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
      if (widget.onVerify case final verify?) {
        await verify(_enteredOtp);
        if (!mounted) return;
        final done = widget.onVerified;
        done == null ? Navigator.pop(context, true) : done(context);
        return;
      }
      await _authRepo.verifyEmailCode(email: widget.email, code: _enteredOtp);
      if (!mounted) return;
      // The account now exists: no way back to Signup or OTP.
      AuthNavigation.resetTo(
        context,
        (_) => const ProfileSetupScreen(),
        name: AppRoutes.profileSetup,
      );
    } catch (e) {
      if (!mounted) return;
      // Email change keeps the server text: its 422 may also mean the
      // address was taken.
      TravibeToast.show(
        context,
        TravibeToastData.error(
          _custom ? ApiError.messageOf(e) : _attempts.fail(e),
        ),
      );
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
      if (widget.onResend case final resend?) {
        await resend();
      } else {
        await _authRepo.resendVerificationCode(email: widget.email);
      }
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

  /// Back returns to the step that opened OTP (Signup or Login keep the
  /// email). Opened at startup there is none, so Signup is rebuilt with it.
  void _back() => AuthNavigation.back(
    context,
    () => AuthNavigation.toSignup(context, email: widget.email),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: ModalRoute.of(context)?.canPop ?? false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    return AuthPage.recovery(
      onBack: _back,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthHeading.small(
            widget.title,
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
            onPressed: _isVerifying || (!_custom && _attempts.locked)
                ? null
                : _verify,
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
