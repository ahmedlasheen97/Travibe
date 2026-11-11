import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      // TODO: wire to AuthRepo, e.g.:
      // await AuthRepo().changePassword(
      //   currentPassword: _currentPasswordController.text,
      //   newPassword: _newPasswordController.text,
      //   newPasswordConfirmation: _confirmPasswordController.text,
      // );
      debugPrint('Updating password...');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update password: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
                  children: [
                    SizedBox(height: AppSizes.h8),
                    _buildTopBar(),
                    SizedBox(height: AppSizes.h24),
                    _buildLabel('Current password.'),
                    SizedBox(height: AppSizes.h8),
                    _passwordField(
                      controller: _currentPasswordController,
                      hint: 'enter your current password',
                      obscure: _obscureCurrent,
                      onToggle: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your current password';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: AppSizes.h24),
                    _buildLabel('New Password'),
                    SizedBox(height: AppSizes.h8),
                    _passwordField(
                      controller: _newPasswordController,
                      hint: 'enter your new password',
                      obscure: _obscureNew,
                      onToggle: () =>
                          setState(() => _obscureNew = !_obscureNew),
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
                    SizedBox(height: AppSizes.h24),
                    _buildLabel('Confirm New Password'),
                    SizedBox(height: AppSizes.h8),
                    _passwordField(
                      controller: _confirmPasswordController,
                      hint: 'renter your new password',
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: (value) {
                        if (value != _newPasswordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.pw20,
                  AppSizes.ph12,
                  AppSizes.pw20,
                  AppSizes.ph20,
                ),
                child: _buildUpdateButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: AppSizes.h40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Change Password',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.sp17,
              fontWeight: FontWeight.w700,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: BackButtonWidget(
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: AppSizes.sp14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: Colors.white54,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.white54,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: EdgeInsets.symmetric(vertical: AppSizes.ph14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r28),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r28),
          borderSide: const BorderSide(color: Color(0xFFDB4A3D)),
        ),
      ),
    );
  }

  Widget _buildUpdateButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.h56,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _updatePassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: _isSubmitting
            ? SizedBox(
                width: AppSizes.w22,
                height: AppSizes.h22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text('Update Password', style: ActionButtonStyle.label),
      ),
    );
  }
}
