import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/features/auth/screens/auth_navigation.dart';

class CreateNewPasswordScreen extends StatefulWidget {
  final String email;
  final String token;

  const CreateNewPasswordScreen({
    super.key,
    required this.email,
    required this.token,
    this.authRepo,
  });
  final AuthRepo? authRepo;

  @override
  State<CreateNewPasswordScreen> createState() =>
      _CreateNewPasswordScreenState();
}

class _CreateNewPasswordScreenState extends State<CreateNewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final AuthRepo _authRepo = widget.authRepo ?? AuthRepo();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;
  bool _isSuccess = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await _authRepo.resetPassword(
        token: widget.token,
        email: widget.email,
        password: _passwordController.text,
        passwordConfirmation: _confirmPasswordController.text,
      );
      if (!mounted) return;
      setState(() => _isSuccess = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reset password: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _confirmOpen = false;

  void _toLogin() => AuthNavigation.toLogin(context, email: widget.email);

  /// The reset code is spent, so back never returns to OTP: before the new
  /// password is saved it asks to cancel the reset; afterwards it goes to Login.
  Future<void> _back() async {
    if (_isSuccess) return _toLogin();
    if (_confirmOpen) return;
    _confirmOpen = true;
    final cancel = await showGlassConfirmDialog(
      context,
      title: 'Cancel password reset?',
      message: "Your new password won't be saved. You'll return to Login.",
      confirmLabel: 'Cancel reset',
      cancelLabel: 'Continue',
    );
    _confirmOpen = false;
    if (cancel && mounted) _toLogin();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        body: SafeArea(
          child: _isSuccess ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(24)),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: AppSizes.adaptiveHeight(8)),
              BackButtonWidget(onTap: _back),
              SizedBox(height: AppSizes.adaptiveHeight(40)),
              Center(
                child: Text(
                  'Create new password',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.adaptiveFont(22),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(12)),
              Center(
                child: Text(
                  'Your new password must be different from your previous password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: AppSizes.adaptiveFont(14),
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(32)),
              Text(
                'New Password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.adaptiveFont(14),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(8)),
              _passwordField(
                controller: _passwordController,
                hint: 'enter your password',
                obscure: _obscurePassword,
                onToggle: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a new password';
                  }
                  if (value.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              SizedBox(height: AppSizes.adaptiveHeight(20)),
              Text(
                'Confirm Password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.adaptiveFont(14),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(8)),
              _passwordField(
                controller: _confirmPasswordController,
                hint: 'renter your password',
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              SizedBox(height: AppSizes.adaptiveHeight(10)),
              _buildPasswordHint(),
              SizedBox(height: AppSizes.adaptiveHeight(24)),
              CustomButton(
                title: _isSubmitting ? 'Resetting...' : 'Reset Password',
                onPressed: _isSubmitting ? null : _resetPassword,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordHint() {
    final meetsLength = _passwordController.text.length >= 8;
    return Row(
      children: [
        Icon(
          meetsLength ? Icons.check_circle : Icons.info_outline,
          color: meetsLength ? Colors.greenAccent : Colors.white54,
          size: AppSizes.adaptiveRadius(16),
        ),
        SizedBox(width: AppSizes.adaptiveWidth(6)),
        Expanded(
          child: Text(
            'At least 8 characters',
            style: TextStyle(
              color: meetsLength ? Colors.greenAccent : Colors.white54,
              fontSize: AppSizes.adaptiveFont(13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required ValueChanged<String> onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: TextStyle(
        color: Colors.white,
        fontSize: AppSizes.adaptiveFont(14),
      ),
      validator: validator,
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white54),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show password' : 'Hide password',
          icon: PasswordEye.icon(obscured: obscure),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: EdgeInsets.symmetric(
          vertical: AppSizes.adaptiveHeight(14),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(28)),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(28)),
          borderSide: const BorderSide(color: Color(0xFFDB4A3D)),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reset finished: no back button (Android back goes to Login);
            // keep the space it used so the layout doesn't shift.
            SizedBox(height: AppSizes.adaptiveHeight(8 + 44 + 60)),
            Center(
              child: Container(
                width: AppSizes.adaptiveRadius(96),
                height: AppSizes.adaptiveRadius(96),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: AppSizes.adaptiveRadius(72),
                    height: AppSizes.adaptiveRadius(72),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: AppSizes.adaptiveRadius(36),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(24)),
            Center(
              child: Text(
                'Password updated!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.adaptiveFont(22),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(12)),
            Center(
              child: Text(
                'Your password has been changed successfully. You can now log in with your new password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: AppSizes.adaptiveFont(14),
                  height: 1.4,
                ),
              ),
            ),
            SizedBox(height: AppSizes.adaptiveHeight(32)),
            CustomButton(title: 'Log In Now', onPressed: _toLogin),
          ],
        ),
      ),
    );
  }
}
