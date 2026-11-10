import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/app_styles.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/cubit/auth_cubit.dart';
import 'package:travibe/features/auth/screens/forgetpass/forget_password_screen.dart';
import 'package:travibe/features/auth/screens/sign_up_screen.dart';
import 'package:travibe/features/auth/widgets/custom_or_login_widget.dart';
import 'package:travibe/features/auth/widgets/social_login_button.dart';
import 'package:travibe/root.dart';
import 'package:travibe/features/auth/screens/otp_verification_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>(
      create: (context) => AuthCubit()..emailController.text = initialEmail,
      child: Builder(
        builder: (context) {
          final cubit = context.read<AuthCubit>();

          return SafeArea(
            child: Scaffold(
              appBar: AppBar(
                leading: const BackButtonWidget(),
                title: const Text(
                  'Login',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              body: BlocListener<AuthCubit, AuthState>(
                listener: (context, state) {
                  if (state is AuthSuccess) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            state.response?.emailVerificationRequired == true
                            ? OtpVerificationScreen(
                                email: state.response!.user.email,
                              )
                            : Root(),
                      ),
                    );
                  } else if (state is AuthFailure) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
                  }
                },
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(AppSizes.ph8),
                    child: Form(
                      key: cubit.formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hey,\nWelcome Back!',
                            style: AppStyles.primaryHeadLinesStyle,
                          ),
                          SizedBox(height: AppSizes.h24),
                          CustomTextField(
                            controller: cubit.emailController,
                            validator: cubit.validateEmail,
                            title: 'Email',
                            prefixIcon: SvgPicture.asset(
                              'assets/images/auth/sms.svg',
                              width: AppSizes.h24,
                              height: AppSizes.h24,
                            ),
                            hintText: 'Enter your email',
                          ),
                          SizedBox(height: AppSizes.h32),
                          CustomTextField(
                            controller: cubit.passwordController,
                            validator: cubit.validatePassword,
                            title: 'Password',
                            prefixIcon: SvgPicture.asset(
                              'assets/images/auth/lock.svg',
                              width: AppSizes.h24,
                              height: AppSizes.h24,
                            ),
                            hintText: 'Enter your password',
                            obscureText: true,
                            passwordVisibilityToggle: true,
                          ),
                          SizedBox(height: AppSizes.h8),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: DarkColors.primaryColor,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: AppSizes.h24),
                          BlocBuilder<AuthCubit, AuthState>(
                            builder: (context, state) {
                              final isLoading = state is AuthLoading;

                              return CustomButton(
                                title: isLoading ? 'Logging in...' : 'Login',
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        if (cubit.formKey.currentState!
                                            .validate()) {
                                          cubit.login(
                                            cubit.emailController.text.trim(),
                                            cubit.passwordController.text,
                                          );
                                        }
                                      },
                              );
                            },
                          ),
                          SizedBox(height: AppSizes.h32),
                          CustomOrLoginWidget(),
                          SizedBox(height: AppSizes.h20),
                          Row(
                            children: [
                              BlocBuilder<AuthCubit, AuthState>(
                                builder: (context, state) => SocialLoginButton(
                                  title: 'Google',
                                  iconPath: 'assets/images/auth/google.svg',
                                  onPressed: state is AuthLoading
                                      ? null
                                      : cubit.loginWithGoogle,
                                ),
                              ),
                              SizedBox(width: AppSizes.w16),
                              SocialLoginButton(
                                title: 'Apple',
                                iconPath: 'assets/images/auth/apple.svg',
                                onPressed: () {},
                              ),
                            ],
                          ),
                          SizedBox(height: AppSizes.h95),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account?",
                                style: AppStyles.grey16MediumStyle,
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SignUpScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Sign Up',
                                  style: AppStyles.orange16MediumStyle,
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
        },
      ),
    );
  }
}
