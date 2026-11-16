import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/auth/screens/login_screen.dart';

class CreateNewPassScreen extends StatelessWidget {
  const CreateNewPassScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          leading: BackButtonWidget(
            onTap: () {
              Navigator.pop(context);
            },
            size: AppSizes.adaptiveRadius(44),
            iconSize: AppSizes.adaptiveRadius(24),
          ),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(AppSizes.adaptiveRadius(8.0)),
            child: Column(
              children: [
                SizedBox(height: AppSizes.adaptiveHeight(32)),
                Text(
                  'Forgot your password?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.adaptiveFont(18),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSizes.adaptiveHeight(8)),
                Text(
                  "No worries! Enter your email address and we'll send you a verification code to reset your password.",
                  style: TextStyle(
                    color: Color(0xFFBDBCBB),
                    fontSize: AppSizes.adaptiveFont(16),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSizes.adaptiveHeight(28)),
                CustomTextField(
                  title: 'Email',
                  prefixIcon: SvgPicture.asset(
                    'assets/images/auth/sms.svg',
                    width: AppSizes.adaptiveRadius(24),
                    height: AppSizes.adaptiveRadius(24),
                  ),
                  hintText: 'Enter your email',
                ),
                SizedBox(height: AppSizes.adaptiveHeight(30)),
                CustomButton(title: 'Send Code', onPressed: () {}),
                SizedBox(height: AppSizes.adaptiveHeight(30)),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Remember your password?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppSizes.adaptiveFont(16),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Log In',
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
    );
  }
}
