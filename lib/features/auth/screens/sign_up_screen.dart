import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/features/auth/widgets/auth_app_bar.dart';
import 'package:travibe/core/constants/feature_flags.dart';
import 'package:travibe/features/auth/data/registration_error.dart';
import 'package:travibe/features/auth/widgets/email_exists_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/auth/cubit/auth_cubit.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/data/auth_repo.dart';
import 'package:travibe/features/auth/screens/auth_navigation.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/widgets/custom_or_login_widget.dart';
import 'package:travibe/features/auth/widgets/social_login_button.dart';
import 'package:travibe/features/auth/widgets/terms_privacy_checkbox.dart';
import 'package:travibe/root.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.authRepo, this.initialEmail = ''});
  final AuthRepo? authRepo;

  /// Prefilled when returning from the OTP step.
  final String initialEmail;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  TextEditingController nameController = TextEditingController();
  late final TextEditingController emailController = TextEditingController(
    text: widget.initialEmail,
  );
  TextEditingController passwordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final AuthRepo authRepo = widget.authRepo ?? AuthRepo();
  final _emailFocus = FocusNode();
  bool _emailDialogOpen = false;
  bool _agreedToTerms = false;
  bool _registering = false;
  final _googleCubit = AuthCubit();

  @override
  void dispose() {
    _googleCubit.close();
    _emailFocus.dispose();
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_registering || _emailDialogOpen || _googleCubit.state is AuthLoading) {
      return;
    }
    if (_formKey.currentState!.validate()) {
      if (!_agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please accept the Terms & Privacy Policy'),
          ),
        );
        return;
      }

      String email = emailController.text.trim();
      String password = passwordController.text.trim();
      String confirmPassword = confirmPasswordController.text.trim();

      setState(() => _registering = true);
      try {
        final authResponse = await authRepo.register(
          email: email,
          password: password,
          passwordConfirmation: confirmPassword,
          termsAccepted: _agreedToTerms,
          locale: PreferencesManager().getLanguage(),
        );

        if (!mounted) return;

        _continue(
          verificationRequired: authResponse.emailVerificationRequired,
          email: email,
        );
      } catch (e) {
        if (!mounted) return;
        if (e is ApiError && isDuplicateEmailError(e)) {
          await _emailExists();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiError ? e.message : 'Registration failed: $e',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _registering = false);
      }
    }
  }

  Future<void> _emailExists() async {
    if (_emailDialogOpen) return;
    _emailDialogOpen = true;
    // Remove keyboard insets before presenting the compact, scrollable dialog.
    FocusScope.of(context).unfocus();
    try {
      final action = await showEmailExistsDialog(context);
      if (!mounted) return;
      if (action == EmailExistsAction.login) {
        // TODO(back-button-auth): if this email is still unverified, return
        // to OTP with "Resend code" instead (docs/AUTH_BACK_NAVIGATION.md).
        AuthNavigation.toLogin(context, email: emailController.text.trim());
      } else if (action == EmailExistsAction.anotherEmail) {
        _emailFocus.requestFocus();
        emailController.selection = TextSelection.collapsed(
          offset: emailController.text.length,
        );
      }
    } finally {
      _emailDialogOpen = false;
    }
  }

  /// OTP is pushed so back returns here with the form intact; a finished
  /// signup clears the auth stack.
  void _continue({required bool verificationRequired, required String email}) {
    if (verificationRequired) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => OtpVerificationScreen(email: email),
        ),
      );
    } else {
      AuthNavigation.resetTo(context, (_) => Root(), name: AppRoutes.root);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Login normally sits beneath Signup; if not, back still leads to Login.
    canPop: ModalRoute.of(context)?.canPop ?? false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) AuthNavigation.toLogin(context);
    },
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      bloc: _googleCubit,
      listener: (context, state) {
        if (state is AuthSuccess) {
          final response = state.response!;
          _continue(
            verificationRequired: response.emailVerificationRequired,
            email: response.user.email,
          );
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
        }
      },
      child: ColoredBox(
        color: DarkColors.backgroundColor,
        child: SafeArea(
          child: Scaffold(
            backgroundColor: DarkColors.backgroundColor,
            appBar: AuthAppBar(
              title: 'Sign Up',
              onBack: () => AuthNavigation.backToLogin(context),
            ),
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.adaptiveWidth(8),
                  AppSizes.adaptiveHeight(24),
                  AppSizes.adaptiveWidth(8),
                  AppSizes.adaptiveHeight(8),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create\nyour account',
                        style: TextStyle(
                          fontSize: AppSizes.adaptiveFont(24),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      // CustomTextField(
                      //   controller: nameController,
                      //   validator: (value) {
                      //     if (value == null || value.trim().isEmpty) {
                      //       return 'Please enter your name';
                      //     }

                      //     return null;
                      //   },
                      //   title: 'Name',
                      //   prefixIcon: SvgPicture.asset(
                      //     'assets/images/auth/sms.svg',
                      //     width: 24,
                      //     height: 24,
                      //   ),
                      //   hintText: 'Enter your name',
                      // ),
                      SizedBox(height: AppSizes.adaptiveHeight(16)),
                      CustomTextField(
                        controller: emailController,
                        focusNode: _emailFocus,
                        validator: (value) {
                          final RegExp emailRegex = RegExp(
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
                        title: 'Email',
                        prefixIcon: SvgPicture.asset(
                          'assets/images/auth/sms.svg',
                          width: AppSizes.adaptiveRadius(24),
                          height: AppSizes.adaptiveRadius(24),
                        ),
                        hintText: 'Enter your email',
                      ),
                      SizedBox(height: AppSizes.adaptiveHeight(16)),
                      CustomTextField(
                        controller: passwordController,
                        validator: (value) {
                          final RegExp passwordRegex = RegExp(
                            r'^(?=.*[A-Za-z])(?=.*\d).{8,}$',
                          );
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }

                          if (!passwordRegex.hasMatch(value)) {
                            return 'Password must be at least 8 characters and contain a letter and a number';
                          }

                          return null;
                        },
                        title: 'Password',
                        prefixIcon: SvgPicture.asset(
                          'assets/images/auth/lock.svg',
                          width: AppSizes.adaptiveRadius(24),
                          height: AppSizes.adaptiveRadius(24),
                        ),
                        hintText: 'Enter your password',
                        obscureText: true,
                        passwordVisibilityToggle: true,
                      ),
                      SizedBox(height: AppSizes.adaptiveHeight(16)),
                      CustomTextField(
                        controller: confirmPasswordController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }

                          if (value != passwordController.text) {
                            return 'Passwords do not match';
                          }

                          return null;
                        },
                        title: 'Confirm Password',
                        prefixIcon: SvgPicture.asset(
                          'assets/images/auth/lock.svg',
                          width: AppSizes.adaptiveRadius(24),
                          height: AppSizes.adaptiveRadius(24),
                        ),
                        hintText: 'Re-enter your password',
                        obscureText: true,
                        passwordVisibilityToggle: true,
                      ),
                      SizedBox(height: AppSizes.adaptiveHeight(12)),
                      TermsAndPrivacyCheckbox(
                        onChanged: (value) {
                          setState(() {
                            _agreedToTerms = value;
                          });
                        },
                      ),
                      SizedBox(height: AppSizes.adaptiveHeight(24)),
                      CustomButton(
                        title: 'Sign Up',
                        onPressed: _registering || _emailDialogOpen
                            ? null
                            : _register,
                      ),
                      if (kEnableSocialAuthentication) ...[
                        SizedBox(height: AppSizes.adaptiveHeight(32)),
                        CustomOrLoginWidget(),
                        SizedBox(height: AppSizes.adaptiveHeight(20)),
                        Row(
                          children: [
                            BlocBuilder<AuthCubit, AuthState>(
                              bloc: _googleCubit,
                              builder: (_, state) => SocialLoginButton(
                                title: 'Google',
                                iconPath: 'assets/images/auth/google.svg',
                                onPressed: _registering || state is AuthLoading
                                    ? null
                                    : _googleCubit.loginWithGoogle,
                              ),
                            ),

                            SizedBox(width: AppSizes.adaptiveWidth(16)),

                            SocialLoginButton(
                              title: 'Apple',
                              iconPath: 'assets/images/auth/apple.svg',
                              onPressed: () {
                                // Apple login
                              },
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: AppSizes.adaptiveHeight(16)),
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Already have an account?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: AppSizes.adaptiveFont(16),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  AuthNavigation.backToLogin(context),
                              child: Text(
                                'Login',
                                style: TextStyle(
                                  color: DarkColors.primaryColor,
                                  fontSize: AppSizes.adaptiveFont(16),
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
        ),
      ),
    );
  }
}
