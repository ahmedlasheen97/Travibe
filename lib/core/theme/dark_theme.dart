import 'package:flutter/material.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/bottom_nav_style.dart';

import 'package:travibe/core/theme/dark_colors.dart';

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Plus Jakarta Sans',
  colorScheme: ColorScheme.dark(
    primaryContainer: Color(0xFF0A0A0A),
    secondary: Color(0XFFC6C6C6),
  ),
  scaffoldBackgroundColor: Color(0xFF0A0A0A),
  primaryColor: DarkColors.primaryColor,
  appBarTheme: AppBarTheme(
    backgroundColor: Color(0xFF0A0A0A),
    centerTitle: true,
    foregroundColor: Colors.white,
    //titleTextStyle: TextStyle(fontSize: AppSizes.sp16, fontWeight: FontWeight.w700, color: Color(0xFF141414)),
  ),
  progressIndicatorTheme: ProgressIndicatorThemeData(color: Colors.white),
  // appBarTheme: AppBarTheme(
  //   backgroundColor: Color(0xFFF6F7F9),
  //   titleTextStyle: TextStyle(
  //     color: Color(0xFF161F1B),
  //     fontSize: 20,
  //   ),
  //   centerTitle: true,
  //   iconTheme: IconThemeData(
  //     color: Color(0xFF161F1B),
  //   ),
  // ),
  // switchTheme: SwitchThemeData(
  //   trackColor: WidgetStateProperty.resolveWith((states) {
  //     if (states.contains(WidgetState.selected)) {
  //       return Color(0xFF15B86C);
  //     }
  //     return Colors.white;
  //   }),
  //   thumbColor: WidgetStateProperty.resolveWith((states) {
  //     if (states.contains(WidgetState.selected)) {
  //       return Colors.white;
  //     }
  //     return Color(0xFF9E9E9E);
  //   }),
  //   trackOutlineColor: WidgetStateProperty.resolveWith((states) {
  //     if (states.contains(WidgetState.selected)) {
  //       return Colors.transparent;
  //     }
  //     return Color(0xFF9E9E9E);
  //   }),
  //   trackOutlineWidth: WidgetStateProperty.resolveWith((states) {
  //     if (states.contains(WidgetState.selected)) {
  //       return 0;
  //     }
  //     return 2;
  //   }),
  // ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: DarkColors.primaryColor,
      foregroundColor: Color(0xFFFFFCFC),
      textStyle: TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: ActionButtonStyle.fontSize,
        fontWeight: FontWeight.w400,
      ),
      shape: ActionButtonStyle.shape,
      minimumSize: Size.fromHeight(48),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: DarkColors.primaryColor),
  ),
  // floatingActionButtonTheme: FloatingActionButtonThemeData(
  //   backgroundColor: Color(0xFF15B86C),
  //   foregroundColor: Color(0xFFFFFCFC),
  //   extendedTextStyle: TextStyle(
  //     fontSize: 14,
  //     fontWeight: FontWeight.w500,
  //   ),
  // ),
  textTheme: TextTheme(
    displaySmall: TextStyle(
      fontSize: 24,
      color: Color(0xFF161F1B),
      fontWeight: FontWeight.w400,
    ),
    displayMedium: TextStyle(
      fontSize: 28,
      color: Color(0xFF161F1B),
      fontWeight: FontWeight.w400,
    ),
    displayLarge: TextStyle(
      fontSize: 32,
      color: Color(0xFF161F1B),
      fontWeight: FontWeight.w400,
    ),
    titleSmall: TextStyle(
      color: Color(0xFF3A4640),
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    titleMedium: TextStyle(
      color: Color(0xFF161F1B),
      fontSize: 16,
      fontWeight: FontWeight.w400,
    ),
    titleLarge: TextStyle(
      color: Colors.white,
      fontSize: 16,
      // AppBar merges this into local title styles, including Login/Sign Up.
      decoration: TextDecoration.none,
      overflow: TextOverflow.ellipsis,
      fontWeight: FontWeight.w400,
    ),
    labelSmall: TextStyle(
      fontWeight: FontWeight.w400,
      color: Color(0xFF161F1B),
      fontSize: 20,
    ),
    labelMedium: TextStyle(color: Colors.black, fontSize: 16),
    labelLarge: TextStyle(color: Colors.black, fontSize: 24),
  ),
  inputDecorationTheme: InputDecorationTheme(
    hintStyle: TextStyle(color: Color(0xFF9E9E9E)),
    filled: true,
    fillColor: Color(0xFFFFFFFF),
    focusColor: Color(0xFFD1DAD6),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(35),
      borderSide: BorderSide(color: Colors.red, width: 0.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(35),
      borderSide: BorderSide(color: Color(0xFF595966), width: 0.5),
    ),
    errorStyle: TextStyle(color: Color(0xFF22C55E)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(35),
      borderSide: BorderSide(color: Color(0xFF595966), width: 0.5),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(35),
      borderSide: BorderSide(color: Color(0xFF595966), width: 0.5),
    ),
  ),
  // checkboxTheme: CheckboxThemeData(
  //   side: BorderSide(
  //     color: Color(0xFFD1DAD6),
  //     width: 2,
  //   ),
  //   shape: RoundedRectangleBorder(
  //     borderRadius: BorderRadius.circular(4),
  //   ),
  // ),
  // iconTheme: IconThemeData(
  //   color: Color(0xFF161F1B),
  // ),
  // listTileTheme: ListTileThemeData(
  //   titleTextStyle: TextStyle(
  //     color: Color(0xFF161F1B),
  //     fontSize: 16,
  //     fontWeight: FontWeight.w400,
  //   ),
  // ),
  // dividerTheme: DividerThemeData(color: Color(0xFFD1DAD6)),
  // textSelectionTheme: TextSelectionThemeData(
  //   cursorColor: Colors.black,
  //   selectionColor: Colors.white,
  //   selectionHandleColor: Colors.black,
  // ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: Colors.transparent, // container handles bg now
    type: BottomNavigationBarType.fixed,
    selectedItemColor: DarkColors.whiteColor,
    unselectedItemColor: DarkColors.greyColor,
    showUnselectedLabels: true,
  ),

  extensions: [
    BottomNavStyle(
      backgroundColor: Color(0x801F1F1F),
      borderColor: Color(0xff3B3B3B), // your requested border color
      borderWidth: 1,
      radius: AppSizes.r50, // your requested radius
      height: AppSizes.h95, // your requested height
    ),
  ],
);
