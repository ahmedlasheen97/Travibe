import 'dart:async';
import 'package:travibe/features/follow_requests/cubit/incoming_requests_cubit.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/notifications/screens/notifications_screen.dart';
import 'package:travibe/features/notifications/screens/notification_navigation.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';

import 'firebase_messaging_client.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'push_message.dart';
import 'package:travibe/features/notifications/cubit/notification_activity.dart';
import 'package:travibe/features/notifications/data/laravel_push_token_repository.dart';
import 'push_notification_service.dart';

class PushNotificationsHost extends StatefulWidget {
  const PushNotificationsHost({super.key, required this.child, this.service});
  final Widget child;
  final PushNotificationService? service;
  @override
  State<PushNotificationsHost> createState() => _PushNotificationsHostState();
}

class _PushNotificationsHostState extends State<PushNotificationsHost>
    with WidgetsBindingObserver {
  late final PushNotificationService _service;
  late final PushNotificationsCoordinator _coordinator;
  StreamSubscription<CurrentUserState>? _user;
  late final CurrentUserCubit _currentUser;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        PushNotificationService(
          client: FirebaseMessagingClient(),
          repository: LaravelPushTokenRepository(),
        );
    _coordinator = PushNotificationsCoordinator(_service);
    final user = _currentUser = context.read<CurrentUserCubit>();
    _user = user.stream.listen(_accountChanged);
    _accountChanged(user.state);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_service.start());
  }

  void _accountChanged(CurrentUserState state) {
    // Bloc streams deliver asynchronously. A queued old profile must not be
    // stamped with a replacement session's credentials after rapid logout/login.
    if (!identical(state, _currentUser.state)) return;
    unawaited(
      _service.updateAccount(
        state.profile?.emailVerifiedAt?.isNotEmpty == true
            ? state.profile?.id
            : null,
        expectedSession: PreferencesManager().sessionRevision,
        deliveryEnabled: state.profile?.pushNotificationsEnabled != false,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.resume());
      _coordinator.refreshCount();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_user?.cancel() ?? Future<void>.value());
    _coordinator.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PushNotificationsScope(coordinator: _coordinator, child: widget.child);
}

/// Root attaches only after the existing auth/onboarding/splash flow reaches it.
/// The push service cannot replace that flow or navigate directly to Home.
class PushNotificationsCoordinator {
  PushNotificationsCoordinator(this.service, {this.repository})
    : notifications = NotificationActivity(repo: repository) {
    _hints = service.activities.listen((_) {
      refreshCount(invalidate: true);
    });
  }
  final NotificationActivity notifications;
  StreamSubscription<PushActivity>? _hints;
  Animation<double>? _routeAnimation;
  void _returned(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) refreshCount();
  }

  void refreshCount({bool invalidate = false}) {
    if (_owner != null) {
      unawaited(notifications.refresh(invalidate: invalidate));
    }
  }

  void dispose() {
    detachAll();
    unawaited(_hints?.cancel() ?? Future<void>.value());
    notifications.dispose();
  }

  final PushNotificationService service;
  final NotificationsRepo? repository;
  Object? _owner;
  void Function()? _open;
  StreamSubscription<PushActivity>? _activity;

  void attach(
    Object owner,
    BuildContext context, {
    FollowCubit? follow,
    IncomingRequestsCubit? incoming,
  }) {
    if (identical(_owner, owner)) return;
    detachAll();
    _owner = owner;
    _routeAnimation = ModalRoute.of(context)?.secondaryAnimation;
    _routeAnimation?.addStatusListener(_returned);
    refreshCount();
    var showing = false;
    void open() {
      if (!context.mounted || showing || !PreferencesManager().hasSession) {
        return;
      }
      showing = true;
      final session = PreferencesManager().sessionRevision;
      Navigator.of(context, rootNavigator: true)
          .push(
            MaterialPageRoute<void>(
              builder: (_) {
                final screen = NotificationsScreen(
                  push: service,
                  repo: repository,
                  activity: notifications,
                );
                final scoped = notificationRouteScope(context, screen);
                if (follow == null && incoming == null) return scoped;
                return MultiBlocProvider(
                  providers: [
                    if (follow != null)
                      BlocProvider<FollowCubit>.value(value: follow),
                    if (incoming != null)
                      BlocProvider<IncomingRequestsCubit>.value(
                        value: incoming,
                      ),
                  ],
                  child: scoped,
                );
              },
            ),
          )
          .whenComplete(() {
            showing = false;
            refreshCount();
            if (context.mounted &&
                session == PreferencesManager().sessionRevision) {
              ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
            }
          });
    }

    _open = open;
    service.setNavigationHandler(open);
    _activity = service.activities.listen((event) {
      if (event.kind != PushActivityKind.foreground ||
          !context.mounted ||
          showing ||
          event.sessionRevision != PreferencesManager().sessionRevision ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('New notification'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              if (event.sessionRevision ==
                  PreferencesManager().sessionRevision) {
                open();
              }
            },
          ),
        ),
      );
    });
  }

  void openInbox() => _open?.call();
  void detach(Object owner) {
    if (identical(_owner, owner)) detachAll();
  }

  void detachAll() {
    _routeAnimation?.removeStatusListener(_returned);
    _routeAnimation = null;
    _owner = null;
    _open = null;
    service.setNavigationHandler(null);
    unawaited(_activity?.cancel() ?? Future<void>.value());
    _activity = null;
  }
}

class PushNotificationsScope extends InheritedWidget {
  const PushNotificationsScope({
    super.key,
    required this.coordinator,
    required super.child,
  });
  final PushNotificationsCoordinator coordinator;
  static PushNotificationsCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PushNotificationsScope>()
      ?.coordinator;
  static void openInbox(BuildContext context) {
    final coordinator = maybeOf(context);
    if (coordinator != null) {
      coordinator.openInbox();
      return;
    }
    // Existing Home widget harnesses may not include the app-level push host.
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  @override
  bool updateShouldNotify(PushNotificationsScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}
