import '../data/chat_history_cache.dart';
import '../widgets/chat_reverb_host.dart';
import '../widgets/chat_network_banner.dart';
import '../widgets/chat_empty_illustration.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'chat_navigation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import '../cubit/chat_cubit.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import '../widgets/chat_widgets.dart';
import 'conversation_screen.dart';
import 'new_conversation_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({
    super.key,
    this.repository,
    this.requests = false,
    this.onRequestResolved,
  });
  final ChatRepository? repository;
  final bool requests;
  final void Function(ChatConversation conversation, bool accepted)?
  onRequestResolved;
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with WidgetsBindingObserver {
  late final ChatRepository _repo =
      widget.repository ?? LaravelChatRepository();
  Object get _inboxKey =>
      ('chats', widget.repository ?? LaravelChatRepository, widget.requests);
  Object get _countKey => (_inboxKey, 'request_count');
  late final _list = ChatListCubit<ChatConversation>(
    cacheKey: _inboxKey,
    cacheGroup: 'inbox',
    cacheItemLimit: 200,
    cacheWhen: () => _serverQuery.isEmpty && _search.text.trim().isEmpty,
    fetch: (next) => _repo is ConversationSearchRepository
        ? (_repo as ConversationSearchRepository).searchConversations(
            _serverQuery,
            continuation: next,
            requests: widget.requests,
          )
        : _repo.conversations(continuation: next, requests: widget.requests),
    idOf: (item) => item.id,
    cancel: _repo.cancel,
  );
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String _serverQuery = '';
  StreamSubscription<dynamic>? _realtime;
  void _searchChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    if (_repo is! ConversationSearchRepository) return;
    // Immediately invalidate old requests; only issue the new request after idle.
    _list.invalidateQuery();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || !_valid) return;
      _serverQuery = _search.text.trim();
      unawaited(_list.resetQuery());
    });
  }

  final Set<String> _resolvedRequests = {};
  int _countRevision = 0;
  bool _refreshAgain = false;
  final _preferences = PreferencesManager();
  late final int _session = _preferences.sessionRevision;
  StreamSubscription<dynamic>? _activity;
  int? _requestCount;
  bool _opening = false;
  bool _offline = false;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    _requestCount = ChatHistoryCache.instance.read<int>(
      _countKey,
      group: 'inbox_counts',
    );
    WidgetsBinding.instance.addObserver(this);
    _preferences.addListener(_sessionChanged);
    unawaited(_refresh());
  }

  bool get _valid =>
      _session == _preferences.sessionRevision && _preferences.hasSession;
  void _sessionChanged() {
    _search.clear();
    _requestCount = null;
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _realtime ??= ChatReverbScope.maybeOf(context)?.signals.listen((event) {
      if (mounted &&
          _valid &&
          event.session == _session &&
          ModalRoute.of(context)?.isCurrent != false &&
          (event.name == 'reconcile' ||
              event.name == 'message.sent' ||
              event.name.startsWith('notification'))) {
        unawaited(_refresh());
      }
    });
    _activity ??= PushNotificationsScope.maybeOf(context)?.service.activities
        .listen((event) {
          if (_valid &&
              event.sessionRevision == _session &&
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed) {
            unawaited(_refresh());
          }
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _valid) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!_valid || _searchDebounce?.isActive == true) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final countRevision = _countRevision;
    // Prefer the server total; never count a partial page as all requests.
    try {
      await _list.load();
      if (!widget.requests && _repo.capabilities.requests && _valid) {
        final page = await _repo.conversations(requests: true);
        if (mounted && _valid && countRevision == _countRevision) {
          setState(
            () => _requestCount =
                page.total ??
                (page.continuation == null ? page.items.length : null),
          );
          _cacheCount();
        }
      }
    } catch (_) {
      // The optional count must not replace a successfully loaded inbox.
    } finally {
      _refreshing = false;
      if (_refreshAgain && mounted && _valid) {
        _refreshAgain = false;
        unawaited(_refresh());
      }
    }
  }

  void _cacheCount() {
    if (_requestCount != null && _valid) {
      ChatHistoryCache.instance.write(
        _countKey,
        _requestCount!,
        _session,
        group: 'inbox_counts',
      );
    }
  }

  Future<void> _open(ChatConversation conversation) async {
    if (_opening || !_valid) return;
    _opening = true;
    final screen = chatRouteScope(
      context,
      ConversationScreen(
        conversation: conversation,
        receivedRequest: widget.requests,
        onDeleted: () {
          if (mounted && _valid) {
            _list.removeConfirmed(
              conversation.id,
              session: _session,
              allowRestoration: true,
            );
          }
        },
        onRequestResolved: _requestResolved,
        repository: widget.repository,
      ),
    );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    _opening = false;
    if (mounted && _valid) await _refresh();
  }

  void _requestResolved(ChatConversation conversation, bool accepted) {
    if (!mounted || !_valid) return;
    final first = _resolvedRequests.add(conversation.id);
    if (first) _countRevision++;
    if (widget.requests || !accepted) {
      _list.removeConfirmed(conversation.id, session: _session);
    } else if (_serverQuery.isEmpty ||
        _matches(conversation, _serverQuery.toLowerCase())) {
      _list.appendConfirmed(conversation, session: _session);
    }
    if (first && _requestCount != null) {
      setState(
        () => _requestCount = (_requestCount! - 1).clamp(0, _requestCount!),
      );
    }
    _cacheCount();
    widget.onRequestResolved?.call(conversation, accepted);
    if (first) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preferences.removeListener(_sessionChanged);
    unawaited(_activity?.cancel() ?? Future<void>.value());
    unawaited(_list.close());
    _searchDebounce?.cancel();
    unawaited(_realtime?.cancel() ?? Future.value());
    _search.dispose();
    super.dispose();
  }

  bool _matches(ChatConversation item, String query) =>
      item.participant.name.toLowerCase().contains(query) ||
      (item.participant.username?.toLowerCase().contains(query) ?? false) ||
      item.preview.toLowerCase().contains(query);

  Widget _heading() =>
      BlocBuilder<
        ChatListCubit<ChatConversation>,
        ChatListState<ChatConversation>
      >(
        bloc: _list,
        builder: (context, state) {
          if (widget.requests ||
              !_valid ||
              (state.loading && !state.hasLoaded && state.items.isEmpty)) {
            return const SizedBox.shrink();
          }
          final query = _search.text.trim().toLowerCase();
          if (query.isNotEmpty) {
            if (state.items.isEmpty ||
                (_repo is! ConversationSearchRepository &&
                    !state.items.any((item) => _matches(item, query)))) {
              return const SizedBox.shrink();
            }
            return const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Chats',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          return Row(
            children: [
              const Expanded(
                child: Text(
                  'Messages',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .5,
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: !_valid
                      ? null
                      : () async {
                          if (_opening) return;
                          _opening = true;
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => chatRouteScope(
                                context,
                                ChatsScreen(
                                  repository: widget.repository,
                                  requests: true,
                                  onRequestResolved: _requestResolved,
                                ),
                              ),
                            ),
                          );
                          _opening = false;
                          if (mounted && _valid) unawaited(_refresh());
                        },
                  child: Text(
                    (_requestCount ?? 0) <= 0
                        ? 'Requests'
                        : 'Requests ($_requestCount)',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: DarkColors.primaryColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.requests
        ? Colors.black
        : DarkColors.backgroundColor,
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(20)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const BackButtonWidget(),
                  Expanded(
                    child: Text(
                      widget.requests ? 'Requests' : 'Chats',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!widget.requests)
                    IconButton(
                      tooltip: 'New conversation',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF151515),
                        side: const BorderSide(color: Colors.white12),
                        minimumSize: const Size.square(44),
                        maximumSize: const Size.square(44),
                        shape: const CircleBorder(),
                      ),
                      onPressed: !_valid
                          ? null
                          : () async {
                              if (_opening) return;
                              _opening = true;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => chatRouteScope(
                                    context,
                                    NewConversationScreen(
                                      repository: widget.repository,
                                    ),
                                  ),
                                ),
                              );
                              _opening = false;
                              if (mounted && _valid) unawaited(_refresh());
                            },
                      icon: const Icon(Icons.add, color: Colors.white),
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),
            if (!widget.requests) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                enabled: _valid,
                onChanged: (_) => _searchChanged(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintFadeDuration: Duration.zero,
                  hintStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: SvgPicture.asset(
                      'assets/images/interactions/search-normal.svg',
                      width: 20,
                      height: 20,
                    ),
                  ),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            _searchChanged();
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: const Color(0xFF141414),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(32),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(32),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 8),
            if (_valid)
              ChatNetworkBanner(
                onReconnect: _refresh,
                onStatus: (value) {
                  if (mounted && _offline != (value == false)) {
                    setState(() => _offline = value == false);
                  }
                },
              ),
            _heading(),
            Expanded(
              child:
                  BlocBuilder<
                    ChatListCubit<ChatConversation>,
                    ChatListState<ChatConversation>
                  >(
                    bloc: _list,
                    builder: (context, state) {
                      if (!_valid) {
                        return const Center(
                          child: Text('Sign in again to use messaging.'),
                        );
                      }
                      final query = _search.text.trim().toLowerCase();
                      final items = state.items
                          .where(
                            (item) =>
                                _repo is ConversationSearchRepository ||
                                _matches(item, query),
                          )
                          .toList();
                      return NotificationListener<ScrollNotification>(
                        onNotification: (event) {
                          if (event.metrics.extentAfter < 160 &&
                              !state.loading &&
                              state.continuation != null) {
                            unawaited(_list.load(more: true));
                          }
                          return false;
                        },
                        child: RefreshIndicator.adaptive(
                          color: DarkColors.primaryColor,
                          onRefresh: _refresh,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              if (state.loading &&
                                  !state.hasLoaded &&
                                  state.items.isEmpty)
                                const ChatsLoadingSkeleton()
                              else if (state.error != null &&
                                  state.items.isEmpty)
                                ErrorRetryView(
                                  message: state.error!,
                                  onRetry: _refresh,
                                )
                              else if (items.isEmpty && _offline)
                                ErrorRetryView(
                                  message:
                                      'Reconnect to load your conversations.',
                                  onRetry: _refresh,
                                )
                              else if (items.isEmpty &&
                                  query.isEmpty &&
                                  !widget.requests &&
                                  state.error == null &&
                                  state.hasLoaded &&
                                  !state.loading)
                                const _EmptyChats()
                              else if (items.isEmpty &&
                                  state.hasLoaded &&
                                  !state.loading)
                                Padding(
                                  padding: const EdgeInsets.only(top: 64),
                                  child: Text(
                                    query.isNotEmpty
                                        ? 'No Results Found'
                                        : 'No message requests',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                )
                              else
                                ...items.map(
                                  (item) => ChatListTile(
                                    key: ValueKey(item.id),
                                    conversation: item,
                                    onTap: () => _open(item),
                                  ),
                                ),
                              if (state.error != null && state.items.isNotEmpty)
                                ErrorRetryView(
                                  message: state.error!,
                                  onRetry: _refresh,
                                ),
                              if (state.loadingMore && state.items.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CupertinoActivityIndicator(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 64),
    child: Column(
      children: [
        const ChatEmptyIllustration(),
        const SizedBox(height: 24),
        const Text(
          'No messages yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Start a conversation with someone and your chats will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
        ),
      ],
    ),
  );
}
