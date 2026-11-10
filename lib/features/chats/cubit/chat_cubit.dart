import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import '../data/chat_drafts.dart';
import '../data/chat_history_cache.dart';

class ChatListState<T> {
  const ChatListState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.continuation,
    this.session = 0,
    this.hasLoaded = false,
    this.loadingMore = false,
  });
  final bool hasLoaded, loadingMore;
  final List<T> items;
  final bool loading;
  final String? error, continuation;
  final int session;
}

/// One instance per route/account. No disk cache of private conversations.
class ChatListCubit<T> extends Cubit<ChatListState<T>> {
  ChatListCubit({
    required this.fetch,
    required this.idOf,
    required this.cancel,
    this.prependPages = false,
    this.mergeRefresh = false,
    this.compare,
    this.reconcile,
    this.cacheKey,
    this.cacheGroup,
    this.cacheItemLimit,
    this.cacheWhen,
    ChatHistoryCache? cache,
    PreferencesManager? preferences,
  }) : _preferences = preferences ?? PreferencesManager(),
       super(const ChatListState()) {
    _cache = cache ?? ChatHistoryCache.instance;
    final snapshot = cacheKey == null
        ? null
        : _cache.read<_HistorySnapshot<T>>(cacheKey!, group: cacheGroup);
    if (snapshot != null) {
      _removed.addAll(snapshot.removed);
      emit(snapshot.state);
      chatLoadDiagnostic('cache_hit', count: state.items.length);
    }
    _preferences.addListener(_sessionChanged);
  }
  final Object? cacheKey;
  final String? cacheGroup;
  final int? cacheItemLimit;
  final bool Function()? cacheWhen;
  late final ChatHistoryCache _cache;
  final Future<ChatPage<T>> Function(String? continuation) fetch;
  final String Function(T) idOf;
  final void Function() cancel;
  final bool prependPages;
  final bool mergeRefresh;
  final int Function(T, T)? compare;
  final T Function(T existing, T incoming)? reconcile;
  final PreferencesManager _preferences;
  int _generation = 0, _eventRevision = 0;
  final Map<String, int> _itemEvents = {};
  final Set<String> _removed = {};
  Future<void>? _pending;
  void _sessionChanged() {
    ++_generation;
    _itemEvents.clear();
    if (state.session != _preferences.sessionRevision) _removed.clear();
    cancel();
    _pending = null;
    emit(ChatListState(session: _preferences.sessionRevision));
  }

  Future<void> load({bool more = false}) {
    if (isClosed || !_preferences.hasSession) return Future.value();
    if (_pending != null) return _pending!;
    if (more && state.continuation == null) return Future.value();
    final generation = ++_generation, session = _preferences.sessionRevision;
    final before = state;
    chatLoadDiagnostic(
      more
          ? 'pagination'
          : before.hasLoaded
          ? 'background_refresh'
          : 'initial_load',
      count: before.items.length,
    );
    emit(
      ChatListState(
        items: before.items,
        hasLoaded: before.hasLoaded,
        loadingMore: more,
        loading: true,
        continuation: before.continuation,
        session: session,
      ),
    );
    final request = _load(before, more, generation, session, _eventRevision);
    _pending = request;
    return request.whenComplete(() {
      if (generation == _generation) _pending = null;
    });
  }

  Future<void> _load(
    ChatListState<T> before,
    bool more,
    int generation,
    int session,
    int eventRevision,
  ) async {
    try {
      final page = await fetch(more ? before.continuation : null);
      if (!_current(generation, session)) return;
      final merged = more && prependPages
          ? [...page.items, ...before.items]
          : [...(more || mergeRefresh ? before.items : <T>[]), ...page.items];
      final unique = <String, T>{};
      for (final item in merged) {
        final id = idOf(item);
        unique[id] = unique.containsKey(id) && reconcile != null
            ? reconcile!(unique[id] as T, item)
            : item;
      }
      // Events arriving after this HTTP request started win over its snapshot.
      for (final item in state.items) {
        if ((_itemEvents[idOf(item)] ?? 0) > eventRevision) {
          final id = idOf(item);
          unique[id] = unique.containsKey(id) && reconcile != null
              ? reconcile!(unique[id] as T, item)
              : item;
        }
      }
      unique.removeWhere((id, _) => _removed.contains(id));
      final values = unique.values.toList();
      if (compare != null) values.sort(compare);
      emit(
        ChatListState(
          items: List.unmodifiable(values),
          hasLoaded: true,
          continuation: !more && mergeRefresh && before.items.isNotEmpty
              ? before.continuation
              : page.continuation == before.continuation && more
              ? null
              : page.continuation,
          session: session,
        ),
      );
    } catch (error) {
      if (_current(generation, session)) {
        emit(
          ChatListState(
            items: state.items,
            hasLoaded: state.hasLoaded,
            continuation: before.continuation,
            error: error is ApiError
                ? error.message
                : 'Unable to load messages. Please retry.',
            session: session,
          ),
        );
      }
    }
  }

