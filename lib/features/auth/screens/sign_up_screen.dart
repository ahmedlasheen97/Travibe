import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/routing/app_routes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
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
import 'package:travibe/features/auth/screens/login_screen.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';
import 'package:travibe/features/auth/widgets/custom_or_login_widget.dart';
import 'package:travibe/features/auth/widgets/social_login_button.dart';
import 'package:travibe/features/auth/widgets/terms_privacy_checkbox.dart';
import 'package:travibe/root.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.authRepo});
  final AuthRepo? authRepo;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
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

        if (authResponse.emailVerificationRequired) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => OtpVerificationScreen(email: email),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Root()),
          );
        }
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
        final email = emailController.text.trim();
        final router = GoRouter.maybeOf(context);
        if (router != null &&
            router.routerDelegate.currentConfiguration.uri.path !=
                AppRoutes.login) {
          final previousRoute = ModalRoute.of(context);
          final navigator = Navigator.of(context);
          router.go(
            Uri(
              path: AppRoutes.login,
              queryParameters: {'email': email},
            ).toString(),
          );
          // A Navigator replacement may sit above the router's former signup
          // page. Remove that old imperative route after Login is installed.
          if (previousRoute != null && previousRoute.settings is! Page) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (navigator.mounted && previousRoute.isActive) {
                navigator.removeRoute(previousRoute);
              }
            });
          }
        } else if (router != null) {
          // Signup may have imperatively replaced the /login page. Reset that
          // navigator instead of reusing a missing GoRouter page or stacking it.
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => LoginScreen(initialEmail: email),
            ),
            (_) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => LoginScreen(initialEmail: email),
              settings: const RouteSettings(name: AppRoutes.login),
            ),
            (_) => false,
          );
        }
      } else if (action == EmailExistsAction.anotherEmail) {
        _emailFocus.requestFocus();
        emailController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: emailController.text.length,
        );
      }
    } finally {
      _emailDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      bloc: _googleCubit,
      listener: (context, state) {
        if (state is AuthSuccess) {
          final response = state.response!;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => response.emailVerificationRequired
                  ? OtpVerificationScreen(email: response.user.email)
                  : Root(),
            ),
          );
        } else if (state is AuthFailure) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
        }
      },
      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(
            leading: const BackButtonWidget(),
            title: Text('Sign Up', style: TextStyle(color: Colors.white)),
          ),
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create\nyour account',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 16),
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
                    SizedBox(height: 16),
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
                        width: 24,
                        height: 24,
                      ),
                      hintText: 'Enter your email',
                    ),
                    SizedBox(height: 16),
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
                        width: 24,
                        height: 24,
                      ),
                      hintText: 'Enter your password',
                      obscureText: true,
                      passwordVisibilityToggle: true,
                    ),
                    SizedBox(height: 16),
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
                        width: 24,
                        height: 24,
                      ),
                      hintText: 'Re-enter your password',
                      obscureText: true,
                      passwordVisibilityToggle: true,
                    ),
                    SizedBox(height: 12),
                    TermsAndPrivacyCheckbox(
                      onChanged: (value) {
                        setState(() {
                          _agreedToTerms = value;
                        });
                      },
                    ),
                    SizedBox(height: 24),
                    CustomButton(
                      title: 'Sign Up',
                      onPressed: _registering || _emailDialogOpen
                          ? null
                          : _register,
                    ),
                    SizedBox(height: 32),
                    CustomOrLoginWidget(),
                    SizedBox(height: 20),
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

                        const SizedBox(width: 16),

                        SocialLoginButton(
                          title: 'Apple',
                          iconPath: 'assets/images/auth/apple.svg',
                          onPressed: () {
                            // Apple login
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: AppSizes.h35),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account?',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoginScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Login',
                            style: TextStyle(
                              color: DarkColors.primaryColor,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
