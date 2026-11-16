import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pin_code_fields/flutter_pin_code_fields.dart';

class VerifyOtpScreen extends StatelessWidget {
  const VerifyOtpScreen({super.key});

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
          child: Column(
            children: [
              SizedBox(height: AppSizes.adaptiveHeight(32)),
              Center(
                child: Text(
                  'Verify your email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.adaptiveFont(24),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(4)),
              Text(
                'Please enter the 4-digit code we sent to your email',
                style: TextStyle(
                  color: Color(0xFFBDBCBB),
                  fontSize: AppSizes.adaptiveFont(14),
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(height: AppSizes.adaptiveHeight(4)),
              Text(
                '****784@domain.com',
                style: TextStyle(
                  color: Color(0xFFBDBCBB),
                  fontSize: AppSizes.adaptiveFont(14),
                  fontWeight: FontWeight.w400,
                ),
              ),
              PinCodeFields(
                length: 4,
                fieldBorderStyle: FieldBorderStyle.square,
                responsive: false,
                fieldHeight:
                    MediaQuery.textScalerOf(context)
                        .scale(AppSizes.adaptiveFont(30))
                        .clamp(AppSizes.adaptiveRadius(60), double.infinity) *
                    1.2,
                fieldWidth: AppSizes.adaptiveRadius(60),
                borderWidth: 5.0,
                activeBorderColor: Colors.blue,
                activeBackgroundColor: Colors.white,
                borderRadius: BorderRadius.circular(
                  AppSizes.adaptiveRadius(20.0),
                ),
                keyboardType: TextInputType.number,
                //inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autoHideKeyboard: false,
                fieldBackgroundColor: Colors.black12,
                borderColor: Colors.black12,
                textStyle: TextStyle(
                  fontSize: AppSizes.adaptiveFont(30),
                  fontWeight: FontWeight.bold,
                ),
                onComplete: (output) {
                  // setState(() {
                  //   _code = output;
                  // });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
