import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import '../data/chat_reverb_service.dart';
import '../cubit/chat_unread_cubit.dart';

class ChatReverbHost extends StatefulWidget {
  const ChatReverbHost({
    super.key,
    required this.child,
    this.service,
    this.unread,
  });
  final Widget child;
  final ChatReverbService? service;
  final ChatUnreadCubit? unread;
  @override
  State<ChatReverbHost> createState() => _ChatReverbHostState();
}

class _ChatReverbHostState extends State<ChatReverbHost>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? ChatReverbService();
  late final _unread = widget.unread ?? ChatUnreadCubit();
  late final _user = context.read<CurrentUserCubit>();
  StreamSubscription<CurrentUserState>? _account;
  StreamSubscription<ChatReverbSignal>? _events;
  Timer? _notifications, _unreadHint;
  StreamSubscription<dynamic>? _pushHints;
  Object? _pushService;
  final Set<String> _reopenedNotifications = {};
  int? _notificationSession;
  @override
  void initState() {
    super.initState();
    _account = _user.stream.listen(_changed);
    _changed(_user.state);
    _events = _service.signals.listen((signal) {
      if (signal.session != PreferencesManager().sessionRevision) return;
      if (signal.name == 'reconcile' ||
          signal.name == 'message.sent' ||
          signal.name == 'messages.read' ||
          signal.name.startsWith('notification')) {
        _refreshUnread();
      }
      if (signal.name == 'reconcile' ||
          signal.name.startsWith('notification')) {
        if (_notificationSession != signal.session) {
          _reopenedNotifications.clear();
          _notificationSession = signal.session;
        }
        if (signal.notificationId != null) {
          _reopenedNotifications.add(signal.notificationId!);
        }
        _notifications?.cancel();
        _notifications = Timer(const Duration(milliseconds: 120), () {
          if (!mounted ||
              signal.session != PreferencesManager().sessionRevision) {
            return;
          }
          PushNotificationsScope.maybeOf(
            context,
          )?.notifications.invalidateFromRealtime(
            reopenedIds: Set.of(_reopenedNotifications),
          );
          _reopenedNotifications.clear();
        });
      }
    });
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _service.foreground(foreground);
    _unread.foreground(foreground);
  }

  void _refreshUnread() {
    final session = PreferencesManager().sessionRevision;
    _unreadHint?.cancel();
    _unreadHint = Timer(const Duration(milliseconds: 120), () {
      if (mounted && session == PreferencesManager().sessionRevision) {
        unawaited(_unread.refresh());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = PushNotificationsScope.maybeOf(context)?.service;
    if (identical(service, _pushService)) return;
    _pushService = service;
    unawaited(_pushHints?.cancel() ?? Future.value());
    _pushHints = service?.activities.listen((event) {
      if (event.sessionRevision == PreferencesManager().sessionRevision) {
        _refreshUnread();
      }
    });
  }

  void _changed(CurrentUserState state) {
    if (!identical(state, _user.state)) return;
    final account = state.profile?.emailVerifiedAt?.isNotEmpty == true
        ? state.profile?.id
        : null;
    _service.account(account);
    _unread.account(account);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service.foreground(state == AppLifecycleState.resumed);
    _unread.foreground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications?.cancel();
    _unreadHint?.cancel();
    unawaited(_pushHints?.cancel() ?? Future.value());
    if (widget.unread == null) unawaited(_unread.close());
    unawaited(_account?.cancel() ?? Future.value());
    unawaited(_events?.cancel() ?? Future.value());
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChatReverbScope(service: _service, unread: _unread, child: widget.child);
}

class ChatReverbScope extends InheritedWidget {
  const ChatReverbScope({
    super.key,
    required this.service,
    this.unread,
    required super.child,
  });
  final ChatReverbService service;
  final ChatUnreadCubit? unread;
  static ChatUnreadCubit? unreadOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatReverbScope>()?.unread;
  static ChatReverbService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatReverbScope>()?.service;
  @override
  bool updateShouldNotify(ChatReverbScope oldWidget) =>
      !identical(oldWidget.service, service) ||
      !identical(oldWidget.unread, unread);
}
