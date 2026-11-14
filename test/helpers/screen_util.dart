import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Wraps [app] in the app's ScreenUtil design frame (390×844) so widgets
/// sized through `AppSizes` can build in tests.
Widget withScreenUtil(Widget app) => ScreenUtilInit(
  designSize: const Size(390, 844),
  minTextAdapt: true,
  splitScreenMode: true,
  builder: (_, _) => app,
);
