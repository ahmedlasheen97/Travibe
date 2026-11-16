import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
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
      _pinController.triggerError();
      if (!mounted) return;
      if (_custom) {
        TravibeToast.show(
          context,
          TravibeToastData.error(
            e is ApiError ? e.message : 'Verification failed. Please retry.',
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Verification failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;

    try {
      if (widget.onResend case final resend?) {
        await resend();
      } else {
        await _authRepo.resendVerificationCode(email: widget.email);
      }
      _pinController.clear();
      _startTimer();
      if (!mounted) return;
      if (_custom) {
        TravibeToast.show(
          context,
          const TravibeToastData.success('A new code has been sent'),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new code has been sent to your email'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (_custom) {
        TravibeToast.show(
          context,
          TravibeToastData.error(
            e is ApiError ? e.message : 'Unable to resend the code.',
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to resend code: $e')));
      }
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
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.adaptiveWidth(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: AppSizes.adaptiveHeight(8)),
                BackButtonWidget(onTap: _back),
                SizedBox(height: AppSizes.adaptiveHeight(40)),
                Center(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.adaptiveFont(22),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(12)),
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Please enter the 4-digit code we sent to your email',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: AppSizes.adaptiveFont(14),
                        ),
                      ),
                      SizedBox(height: AppSizes.adaptiveHeight(4)),
                      Text(
                        _maskedEmail,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppSizes.adaptiveFont(14),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(40)),
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
                      cellSize: Size.square(AppSizes.adaptiveRadius(60)),
                      spacing: AppSizes.adaptiveWidth(16),
                      borderWidth: 1,
                      focusedBorderWidth: 1.5,
                      borderColor: const Color(0xFF2E2E2E),
                      focusedBorderColor: DarkColors.primaryColor,
                      filledBorderColor: DarkColors.primaryColor,
                      fillColor: const Color(0xFF1C1C1C),
                      focusedFillColor: const Color(0xFF1C1C1C),
                      filledFillColor: const Color(0xFF1C1C1C),
                      textStyle: TextStyle(
                        color: Colors.white,
                        fontSize: AppSizes.adaptiveFont(22),
                        fontWeight: FontWeight.w600,
                      ),
                      errorColor: Colors.redAccent,
                      enableErrorShake: true,
                    ),
                  ),
                ),
                SizedBox(height: AppSizes.adaptiveHeight(40)),
                _buildVerifyButton(),
                SizedBox(height: AppSizes.adaptiveHeight(24)),
                Center(child: _buildResendRow()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.adaptiveHeight(56).clamp(56, 64),
      child: ElevatedButton(
        onPressed: _isVerifying ? null : _verify,
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: _isVerifying
            ? SizedBox(
                width: AppSizes.adaptiveRadius(22),
                height: AppSizes.adaptiveRadius(22),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text('Verify', style: ActionButtonStyle.label),
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
                fontSize: AppSizes.adaptiveFont(14),
              ),
            ),
            TextButton(
              onPressed: _resendOtp,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.adaptiveWidth(2),
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
                  fontSize: AppSizes.adaptiveFont(14),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: AppSizes.adaptiveHeight(6)),
        Text(
          _formattedTime,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: AppSizes.adaptiveFont(14),
          ),
        ),
      ],
    );
  }
}
