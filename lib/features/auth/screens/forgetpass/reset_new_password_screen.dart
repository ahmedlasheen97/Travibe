import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/forgetpass/create_new_password_screen.dart';

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
      _pinController.triggerError();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Verification failed: $e')));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;

    try {
      await _authRepo.forgotPassword(email: widget.email);
      _pinController.clear();
      _startTimer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent to your email')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to resend code: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildBackButton(),
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'Verify your email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Please enter the 4-digit code we sent to your email',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maskedEmail,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
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
                    cellSize: const Size(60, 60),
                    spacing: 16,
                    borderWidth: 1,
                    focusedBorderWidth: 1.5,
                    borderColor: const Color(0xFF2E2E2E),
                    focusedBorderColor: DarkColors.primaryColor,
                    filledBorderColor: DarkColors.primaryColor,
                    fillColor: const Color(0xFF1C1C1C),
                    focusedFillColor: const Color(0xFF1C1C1C),
                    filledFillColor: const Color(0xFF1C1C1C),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                    errorColor: Colors.redAccent,
                    enableErrorShake: true,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _buildVerifyButton(),
              const SizedBox(height: 24),
              Center(child: _buildResendRow()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return BackButtonWidget(
      onTap: () => Navigator.of(context).maybePop(),
      size: 44,
      iconSize: 18,
    );
  }

  Widget _buildVerifyButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isVerifying ? null : _verify,
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: _isVerifying
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text('Verify', style: ActionButtonStyle.label),
      ),
    );
  }

  Widget _buildResendRow() {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
            children: [
              const TextSpan(text: "Didn't get OTP? "),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: _resendOtp,
                  child: Text(
                    'Resend OTP',
                    style: TextStyle(
                      color: _canResend
                          ? DarkColors.primaryColor
                          : DarkColors.primaryColor.withValues(alpha: 0.4),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _formattedTime,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
