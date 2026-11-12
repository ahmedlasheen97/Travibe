import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/screens/settings_screen.dart';
import 'settings_privacy_test.dart' as settings;

void main() {
  final preferences = PreferencesManager();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.saveToken('settings-loading');
  });
  tearDown(() => preferences.clear());

  Future<void> show(WidgetTester tester, CurrentUserCubit user) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme,
          home: SettingsScreen(currentUser: user),
        ),
      ),
    );
    await tester.pump();
  }

  Switch activeStatus(WidgetTester tester) => tester.widget<Switch>(
    find.descendant(
      of: find.ancestor(
        of: find.text('Active Status'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    ),
  );

  testWidgets(
    'cached settings render immediately while GET /profile revalidates',
    (tester) async {
      final api = settings.SettingsApi();
      final user = settings.settingsCubit(api);
      addTearDown(user.close);
      await user.load();
      expect(user.state.profile?.hasSettings, isTrue);

      api.readResult = Completer<dynamic>();
      await show(tester, user);
      // Opening Settings revalidates `GET /profile` in the background.
      expect(api.reads, ['profile', 'profile']);
      expect(user.state.loading, isTrue);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(find.text('Server settings are unavailable.'), findsNothing);
      expect(activeStatus(tester).onChanged, isNotNull);

      (api.readResult as Completer<dynamic>).complete({
        'data': settings.settingsUser(),
      });
      await tester.pumpAndSettle();
      expect(user.state.loading, isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'without cached settings a small Cupertino loader shows, never a line',
    (tester) async {
      final api = settings.SettingsApi()..readResult = Completer<dynamic>();
      final user = settings.settingsCubit(api);
      addTearDown(user.close);
      await show(tester, user);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final loader = find.byType(CupertinoActivityIndicator);
      expect(loader, findsOneWidget);
      expect(tester.getSize(loader).height, lessThanOrEqualTo(24));
      expect(find.bySemanticsLabel('Loading settings'), findsOneWidget);
      // Nothing cached yet: controls show as unavailable, not as editable.
      expect(find.byType(Switch), findsNothing);

      (api.readResult as Completer<dynamic>).complete({
        'data': settings.settingsUser(),
      });
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(activeStatus(tester).onChanged, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
