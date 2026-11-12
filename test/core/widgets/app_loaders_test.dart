import 'package:flutter/cupertino.dart' hide RefreshCallback;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/travibe_loading_indicator.dart';

void main() {
  Widget app(Widget child) => ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) => MaterialApp(
      theme: darkTheme,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Color? materialColor(WidgetTester tester, Type type) {
    final element = tester.element(find.byType(type));
    final widget = element.widget as ProgressIndicator;
    return widget.color ?? ProgressIndicatorTheme.of(element).color;
  }

  testWidgets('theme makes Circular and Linear indicators white', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 100, child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
    expect(
      materialColor(tester, CircularProgressIndicator),
      DarkColors.whiteColor,
    );
    expect(
      materialColor(tester, LinearProgressIndicator),
      DarkColors.whiteColor,
    );
    expect(darkTheme.primaryColor, DarkColors.primaryColor);
  });

  testWidgets('AppActivityIndicator defaults to white in both modes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const AppActivityIndicator(radius: 11, animating: false)),
    );
    var spinner = tester.widget<CupertinoActivityIndicator>(
      find.byType(CupertinoActivityIndicator),
    );
    expect(spinner.color, appLoaderColor);
    expect(appLoaderColor, DarkColors.whiteColor);
    expect(spinner.radius, 11);
    expect(spinner.animating, isFalse);

    await tester.pumpWidget(
      app(const AppActivityIndicator.partiallyRevealed(progress: .4)),
    );
    spinner = tester.widget<CupertinoActivityIndicator>(
      find.byType(CupertinoActivityIndicator),
    );
    expect(spinner.color, DarkColors.whiteColor);
    expect(spinner.progress, .4);
  });

  testWidgets('TravibeLoadingIndicator is white despite the orange theme', (
    tester,
  ) async {
    await tester.pumpWidget(app(const TravibeLoadingIndicator()));
    expect(
      tester
          .widget<CupertinoActivityIndicator>(
            find.byType(CupertinoActivityIndicator),
          )
          .color,
      DarkColors.whiteColor,
    );
  });

  testWidgets('AppRefreshIndicator uses a white spinner', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      app(
        AppRefreshIndicator(
          onRefresh: () async => refreshed++,
          child: ListView(children: const [SizedBox(height: 2000)]),
        ),
      ),
    );
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    expect(refresh.color, DarkColors.whiteColor);
    await refresh.onRefresh();
    expect(refreshed, 1);
  });
}
