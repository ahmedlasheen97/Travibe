import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
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
        ), // fixed
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
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.adaptiveWidth(24),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: AppSizes.adaptiveHeight(8)),
                  const BackButtonWidget(),
                  SizedBox(height: AppSizes.adaptiveHeight(40)),
                  Center(
                    child: Text(
                      'Forgot your password?',
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
                      "No worries! Enter your email address and we'll send you a verification code to reset your password.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: AppSizes.adaptiveFont(14),
                        height: 1.4,
                      ),
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(32)),
                  CustomTextField(
                    title: 'Email',
                    controller: _emailController,
                    hintText: 'enter your email',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: SvgPicture.asset(
                      'assets/images/auth/sms.svg',
                      width: AppSizes.adaptiveRadius(24),
                      height: AppSizes.adaptiveRadius(24),
                    ),
                    validator: (value) {
                      final emailRegex = RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$',
                      );
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(24)),
                  CustomButton(
                    title: _isSubmitting ? 'Sending...' : 'Send Code',
                    onPressed: _isSubmitting ? null : _sendCode,
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(20)),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Remember your password? ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: AppSizes.adaptiveFont(14),
                          ),
                        ),
                        GestureDetector(
                          // Login sits beneath; don't stack a second one.
                          onTap: () => AuthNavigation.backToLogin(context),
                          child: Text(
                            'Log In',
                            style: TextStyle(
                              color: DarkColors.primaryColor,
                              fontSize: AppSizes.adaptiveFont(14),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
