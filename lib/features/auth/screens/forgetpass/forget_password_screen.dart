import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/theme/app_styles.dart';
import 'package:travibe/features/auth/widgets/auth_heading.dart';
import 'package:travibe/features/auth/widgets/auth_page.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/forgetpass/reset_new_password_screen.dart';
import 'package:travibe/features/auth/screens/auth_navigation.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final AuthRepo _authRepo = AuthRepo();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final email = _emailController.text.trim();
      await _authRepo.forgotPassword(email: email);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResetPasswordOtpScreen(email: email),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      TravibeToast.show(context, TravibeToastData.error(ApiError.messageOf(e)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage.recovery(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthHeading.small(
              'Forgot your password?',
              subtitle:
                  "No worries! Enter your email address and we'll send you a verification code to reset your password.",
            ),
            SizedBox(height: AppSizes.authTitleGap),
            CustomTextField(
              title: 'Email',
              controller: _emailController,
              hintText: 'Enter your email',
              keyboardType: TextInputType.emailAddress,
              prefixIcon: SvgPicture.asset(
                'assets/images/auth/sms.svg',
                width: AppSizes.authIconSize,
                height: AppSizes.authIconSize,
              ),
              validator: (value) {
                final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$');
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!emailRegex.hasMatch(value.trim())) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
            SizedBox(height: AppSizes.authActionGap),
            CustomButton(
              title: _isSubmitting ? 'Sending...' : 'Send Code',
              onPressed: _isSubmitting ? null : _sendCode,
            ),
            SizedBox(height: AppSizes.authActionGap),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Remember your password?',
                    style: AppStyles.grey16MediumStyle.copyWith(
                      fontSize: AppSizes.authBodyFont,
                    ),
                  ),
                  TextButton(
                    // Login sits beneath; don't stack a second one.
                    onPressed: () => AuthNavigation.backToLogin(context),
                    child: Text(
                      'Log In',
                      style: AppStyles.orange16MediumStyle.copyWith(
                        fontSize: AppSizes.authBodyFont,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
