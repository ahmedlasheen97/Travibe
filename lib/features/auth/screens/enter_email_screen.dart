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
            size: 44,
            iconSize: 24,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              SizedBox(height: 32),
              Text(
                'Forgot your password?',
                style: TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                "No worries! Enter your email address and we'll send you a verification code to reset your password.",
                style: TextStyle(color: Color(0xFFBDBCBB), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28),
              CustomTextField(
                title: 'Email',
                prefixIcon: SvgPicture.asset(
                  'assets/images/auth/sms.svg',
                  width: 24,
                  height: 24,
                ),
                hintText: 'Enter your email',
              ),
              SizedBox(height: 30),
              CustomButton(title: 'Send Code', onPressed: () {}),
              SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Remember your password?',
                    style: TextStyle(color: Colors.white, fontSize: 16),
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
    );
  }
}
