import 'notification_navigation.dart';
import '../data/notification_targets.dart';
import '../data/notification_diagnostics.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/cubit/cursor_list_cubit.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/firebase_messaging_client.dart';
import 'package:travibe/core/notifications/push_notification_service.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/notifications/cubit/notifications_cubit.dart';
import 'package:travibe/features/notifications/cubit/notification_activity.dart';
import 'package:travibe/features/notifications/data/notification_model.dart';
import 'package:travibe/features/notifications/data/notification_presentation.dart';
import 'package:travibe/features/notifications/widgets/notification_row.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/follow/widgets/follow_pill.dart';
import 'package:travibe/features/notifications/data/notifications_repo.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

/// Laravel inbox. Read actions never navigate to unverified payload destinations.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.repo,
    this.push,
    this.activity,
    this.presentation = const NotificationPresentationResolver(),
    this.targets,
    this.openDestination,
  });
  final NotificationsRepo? repo;
  final PushNotificationService? push;
  final NotificationActivity? activity;
  final NotificationPresentationResolver presentation;
  final NotificationTargetsRepository? targets;
  final NotificationDestinationOpener? openDestination;
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  late final NotificationActivity _notifications;
  late final _list = NotificationsCubit(
    repo: widget.repo,
    activity: _notifications,
  );
  final _session = PreferencesManager();
  late FollowCubit _follow;
  bool _ownsFollow = false;
  StreamSubscription<dynamic>? _activity;
  StreamSubscription<dynamic>? _loaded, _invalidated;
  late final _targets = widget.targets ?? NotificationTargetsRepository();
  final _diagnostics = NotificationDiagnostics();
  final Set<String> _autoAttempted = {};
  bool _autoReading = false, _entryAttempted = false, _opening = false;
  late int _revision;
  Animation<double>? _covered;
  void _returned(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted && _session.hasSession) {
      _autoAttempted.clear();
      _entryAttempted = false;
      unawaited(_list.refresh());
      _queueAutoRead();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(animation, _covered)) {
      _covered?.removeStatusListener(_returned);
      _covered = animation;
      _covered?.addStatusListener(_returned);
    }
  }

  void _queueAutoRead() => scheduleMicrotask(_autoRead);
  void _autoRead() {
    if (!mounted ||
        !_session.hasSession ||
        _autoReading ||
        _notifications.markingAll ||
        ModalRoute.of(context)?.isCurrent == false ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    final state = _list.state;
    if (state.status != CursorListStatus.loaded ||
        state.refreshing ||
        state.loadingMore ||
        state.error != null) {
      return;
    }
    final unread = state.items
        .where((item) => item['read_at'] == null)
        .map((item) => item['id'].toString())
        .toSet();
    if (unread.difference(_autoAttempted).isEmpty &&
        (_entryAttempted || _notifications.count == 0)) {
      return;
    }
    _autoAttempted.addAll(unread);
    _entryAttempted = true;
    _autoReading = true;
    final revision = _session.sessionRevision;
    unawaited(
      _markAll().whenComplete(() {
        if (mounted && revision == _session.sessionRevision) {
          _autoReading = false;
          _queueAutoRead();
        }
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _revision = _session.sessionRevision;
    final shared = context.read<FollowCubit?>();
    _ownsFollow = shared == null;
    _follow = shared ?? FollowCubit();
    _notifications = widget.activity ?? NotificationActivity(repo: widget.repo);
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_sessionChanged);
    _loaded = _list.stream.listen((_) => _queueAutoRead());
    _invalidated = _notifications.invalidations.listen((revision) {
      if (revision != _session.sessionRevision) return;
      _autoAttempted.clear();
      _entryAttempted = false;
    });
    _notifications.addListener(_queueAutoRead);
    if (_session.hasSession) {
      unawaited(_list.load());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_notifications.refresh());
      });
    }
    _activity = widget.push?.activities.listen((event) {
      if (_session.hasSession &&
          event.sessionRevision == _session.sessionRevision) {
        unawaited(_list.refresh());
        if (widget.activity == null) {
          unawaited(_notifications.refresh(invalidate: true));
        }
      }
    });
  }

  void _sessionChanged() {
    if (_revision == _session.sessionRevision) return;
    _revision = _session.sessionRevision;
    _autoAttempted.clear();
    _entryAttempted = false;
    _autoReading = false;
    _opening = false;
    if (_ownsFollow) {
      unawaited(_follow.close());
      _follow = FollowCubit();
    }
    if (mounted) setState(() {});
    // CursorListCubit clears previous data synchronously for the new session.
    // Wait until every session listener has invalidated its old request first.
    scheduleMicrotask(() {
      if (mounted && _session.hasSession) unawaited(_list.load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _session.hasSession) {
      _autoAttempted.clear();
      _entryAttempted = false;
      unawaited(_list.refresh());
      unawaited(_notifications.refresh(invalidate: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_sessionChanged);
    _covered?.removeStatusListener(_returned);
    _notifications.removeListener(_queueAutoRead);
    unawaited(_loaded?.cancel() ?? Future.value());
    unawaited(_invalidated?.cancel() ?? Future.value());
    if (widget.targets == null) _targets.dispose();
    unawaited(_activity?.cancel() ?? Future<void>.value());
    unawaited(_list.close());
    if (widget.activity == null) _notifications.dispose();
    if (_ownsFollow) unawaited(_follow.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<FollowCubit>.value(
    value: _follow,
    child: ListenableBuilder(
      listenable: _notifications,
      builder: (context, _) => Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0B),
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          centerTitle: true,
          toolbarHeight: AppSizes.adaptiveHeight(80),
          leadingWidth: 80,
          leading: const Padding(
            padding: EdgeInsetsDirectional.only(start: 20, end: 16),
            child: BackButtonWidget(),
          ),
          title: const Text(
            'Notifications',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Notification options',
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              onSelected: (value) {
                if (value == 'read') {
                  unawaited(_markAll());
                } else {
                  _showPermissionSettings();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'read',
                  enabled: _session.hasSession && !_notifications.markingAll,
                  child: const Text('Mark all as read'),
                ),
                if (widget.push != null)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Notification settings'),
                  ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: DarkColors.primaryColor,
            onRefresh: () async {
              // Laravel stays usable even when optional APNs/FCM is unavailable.
              if (widget.push != null) unawaited(widget.push!.retry());
              if (_session.hasSession) {
                _autoAttempted.clear();
                _entryAttempted = false;
                _targets.invalidate();
                await Future.wait([
                  _list.refresh(),
                  _notifications.refresh(invalidate: true),
                ]);
              }
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (_session.hasSession &&
                    event.depth == 0 &&
                    event.metrics.axis == Axis.vertical &&
                    event.metrics.extentAfter < 240) {
                  unawaited(_list.more());
                }
                return false;
              },
              child:
                  BlocBuilder<
                    NotificationsCubit,
                    CursorListState<Map<String, dynamic>>
                  >(
                    bloc: _list,
                    builder: (context, state) => CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (!_session.hasSession)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Sign in to view your notifications.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          )
                        else ...[
                          if (state.status == CursorListStatus.initial ||
                              state.status == CursorListStatus.loading)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          if (state.error != null)
                            SliverToBoxAdapter(
                              child: ErrorRetryView(
                                message: state.error!.message,
                                onRetry: _list.load,
                              ),
                            ),
                          if (state.status == CursorListStatus.loaded &&
                              state.items.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No notifications yet.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          SliverList.builder(
                            itemCount: state.items.length,
                            itemBuilder: (context, index) {
                              final item = InboxNotification.fromJson(
                                state.items[index],
                              );
                              final followState = context.watch<FollowCubit>();
                              final actor = item.actor;
                              // Viewer id is optional: when known, never offer
                              // to follow yourself.
                              final viewer = context
                                  .watch<CurrentUserCubit?>()
                                  ?.state
                                  .profile
                                  ?.id;
                              // Follow is never self-sent; hide when already
                              // following. Tapping flips the pill to Following.
                              final canFollow =
                                  widget.presentation.kind(item) ==
                                      NotificationKind.follow &&
                                  actor?.id != null &&
                                  actor?.isBlocked != true &&
                                  actor?.isFollowing == false &&
                                  actor!.id != viewer &&
                                  followState.canInteract(actor.id!);
                              _diagnostics.inspect(item);
                              return NotificationRow(
                                key: ValueKey(
                                  '${_session.sessionRevision}:${item.id}',
                                ),
                                item: item,
                                resolver: widget.presentation,
                                onRead: () => _openNotification(item),
                                onAvatarTap: () =>
                                    _openNotification(item, profile: true),
                                followAction: canFollow
                                    ? FollowActionBuilder(
                                        userId: actor.id!,
                                        initialFollowing: actor.isFollowing!,
                                        builder:
                                            (
                                              context,
                                              following,
                                              pending,
                                              onToggle,
                                            ) => FollowPill(
                                              following: following,
                                              pending: pending,
                                              onPressed: onToggle,
                                            ),
                                      )
                                    : null,
                              );
                            },
                          ),
                          if (state.loadingMore)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          if (state.paginationError != null)
                            SliverToBoxAdapter(
                              child: ErrorRetryView(
                                message: state.paginationError!.message,
                                onRetry: () => _list.more(retry: true),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    ),
  );

  void _showPermissionSettings() {
    final push = widget.push;
    if (push == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0B0B),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: NotificationPermissionCard(push: push),
        ),
      ),
    );
  }

  Future<void> _openNotification(
    InboxNotification item, {
    bool profile = false,
  }) async {
    if (_opening || !_session.hasSession) return;
    _opening = true;
    final revision = _session.sessionRevision;
    bool current() =>
        mounted && revision == _session.sessionRevision && _session.hasSession;
    try {
      if (!item.isRead) {
        final ok = await _notifications.markRead(item.id);
        if (!mounted || !current()) return;
        if (!ok) _showReadError();
      }
      final actorId = NotificationTarget.positive(item.actor?.id);
      final target = profile
          ? (actorId == null || item.actor?.isBlocked == true
                ? null
                : NotificationTarget(NotificationTargetKind.profile, actorId))
          : NotificationTarget.from(item);
      if (target == null && !profile && item.isRequest) {
        // Missing conversation_id: fall back to the Requests tab.
        if (!mounted || !current()) return;
        await (widget.openDestination ?? openNotificationDestination)(
          context,
          item,
          const NotificationContent(
            NotificationTarget(NotificationTargetKind.conversation, 0),
          ),
        );
        return;
      }
      if (target == null) {
        if (mounted && current()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This notification has no available destination.'),
            ),
          );
        }
        return;
      }
      NotificationContent content;
      try {
        content = await _targets.resolve(target, fresh: true);
      } catch (_) {
        // A request that cannot be fetched still lands on the Requests tab.
        if (target.kind != NotificationTargetKind.conversation ||
            !item.isRequest) {
          rethrow;
        }
        content = NotificationContent(target);
      }
      if (!mounted || !current()) return;
      await (widget.openDestination ?? openNotificationDestination)(
        context,
        item,
        content,
      );
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This content is unavailable, expired, or cannot be accessed.',
            ),
          ),
        );
      }
    } finally {
      if (current()) _opening = false;
    }
  }

  Future<void> _markAll() async {
    final revision = _session.sessionRevision;
    _autoAttempted.addAll(
      _list.state.items
          .where((n) => n['read_at'] == null)
          .map((n) => n['id'].toString()),
    );
    _entryAttempted = true;
    final ok = await _notifications.markAllRead(
      ids: _list.state.items
          .where((n) => n['read_at'] == null)
          .map((n) => n['id'].toString()),
    );
    if (!mounted || revision != _session.sessionRevision) return;
    if (!ok) _showReadError();
  }

  void _showReadError() => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      action: SnackBarAction(
        label: 'Retry',
        onPressed: () => unawaited(_markAll()),
      ),
      content: Text(
        _notifications.error?.message ??
            'Unable to mark notifications as read. Please retry.',
      ),
    ),
  );
}