  bool _current(int generation, int session) =>
      !isClosed &&
      generation == _generation &&
      session == _preferences.sessionRevision;

  /// Only a confirmed repository response, never an optimistic receipt.
  void appendConfirmed(T item, {required int session}) {
    if (isClosed ||
        !_preferences.hasSession ||
        session != _preferences.sessionRevision) {
      return;
    }
    if (_removed.contains(idOf(item))) return;
    _itemEvents[idOf(item)] = ++_eventRevision;
    final existing = state.items.where((value) => idOf(value) == idOf(item));
    final resolved = existing.isNotEmpty && reconcile != null
        ? reconcile!(existing.first, item)
        : item;
    final unique = <String, T>{
      for (final existing in state.items) idOf(existing): existing,
      idOf(item): resolved,
    };
    final values = unique.values.toList();
    if (compare != null) values.sort(compare);
    emit(
      ChatListState(
        items: List.unmodifiable(values),
        hasLoaded: state.hasLoaded,
        loadingMore: state.loadingMore,
        continuation: state.continuation,
        error: state.error,
        loading: state.loading,
        session: session,
      ),
    );
  }

  /// A confirmed removal wins over pending pages and stale refresh snapshots.
  /// Scoped to this route/account; a new session never inherits these IDs.
  void removeConfirmed(
    String id, {
    required int session,
    bool allowRestoration = false,
  }) {
    if (isClosed ||
        !_preferences.hasSession ||
        session != _preferences.sessionRevision) {
      return;
    }
    if (allowRestoration) {
      // Cancel pre-delete snapshots. A later canonical response may legitimately
      // restore a hidden thread when the other participant sends a new message.
      ++_generation;
      cancel();
      _pending = null;
    } else {
      _removed.add(id);
    }
    _itemEvents.remove(id);
    emit(
      ChatListState(
        items: List.unmodifiable(state.items.where((item) => idOf(item) != id)),
        hasLoaded: state.hasLoaded,
        loadingMore: state.loadingMore,
        loading: allowRestoration ? false : state.loading,
        error: state.error,
        continuation: state.continuation,
        session: session,
      ),
    );
  }

  /// Invalidate requests tied to an obsolete server-side search query.
  void invalidateQuery() {
    ++_generation;
    cancel();
    _pending = null;
    _itemEvents.clear();
    emit(ChatListState(session: _preferences.sessionRevision, loading: true));
  }

  Future<void> resetQuery() {
    invalidateQuery();
    return load();
  }

  @override
  void onChange(Change<ChatListState<T>> change) {
    super.onChange(change);
    final next = change.nextState;
    if (cacheKey != null &&
        (cacheWhen?.call() ?? true) &&
        (next.hasLoaded || next.items.isNotEmpty)) {
      final truncated =
          cacheItemLimit != null && next.items.length > cacheItemLimit!;
      _cache.write(
        cacheKey!,
        _HistorySnapshot<T>(
          ChatListState<T>(
            items: truncated
                ? List.unmodifiable(next.items.take(cacheItemLimit!))
                : next.items,
            // A truncated warm snapshot cannot safely reuse a cursor beyond its
            // retained rows. The next canonical refresh restores pagination.
            continuation: truncated ? null : next.continuation,
            session: next.session,
            hasLoaded: next.hasLoaded,
          ),
          Set.of(_removed),
        ),
        next.session,
        group: cacheGroup,
      );
    }
  }

  @override
  Future<void> close() {
    ++_generation;
    _preferences.removeListener(_sessionChanged);
    cancel();
    return super.close();
  }
}

class _HistorySnapshot<T> {
  const _HistorySnapshot(this.state, this.removed);
  final ChatListState<T> state;
  final Set<String> removed;
}

class ChatComposerState {
  const ChatComposerState({
    this.draft = '',
    this.sending = false,
    this.error,
    this.session = 0,
    this.replyTo,
    this.localMessages = const [],
  });
  final String draft;
  final bool sending;
  final String? error;
  final int session;
  final ChatMessage? replyTo;
  final List<ChatMessage> localMessages;
}

