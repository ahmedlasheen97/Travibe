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
            size: 44,
            iconSize: 24,
          ),
        ),

        body: Column(
          children: [
            SizedBox(height: 32),
            Center(
              child: const Text(
                'Verify your email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Please enter the 4-digit code we sent to your email',
              style: TextStyle(
                color: Color(0xFFBDBCBB),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '****784@domain.com',
              style: TextStyle(
                color: Color(0xFFBDBCBB),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            PinCodeFields(
              length: 4,
              fieldBorderStyle: FieldBorderStyle.square,
              responsive: false,
              fieldHeight: 130.0,
              fieldWidth: 130.0,
              borderWidth: 5.0,
              activeBorderColor: Colors.blue,
              activeBackgroundColor: Colors.white,
              borderRadius: BorderRadius.circular(20.0),
              keyboardType: TextInputType.number,
              //inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autoHideKeyboard: false,
              fieldBackgroundColor: Colors.black12,
              borderColor: Colors.black12,
              textStyle: TextStyle(fontSize: 30.0, fontWeight: FontWeight.bold),
              onComplete: (output) {
                // setState(() {
                //   _code = output;
                // });
              },
            ),
          ],
        ),
      ),
    );
  }
}