class NotificationPermissionCard extends StatelessWidget {
  const NotificationPermissionCard({super.key, required this.push});
  final PushNotificationService push;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: push,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Push notifications',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            !push.supported
                ? 'Push notifications are not configured on this device.'
                : switch (push.permission) {
                    PushPermission.unknown =>
                      'Checking notification permission…',
                    PushPermission.notDetermined =>
                      'Choose whether Travibe can send notifications.',
                    PushPermission.denied =>
                      'Notifications are disabled. Enable them in device Settings, then return.',
                    PushPermission.authorized =>
                      'Notification permission is enabled.',
                    PushPermission.provisional =>
                      'Quiet notifications are enabled.',
                  },
            style: const TextStyle(color: Colors.white70),
          ),
          if (push.tokenStatus == PushTokenStatus.waitingForApns)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Waiting for Apple notification registration. You can try again shortly.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          if (push.error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error, style: const TextStyle(color: Colors.white70)),
            ),
          if (push.supported) ...[
            const SizedBox(height: 12),
            CustomButton(
              title: push.requestingPermission
                  ? 'Checking…'
                  : push.permission == PushPermission.notDetermined ||
                        push.permission == PushPermission.unknown
                  ? 'Enable notifications'
                  : 'Check notification status',
              onPressed: push.requestingPermission
                  ? null
                  : () {
                      if (push.permission == PushPermission.notDetermined ||
                          push.permission == PushPermission.unknown) {
                        unawaited(push.requestPermission());
                      } else {
                        unawaited(push.retry());
                      }
                    },
            ),
          ],
        ],
      ),
    ),
  );
}
