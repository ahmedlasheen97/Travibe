import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/profile/cubit/change_password_cubit.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.repo});

  final AuthRepo? repo;

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
  late final _cubit = ChangePasswordCubit(repo: widget.repo);

  @override
  void initState() {
    super.initState();
    for (final (controller, field) in [
      (_currentPasswordController, PasswordField.current),
      (_newPasswordController, PasswordField.password),
      (_confirmPasswordController, PasswordField.confirmation),
    ]) {
      controller.addListener(() => _cubit.clearFieldError(field));
    }
  }

  @override
  void dispose() {
    _cubit.close();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updatePassword() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _cubit.submit(
      currentPassword: _currentPasswordController.text,
      password: _newPasswordController.text,
      passwordConfirmation: _confirmPasswordController.text,
    );
  }

  void _onState(BuildContext context, ChangePasswordState state) {
    if (state.done) {
      final toast = TravibeToast.of(context);
      Navigator.of(context).pop();
      toast.present(const TravibeToastData.success('Password updated'));
    } else if (state.error case final message?) {
      TravibeToast.show(context, TravibeToastData.error(message));
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ChangePasswordCubit, ChangePasswordState>(
        bloc: _cubit,
        listener: _onState,
        builder: (context, state) => _buildBody(state),
      );

  Widget _buildBody(ChangePasswordState state) {
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
                      serverError: state.fieldErrors[PasswordField.current],
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
                      serverError: state.fieldErrors[PasswordField.password],
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
                      serverError:
                          state.fieldErrors[PasswordField.confirmation],
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
                child: _buildUpdateButton(state.submitting || state.done),
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
    String? serverError,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
      validator: validator,
      cursorColor: Colors.white,
      decoration: InputDecoration(
        hintText: hint,
        errorText: serverError,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: Colors.white54,
        ),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show password' : 'Hide password',
          icon: PasswordEye.icon(obscured: obscure),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: EdgeInsets.symmetric(vertical: AppSizes.ph14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildUpdateButton(bool busy) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.h56,
      child: ElevatedButton(
        onPressed: busy ? null : _updatePassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: busy
            ? SizedBox(
                width: AppSizes.w22,
                height: AppSizes.h22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text('Update Password', style: ActionButtonStyle.label),
      ),
    );
  }
}
