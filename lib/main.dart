import 'package:travibe/features/chats/widgets/chat_reverb_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/routing/router_generator.dart';
import 'package:travibe/core/theme/dark_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:go_router/go_router.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:app_links/app_links.dart';
import 'package:travibe/core/deeplinks/deep_links.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //await GoogleAuthService().initialize();

  await PreferencesManager().init();

  // Subscribe early so a cold-start `travibe://posts/{id}` link is caught.
  runApp(
    MyApp(deepLinks: DeepLinkCoordinator(links: AppLinks().uriLinkStream)),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.currentUser,
    this.router,
    this.pushNotifications,
    this.deepLinks,
  });
  final CurrentUserCubit? currentUser;
  final GoRouter? router;
  final PushNotificationService? pushNotifications;

  /// `travibe://posts/{id}` links; tests omit it to stay off the platform.
  final DeepLinkCoordinator? deepLinks;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final app = ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, _) => ValueListenableBuilder<String>(
        valueListenable: PreferencesManager().language,
        builder: (context, language, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Travibe',
          theme: darkTheme,
          routerConfig: router ?? RouterGenerator.router,
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
    final hosted = PushNotificationsHost(
      service: pushNotifications,
      child: ChatReverbHost(
        child: DeepLinksHost(coordinator: deepLinks, child: app),
      ),
    );
    return currentUser == null
        ? BlocProvider(create: (_) => CurrentUserCubit()..load(), child: hosted)
        : BlocProvider.value(value: currentUser!, child: hosted);
  }
}