class ChatComposerCubit extends Cubit<ChatComposerState> {
  ChatComposerCubit({
    required this.repository,
    required this.conversation,
    required this.onSent,
    this.cacheKey,
    PreferencesManager? preferences,
  }) : _preferences = preferences ?? PreferencesManager(),
       super(const ChatComposerState()) {
    _ownerSession = _preferences.sessionRevision;
    final saved = cacheKey == null
        ? null
        : ChatHistoryCache.instance.read<_OutboxSnapshot>(cacheKey!);
    if (saved != null) {
      _local.addAll(saved.messages);
      _localReplies.addAll(saved.replies);
      _uncertain.addAll(saved.uncertain);
      _serverIds.addAll(saved.serverIds);
      _sequence = saved.sequence;
      _replyTo = saved.reply;
    }
    emit(
      ChatComposerState(
        localMessages: List.unmodifiable(_local.values),
        draft: ChatDrafts.instance.read(conversation.id),
        session: _preferences.sessionRevision,
        replyTo: _replyTo,
      ),
    );
    _preferences.addListener(_sessionChanged);
  }
  final Object? cacheKey;
  final ChatRepository repository;
  ChatConversation conversation;
  final void Function(ChatMessage) onSent;
  final PreferencesManager _preferences;
  late final int _ownerSession;
  ChatMessage? _replyTo;
  final Map<String, ChatMessage> _local = {};
  final Map<String, ChatMessage?> _localReplies = {};
  final Set<String> _uncertain = {};
  final Map<String, String> _serverIds = {};
  int _sequence = 0;
  bool retryNeedsConfirmation(String id) => _uncertain.contains(id);
  void setConversation(ChatConversation value) {
    if (value.id != conversation.id ||
        _ownerSession != _preferences.sessionRevision ||
        isClosed) {
      return;
    }
    conversation = value;
    emit(
      ChatComposerState(
        localMessages: List.unmodifiable(_local.values),
        draft: state.draft,
        sending: state.sending,
        error: state.error,
        session: _ownerSession,
        replyTo: _replyTo,
      ),
    );
  }

  void setReply(ChatMessage? value) {
    if (state.sending ||
        _ownerSession != _preferences.sessionRevision ||
        isClosed) {
      return;
    }
    _replyTo = value;
    emit(
      ChatComposerState(
        localMessages: List.unmodifiable(_local.values),
        draft: state.draft,
        session: _ownerSession,
        replyTo: _replyTo,
      ),
    );
  }

  void _sessionChanged() {
    _local.clear();
    _localReplies.clear();
    _uncertain.clear();
    _serverIds.clear();
    _replyTo = null;
    repository.cancel();
    emit(ChatComposerState(session: _preferences.sessionRevision));
  }

  void edit(String value) {
    if (_ownerSession != _preferences.sessionRevision) return;
    if (!state.sending) ChatDrafts.instance.write(conversation.id, value);
    if (!state.sending) {
      emit(
        ChatComposerState(
          localMessages: List.unmodifiable(_local.values),
          draft: value,
          session: _preferences.sessionRevision,
          replyTo: _replyTo,
        ),
      );
    }
  }

  Future<void> send() => _sendText(state.draft, reply: _replyTo);
  Future<void> retry(String id) async {
    final item = _local[id];
    if (item?.delivery != ChatDelivery.failed) return;
    await _sendText(item!.text, reply: _localReplies[id], retryId: id);
  }

  /// No body/time heuristics: only a server acknowledgement ID correlates text.
  bool reconcileUnknown(String localId, List<ChatMessage> history) {
    if (isClosed || _ownerSession != _preferences.sessionRevision) return false;
    final id = _serverIds[localId];
    final local = _local[localId];
    if (id == null ||
        local == null ||
        !history.any(
          (item) => item.id == id && item.conversationId == conversation.id,
        )) {
      return false;
    }
    _local.remove(localId);
    _localReplies.remove(localId);
    _uncertain.remove(localId);
    _serverIds.remove(localId);
    final draft = state.draft == local.text ? '' : state.draft;
    ChatDrafts.instance.write(conversation.id, draft);
    if (state.draft == local.text) _replyTo = null;
    emit(
      ChatComposerState(
        localMessages: List.unmodifiable(_local.values),
        draft: draft,
        session: _ownerSession,
        replyTo: _replyTo,
      ),
    );
    return true;
  }

  Future<void> _sendText(
    String text, {
    ChatMessage? reply,
    String? retryId,
  }) async {
    if (isClosed ||
        _ownerSession != _preferences.sessionRevision ||
        state.sending ||
        text.trim().isEmpty ||
        !_preferences.hasSession) {
      return;
    }
    if (!conversation.canSend || !repository.capabilities.sendText) {
      emit(
        ChatComposerState(
          localMessages: List.unmodifiable(_local.values),
          draft: state.draft,
          error: ChatUnavailable().message,
          session: _ownerSession,
          replyTo: _replyTo,
        ),
      );
      return;
    }
    final id = retryId ?? 'local-$_ownerSession-${++_sequence}';
    final created = _local[id]?.createdAt ?? DateTime.now();
    _localReplies[id] = reply;
    ChatMessage local(ChatDelivery status) => ChatMessage(
      id: id,
      senderId: '',
      kind: ChatMessageKind.text,
      text: text,
      createdAt: created,
      delivery: status,
      conversationId: conversation.id,
    );
    _local[id] = local(ChatDelivery.sending);
    final session = _preferences.sessionRevision;
    emit(
      ChatComposerState(
        localMessages: List.unmodifiable(_local.values),
        draft: state.draft,
        sending: true,
        session: session,
        replyTo: _replyTo,
      ),
    );
    try {
      final repo = repository;
      final message = reply != null && repo is ChatOperationsRepository
          ? await (repo as ChatOperationsRepository).reply(
              conversation.id,
              text,
              reply.id,
            )
          : await repository.sendText(conversation.id, text);
      if (isClosed || session != _preferences.sessionRevision) return;
      _local.remove(id);
      _localReplies.remove(id);
      _uncertain.remove(id);
      _serverIds.remove(id);
      final draft = state.draft == text ? '' : state.draft;
      ChatDrafts.instance.write(conversation.id, draft);
      if (state.draft == text) _replyTo = null;
      emit(
        ChatComposerState(
          localMessages: List.unmodifiable(_local.values),
          draft: draft,
          session: session,
          replyTo: _replyTo,
        ),
      );
      onSent(message);
    } catch (error) {
      if (isClosed || session != _preferences.sessionRevision) return;
      _local[id] = local(ChatDelivery.failed);
      if (error is ChatUnconfirmedSend && error.serverMessageId != null) {
        _serverIds[id] = error.serverMessageId!;
      }
      final explicitRejection =
          error is ChatPreSendFailure ||
          error is ApiError &&
              error.statusCode != null &&
              error.statusCode! >= 400 &&
              error.statusCode! < 500;
      if (!explicitRejection) {
        _uncertain.add(id);
      }
      // A failed retry must not erase ambiguity from an earlier timed-out send.
      emit(
        ChatComposerState(
          localMessages: List.unmodifiable(_local.values),
          draft: state.draft,
          session: session,
          replyTo: _replyTo,
          error: explicitRejection
              ? (error as ApiError).message
              : 'Send was not confirmed. Check the conversation before trying again.',
        ),
      );
    }
  }

  void _saveOutbox() {
    if (cacheKey == null) return;
    ChatHistoryCache.instance.write(
      cacheKey!,
      _OutboxSnapshot(
        Map.of(_local),
        Map.of(_localReplies),
        Set.of(_uncertain),
        Map.of(_serverIds),
        _sequence,
        _replyTo,
      ),
      _ownerSession,
    );
  }

  @override
  void onChange(Change<ChatComposerState> change) {
    super.onChange(change);
    _saveOutbox();
  }

  @override
  Future<void> close() {
    // An interrupted request is ambiguous, never automatically resend it.
    for (final item in _local.values.toList()) {
      if (item.delivery == ChatDelivery.sending) {
        _local[item.id] = ChatMessage(
          id: item.id,
          senderId: item.senderId,
          kind: item.kind,
          text: item.text,
          createdAt: item.createdAt,
          conversationId: item.conversationId,
          delivery: ChatDelivery.failed,
        );
        _uncertain.add(item.id);
      }
    }
    _saveOutbox();
    _preferences.removeListener(_sessionChanged);
    return super.close();
  }
}

class _OutboxSnapshot {
  const _OutboxSnapshot(
    this.messages,
    this.replies,
    this.uncertain,
    this.serverIds,
    this.sequence,
    this.reply,
  );
  final Map<String, ChatMessage> messages;
  final Map<String, ChatMessage?> replies;
  final Set<String> uncertain;
  final Map<String, String> serverIds;
  final int sequence;
  final ChatMessage? reply;
}
