import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import '../data/chat_history_cache.dart';
import '../widgets/chat_request_controls.dart';
import '../widgets/chat_loading.dart';
import '../widgets/chat_network_banner.dart';
import '../widgets/chat_options.dart';
import 'conversation_details_screen.dart';
import 'chat_navigation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import '../widgets/chat_pending_media_bubble.dart';
import '../data/chat_media_selection.dart';
import '../widgets/chat_selected_media_tray.dart';
import '../data/chat_presence_presentation.dart';
import '../widgets/chat_pull_to_refresh.dart';
import '../widgets/chat_reverb_host.dart';
import '../data/chat_reverb_service.dart';
import '../data/chat_broadcast_event.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import '../cubit/chat_audio_controller.dart';
import '../widgets/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/notifications/push_notifications_host.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import '../cubit/chat_cubit.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import '../widgets/chat_widgets.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversation,
    this.repository,
    this.currentUserId,
    this.mediaUploader,
    this.pickAttachments,
    this.receivedRequest = false,
    this.onRequestResolved,
    this.onDeleted,
    this.markReadOnOpen = true,
  });
  final ChatConversation conversation;

  /// False when the caller already marked this conversation read.
  final bool markReadOnOpen;
  final VoidCallback? onDeleted;
  final bool receivedRequest;
  final void Function(ChatConversation conversation, bool accepted)?
  onRequestResolved;
  final ChatRepository? repository;
  final String? currentUserId;
  final MediaUploadService? mediaUploader;
  final Future<List<XFile>> Function(ImageSource source)? pickAttachments;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  late final _repo = widget.repository ?? LaravelChatRepository();
  // Closing the history list cancels `_repo`; a read must survive leaving.
  late final ChatRepository _readRepo =
      widget.repository ?? LaravelChatRepository();
  bool _openReadStarted = false;
  Object get _historyKey =>
      (widget.repository ?? LaravelChatRepository, widget.conversation.id);
  late final _list = ChatListCubit<ChatMessage>(
    cacheKey: _historyKey,
    prependPages: true,
    mergeRefresh: true,
    reconcile: reconcileChatMessage,
    compare: (a, b) =>
        (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0),
    fetch: (next) => _repo.messages(widget.conversation.id, continuation: next),
    idOf: (message) => message.id,
    cancel: _repo.cancel,
  );
  late final _composer = ChatComposerCubit(
    cacheKey: (_historyKey, 'outbox'),
    repository: _repo,
    conversation: widget.receivedRequest
        ? widget.conversation.withSending(false)
        : widget.conversation,
    onSent: (message) => unawaited(_receivedSentMessage(message)),
  );
  final _text = TextEditingController();
  final _textFocus = FocusNode();
  final _attachmentAnchor = GlobalKey();
  late final _scroll = ScrollController(
    initialScrollOffset:
        ChatHistoryCache.instance.read<double>((_historyKey, 'scroll')) ?? 0,
  );
  final _preferences = PreferencesManager();
  late final _audio = ChatAudioController();
  MediaUploadService? _uploader;
  final _uploadCancel = CancelToken();
  ChatMediaSelection? _pendingMedia;
  final _selections = ChatMediaSelectionQueue();
  bool _sendingSelections = false;
  double? _uploadProgress;
  bool _uploading = false, _picking = false, _managing = false;
  bool _allowPop = false;
  String? _mediaError;
  String? _expandedMessageId;
  Timer? _typingCooldown, _typingIdle;
  bool _retryBusy = false;
  bool _requestBusy = false, _accepting = false, _requestDialogOpen = false;
  bool _requestResolved = false;
  String? _requestError;
  bool get _pendingRequest {
    final value = _details ?? widget.conversation;
    return value.isAccepted != true &&
        (widget.receivedRequest ||
            (value.isAccepted == false && !widget.conversation.canSend));
  }

  bool get _blockedLocally {
    final id = (_details ?? widget.conversation).participant.id;
    final state = context.read<BlockCubit?>()?.state;
    return state?.isBlocked(id) == true || state?.pending.contains(id) == true;
  }

  bool? _lastLocalBlock;
  bool get _canSend =>
      !_pendingRequest &&
      !_blockedLocally &&
      (_details ?? widget.conversation).canSend &&
      _repo.capabilities.sendText &&
      _valid;
  bool _lastRecording = false;
  ChatVoiceDraft? _lastVoiceDraft;
  void _audioChanged() {
    // Playback position is rendered by the bubble, not the entire conversation.
    if (_lastRecording == _audio.recording &&
        identical(_lastVoiceDraft, _audio.draft)) {
      return;
    }
    _lastRecording = _audio.recording;
    _lastVoiceDraft = _audio.draft;
    if (mounted) setState(() {});
  }

  late final _session = _preferences.sessionRevision;
  StreamSubscription<dynamic>? _activity;
  StreamSubscription<ChatReverbSignal>? _realtime;
  ChatReverbService? _reverb;
  Animation<double>? _covered;
  Timer? _liveRead;
  void _visibility(AnimationStatus _) => _bindConversation();
  void _bindConversation() {
    if (!mounted || !_valid) return;
    final visible = ModalRoute.of(context)?.isCurrent != false;
    _reverb?.conversation(
      this,
      visible && !_pendingRequest && !_blockedLocally
          ? (_details ?? widget.conversation)
          : null,
    );
  }

  void _presenceChanged() {
    if (mounted && _valid) setState(() {});
  }

  void _serverEvent(ChatReverbSignal signal) {
    if (!mounted || !_valid || signal.session != _session) return;
    if (signal.name == 'reconcile') {
      chatLoadDiagnostic('reverb_reconciliation');
      unawaited(_refresh());
      return;
    }
    final event = signal.event;
    if (event is ChatMessageSent &&
        event.message.conversationId == widget.conversation.id) {
      final followLatest = !_scroll.hasClients || _scroll.offset < 100;
      _list.appendConfirmed(event.message, session: _session);
      if (followLatest) _bottom();
      _liveRead?.cancel();
      _liveRead = Timer(const Duration(milliseconds: 180), () {
        if (mounted && _valid && ModalRoute.of(context)?.isCurrent != false) {
          unawaited(_refresh());
        }
      });
    } else if (event is ChatMessagesRead &&
        event.conversationId == widget.conversation.id) {
      final user =
          widget.currentUserId ??
          context.read<CurrentUserCubit?>()?.state.profile?.id;
      if (user == null) return;
      for (final message in event.apply(
        _list.state.items,
        currentUserId: user,
      )) {
        _list.appendConfirmed(message, session: _session);
      }
    }
  }

  bool _refreshing = false, _refreshAgain = false;
  ChatConversation? _details;
  String? _detailError;
  bool _loadingDetails = false;
  int _headerEpoch = 0;
  DateTime? _changesSince;
  String? _syncError;
  bool get _valid =>
      _preferences.hasSession && _session == _preferences.sessionRevision;
  @override
  void initState() {
    super.initState();
    _text.text = _composer.state.draft;
    // A reopened history may include older pages. Reconcile their edits and
    // tombstones through updated_since, not just the newest REST page.
    _changesSince = ChatHistoryCache.instance.read<DateTime>((
      _historyKey,
      'changes_since',
    ));
    if (_changesSince == null) {
      for (final message in _list.state.items) {
        final updated = message.updatedAt;
        if (updated != null &&
            (_changesSince == null || updated.isAfter(_changesSince!))) {
          _changesSince = updated;
        }
      }
    }
    _audio.addListener(_audioChanged);
    _preferences.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  void _sessionChanged() {
    _text.clear();
    _expandedMessageId = null;
    _details = null;
    _detailError = null;
    _changesSince = null;
    _headerEpoch++;
    _syncError = null;
    _pendingMedia = null;
    _selections.clear();
    _mediaError = null;
    _uploadCancel.cancel();
    _typingCooldown?.cancel();
    _typingIdle?.cancel();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reverb = ChatReverbScope.maybeOf(context);
    if (!identical(reverb, _reverb)) {
      _reverb?.conversation(this, null);
      _reverb?.removeListener(_presenceChanged);
      unawaited(_realtime?.cancel() ?? Future.value());
      _reverb = reverb;
      _realtime = reverb?.signals.listen(_serverEvent);
      reverb?.addListener(_presenceChanged);
    }
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(covered, _covered)) {
      _covered?.removeStatusListener(_visibility);
      _covered = covered;
      covered?.addStatusListener(_visibility);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindConversation());
    if (!_openReadStarted) {
      _openReadStarted = true;
      // Read at open, not after history: leaving early must not skip it.
      if (widget.markReadOnOpen) {
        unawaited(_markRead().then<void>((_) {}, onError: (Object _) {}));
      }
    }
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
    if (state == AppLifecycleState.resumed && _valid) {
      _audio.resume();
      unawaited(_refresh());
    } else {
      _typingCooldown?.cancel();
      _typingIdle?.cancel();
      _typingCooldown = null;
      _typingIdle = null;
      unawaited(_sendTyping(false));
      unawaited(_audio.pause());
    }
  }

  Future<void> _onlineAgain() async {
    if (!mounted) return;
    ChatReverbScope.maybeOf(context)?.reconnectNow();
    await _refresh();
  }

  Future<void> _refresh() async {
    if (!_valid) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    _refreshAgain = false;
    final headerEpoch = _headerEpoch;
    final history = _list.load();
    try {
      final repository = _repo;
      if (repository is ConversationDetailsRepository &&
          repository.capabilities.detail) {
        if (mounted) setState(() => _loadingDetails = true);
        try {
          final details = await (repository as ConversationDetailsRepository)
              .conversation(widget.conversation.id);
          if (mounted && _valid && headerEpoch == _headerEpoch) {
            _assignConversation(details);
            _detailError = null;
          }
        } catch (_) {
          if (mounted && _valid && headerEpoch == _headerEpoch) {
            setState(
              () => _detailError =
                  'Unable to load this conversation. Please retry.',
            );
          }
        } finally {
          if (mounted) setState(() => _loadingDetails = false);
        }
      }
      if (!_valid || !mounted) return;
      await history;
      if (!mounted || !_valid) return;
      if (_valid &&
          _list.state.error == null &&
          _repo is ChatOperationsRepository) {
        DateTime? anchor;
        for (final message in _list.state.items) {
          final updated = message.updatedAt;
          if (updated != null && (anchor == null || updated.isAfter(anchor))) {
            anchor = updated;
          }
        }
        final since = _changesSince;
        if (since != null) {
          try {
            String? next;
            final pages = <String?>{};
            do {
              if (WidgetsBinding.instance.lifecycleState != null &&
                  WidgetsBinding.instance.lifecycleState !=
                      AppLifecycleState.resumed) {
                return;
              }
              if (!pages.add(next)) throw const FormatException();
              final changes = await (_repo as ChatOperationsRepository)
                  .messageChanges(
                    widget.conversation.id,
                    updatedSince: since,
                    continuation: next,
                  );
              if (!mounted || !_valid) return;
              for (final item in changes.items) {
                _list.appendConfirmed(item, session: _session);
                if (item.isDeleted && _audio.currentMessageId == item.id) {
                  unawaited(_audio.stopPlayback());
                }
                if (_composer.state.replyTo?.id == item.id) {
                  _composer.setReply(item);
                }
              }
              next = changes.continuation;
            } while (next != null);
            if (mounted) setState(() => _syncError = null);
            _changesSince = anchor ?? since;
          } catch (_) {
            if (mounted && _valid && headerEpoch == _headerEpoch) {
              setState(
                () => _syncError =
                    'Unable to synchronize message updates. Please retry.',
              );
            }
          }
        } else {
          _changesSince = anchor;
        }
      }
      if (_changesSince != null) {
        ChatHistoryCache.instance.write(
          (_historyKey, 'changes_since'),
          _changesSince!,
          _session,
        );
      }
      if (_valid && _list.state.error == null && _repo.capabilities.read) {
        if (ModalRoute.of(context)?.isCurrent != false &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed)) {
          final result = await _markRead();
          if (result != null &&
              mounted &&
              _valid &&
              headerEpoch == _headerEpoch) {
            _assignConversation(result);
            if (_requestResolved && _details?.isAccepted == true) {
              widget.onRequestResolved?.call(_details!, true);
            }
          }
        }
      }
    } catch (_) {
      // Reading the conversation must survive a failed read-receipt mutation.
    } finally {
      _refreshing = false;
      if (_refreshAgain &&
          mounted &&
          _valid &&
          ModalRoute.of(context)?.isCurrent != false) {
        _refreshAgain = false;
        unawaited(_refresh());
      }
    }
  }

  /// Marks the conversation read on [_readRepo] and updates the app badges
  /// even if this screen is popped before the request finishes.
  Future<ChatConversation?> _markRead() async {
    if (!_valid || !_readRepo.capabilities.read) return null;
    final id = widget.conversation.id;
    final push = PushNotificationsScope.maybeOf(context);
    final unread = ChatReverbScope.unreadOf(context);
    final repo = _readRepo;
    final request = repo is ChatOperationsRepository
        ? (repo as ChatOperationsRepository).readConversation(id)
        : repo.markRead(id).then<ChatConversation?>((_) => null);
    unawaited(unread?.trackRead(id, request));
    final result = await request;
    if (_valid) push?.refreshCount(invalidate: true);
    return result;
  }

  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  });
  Future<void> _receivedSentMessage(ChatMessage message) async {
    if (!mounted || !_valid) return;
    final followLatest = !_scroll.hasClients || _scroll.offset < 100;
    _list.appendConfirmed(message, session: _session);
    if (followLatest) _bottom();
    await _list.load();
    if (!mounted || !_valid) return;
    // A pending older REST response must not discard this confirmed send;
    // equally, never overwrite newer server receipts or a deletion with Sent.
    if (!_list.state.items.any((item) => item.id == message.id)) {
      _list.appendConfirmed(message, session: _session);
    }
    if (followLatest) _bottom();
  }

  @override
  void dispose() {
    _covered?.removeStatusListener(_visibility);
    _liveRead?.cancel();
    _reverb?.removeListener(_presenceChanged);
    _reverb?.conversation(this, null);
    unawaited(_realtime?.cancel() ?? Future.value());
    _typingCooldown?.cancel();
    _typingIdle?.cancel();
    unawaited(_sendTyping(false));
    _uploadCancel.cancel();
    _uploader?.close();
    _audio.removeListener(_audioChanged);
    _audio.dispose();
    _preferences.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_activity?.cancel() ?? Future<void>.value());
    unawaited(_composer.close());
    unawaited(_list.close());
    _text.dispose();
    _textFocus.dispose();
    if (_changesSince != null) {
      ChatHistoryCache.instance.write(
        (_historyKey, 'changes_since'),
        _changesSince!,
        _session,
      );
    }
    if (_scroll.hasClients) {
      ChatHistoryCache.instance.write(
        (_historyKey, 'scroll'),
        _scroll.offset.clamp(0, double.infinity),
        _session,
      );
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user =
        widget.currentUserId ??
        context.watch<CurrentUserCubit?>()?.state.profile?.id;
    final participant = (_details ?? widget.conversation).participant;
    final blocks = context.watch<BlockCubit?>()?.state;
    if (_lastLocalBlock != _blockedLocally) {
      _lastLocalBlock = _blockedLocally;
      WidgetsBinding.instance.addPostFrameCallback((_) => _bindConversation());
    }
    final presenceLabel = chatPresenceLabel(
      _details ?? widget.conversation,
      blocked:
          blocks?.isBlocked(participant.id) == true ||
          blocks?.pending.contains(participant.id) == true,
      typing: _reverb?.typing == true,
      memberOnline: _reverb?.memberOnline(participant.id) == true,
    );
    return PopScope<Object?>(
      canPop:
          _allowPop ||
          !_valid ||
          (!_requestBusy &&
              !_uploading &&
              !_sendingSelections &&
              _selections.isEmpty &&
              !_audio.recording &&
              _audio.draft == null &&
              _pendingMedia == null),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leaveDraft());
      },
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        body: SafeArea(
          child: !_valid
              ? Column(
                  children: [
                    const BackButtonWidget(),
                    const Expanded(
                      child: Center(
                        child: Text('Sign in again to use messaging.'),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          const BackButtonWidget(),
                          const SizedBox(width: 10),
                          InkWell(
                            key: const ValueKey(
                              'conversation-participant-profile',
                            ),
                            customBorder: const CircleBorder(),
                            onTap:
                                participant.isBlocked == true ||
                                    int.tryParse(participant.id) == null
                                ? null
                                : () => ProfileScreen.open(
                                    context,
                                    userId: int.parse(participant.id),
                                  ),
                            child: HomeUserAvatar(
                              url: participant.avatarUrl,
                              size: 40,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: _showDetails,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    participant.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (presenceLabel != null)
                                    Text(
                                      presenceLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Conversation options',
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(44),
                              maximumSize: const Size.square(44),
                              backgroundColor: const Color(0xFF151515),
                              side: const BorderSide(color: Colors.white12),
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.more_vert, size: 22),
                            onPressed: _options,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: BlocBuilder<ChatComposerCubit, ChatComposerState>(
                        bloc: _composer,
                        builder: (context, outbox) =>
                            BlocBuilder<
                              ChatListCubit<ChatMessage>,
                              ChatListState<ChatMessage>
                            >(
                              bloc: _list,
                              builder: (context, state) {
                                // Wire adapter returns server-authoritative chronological ordering.
                                final messages = [
                                  ...outbox.localMessages.reversed,
                                  ...state.items.reversed,
                                ];
                                final deletedIds = state.items
                                    .where((m) => m.isDeleted)
                                    .map((m) => m.id)
                                    .toSet();
                                return NotificationListener<ScrollNotification>(
                                  onNotification: (event) {
                                    ChatHistoryCache.instance.write(
                                      (_historyKey, 'scroll'),
                                      event.metrics.pixels.clamp(
                                        0,
                                        double.infinity,
                                      ),
                                      _session,
                                    );
                                    if (event.metrics.extentAfter < 120 &&
                                        !state.loading &&
                                        state.continuation != null) {
                                      unawaited(_list.load(more: true));
                                    }
                                    return false;
                                  },
                                  child: ChatPullToRefresh(
                                    onRefresh: _refresh,
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        controller: _scroll,
                                        reverse: true,
                                        physics: const BouncingScrollPhysics(
                                          parent:
                                              AlwaysScrollableScrollPhysics(),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                        itemCount:
                                            messages.length +
                                            1 +
                                            (_pendingMedia != null ? 1 : 0),
                                        itemBuilder: (context, listIndex) {
                                          final pending = _pendingMedia;
                                          if (pending != null &&
                                              listIndex == 0) {
                                            return ChatPendingMediaBubble(
                                              media: pending,
                                              sending:
                                                  _uploading ||
                                                  _sendingSelections,
                                              onRetry: () => unawaited(
                                                _selections.isNotEmpty
                                                    ? _sendSelections()
                                                    : _sendPendingMedia(),
                                              ),
                                            );
                                          }
                                          final index =
                                              listIndex -
                                              (pending != null ? 1 : 0);
                                          if (index == messages.length) {
                                            if ((_loadingDetails ||
                                                    state.loading) &&
                                                messages.isEmpty &&
                                                !state.hasLoaded) {
                                              return const ChatHistorySkeleton();
                                            }
                                            if (_syncError != null) {
                                              return ErrorRetryView(
                                                message: _syncError!,
                                                onRetry: _refresh,
                                              );
                                            }
                                            if (_detailError != null) {
                                              return ErrorRetryView(
                                                message: _detailError!,
                                                onRetry: _refresh,
                                              );
                                            }
                                            if (state.loadingMore) {
                                              return const Padding(
                                                padding: EdgeInsets.all(20),
                                                child: Center(
                                                  child:
                                                      CupertinoActivityIndicator(),
                                                ),
                                              );
                                            }
                                            if (state.error != null) {
                                              return ErrorRetryView(
                                                message: state.error!,
                                                onRetry: _refresh,
                                              );
                                            }
                                            return messages.isEmpty &&
                                                    _pendingMedia == null
                                                ? const Center(
                                                    child: Text(
                                                      'No messages yet',
                                                      style: TextStyle(
                                                        color: Colors.white60,
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox.shrink();
                                          }
                                          final message = messages[index];
                                          final previous =
                                              index + 1 < messages.length
                                              ? messages[index + 1].createdAt
                                              : null;
                                          final date = message.createdAt
                                              ?.toLocal();
                                          final showDate =
                                              date != null &&
                                              (previous == null ||
                                                  !DateUtils.isSameDay(
                                                    date,
                                                    previous.toLocal(),
                                                  ));
                                          return Column(
                                            key: ValueKey(message.id),
                                            children: [
                                              if (showDate)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 18,
                                                      ),
                                                  child: Text(
                                                    DateUtils.isSameDay(
                                                          date,
                                                          DateTime.now(),
                                                        )
                                                        ? 'Today'
                                                        : DateUtils.isSameDay(
                                                            date,
                                                            DateTime.now()
                                                                .subtract(
                                                                  const Duration(
                                                                    days: 1,
                                                                  ),
                                                                ),
                                                          )
                                                        ? 'Yesterday'
                                                        : MaterialLocalizations.of(
                                                            context,
                                                          ).formatMediumDate(
                                                            date,
                                                          ),
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              GestureDetector(
                                                onLongPress: () =>
                                                    _messageOptions(
                                                      message,
                                                      user,
                                                    ),
                                                child: ChatMessageBubble(
                                                  message: message,
                                                  detailsExpanded:
                                                      _expandedMessageId ==
                                                      message.id,
                                                  onDetailsTap: () => setState(
                                                    () => _expandedMessageId =
                                                        _expandedMessageId ==
                                                            message.id
                                                        ? null
                                                        : message.id,
                                                  ),
                                                  onRetry:
                                                      message.delivery ==
                                                          ChatDelivery.failed
                                                      ? () => _retryMessage(
                                                          message,
                                                        )
                                                      : null,
                                                  audio: _audio,
                                                  deletedMessageIds: deletedIds,
                                                  outgoing:
                                                      message.id.startsWith(
                                                        'local-',
                                                      ) ||
                                                      (user != null &&
                                                          user.isNotEmpty &&
                                                          message.senderId ==
                                                              user),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      // Do not keep outgoing controls/composer interactive during a fade.
                      layoutBuilder: (child, _) => child ?? const SizedBox(),
                      child: _pendingRequest
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ChatNetworkBanner(onReconnect: _onlineAgain),
                                ChatPendingRequestControls(
                                  key: const ValueKey(
                                    'pending-request-controls',
                                  ),
                                  accepting: _accepting,
                                  error: _requestError,
                                  onAccept:
                                      _requestBusy ||
                                          !_repo.capabilities.requestActions
                                      ? null
                                      : _acceptRequest,
                                  onDecline:
                                      _requestBusy ||
                                          !_repo.capabilities.requestActions
                                      ? null
                                      : _declineRequest,
                                ),
                              ],
                            )
                          : ChatComposer(
                              key: const ValueKey('accepted-chat-composer'),
                              topAccessory: ChatNetworkBanner(
                                onReconnect: _onlineAgain,
                                margin: const EdgeInsets.only(bottom: 8),
                              ),
                              composer: _composer,
                              text: _text,
                              focusNode: _textFocus,
                              attachmentAnchor: _attachmentAnchor,
                              audio: _audio,
                              canSend: _canSend,
                              disabledReason:
                                  (_details ?? widget.conversation).isBlocked ==
                                      true
                                  ? 'Messaging is blocked for this conversation.'
                                  : (_details ?? widget.conversation)
                                            .isAccepted ==
                                        false
                                  ? 'Accept this request from Message Requests before replying.'
                                  : 'Sending is currently unavailable.',
                              uploading: _uploading || _sendingSelections,
                              onSendAttachments: () =>
                                  unawaited(_sendSelections()),
                              selectedMediaTray: _selections.isEmpty
                                  ? null
                                  : ChatSelectedMediaTray(
                                      items: _selections.items,
                                      showSendButton: false,
                                      showUploadIndicator: false,
                                      sending: _uploading || _sendingSelections,
                                      progress: _uploadProgress,
                                      onRemove: _removeSelection,
                                      onSend: () =>
                                          unawaited(_sendSelections()),
                                    ),
                              onAttachment: _attachments,
                              onTyped: _typed,
                              onSendVoice: _sendVoice,
                              onDiscardMedia: _discardMedia,
                              mediaLabel: _selections.isEmpty
                                  ? _pendingMedia?.filename
                                  : null,
                              mediaError: _mediaError,
                              onRetryMedia: _pendingMedia != null && !_uploading
                                  ? () => unawaited(
                                      _selections.isNotEmpty
                                          ? _sendSelections()
                                          : _sendPendingMedia(),
                                    )
                                  : null,
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _assignConversation(ChatConversation value) {
    if (_details?.isAccepted == true && value.isAccepted != true) return;
    final pending = _pendingRequest;
    setState(() {
      _details = value.withSending(
        value.isBlocked == false &&
            (value.isAccepted == true ||
                (!widget.receivedRequest && widget.conversation.canSend)),
      );
      _composer.setConversation(_details!);
    });
    if (pending && value.isAccepted == true && !_requestResolved) {
      _requestResolved = true;
      widget.onRequestResolved?.call(_details!, true);
    }
    _bindConversation();
  }

  Future<void> _acceptRequest() async {
    if (!_valid || !_pendingRequest || _requestBusy) return;
    setState(() {
      _requestBusy = true;
      _accepting = true;
      _requestError = null;
    });
    _headerEpoch++;
    try {
      final ChatConversation result;
      if (_repo case ConversationRequestRepository requests) {
        result = await requests.acceptRequest(widget.conversation.id);
      } else {
        await _repo.resolveRequest(widget.conversation.id, accept: true);
        if (!_valid || !mounted) return;
        if (_repo case ConversationDetailsRepository details) {
          result = await details.conversation(widget.conversation.id);
        } else {
          throw StateError(
            'Acceptance requires an authoritative conversation response.',
          );
        }
      }
      if (!mounted || !_valid) return;
      if (result.id != widget.conversation.id || result.isAccepted != true) {
        throw StateError('Acceptance not confirmed.');
      }
      _assignConversation(result);
      unawaited(_refresh());
    } catch (_) {
      if (mounted && _valid) {
        setState(
          () => _requestError =
              'Unable to accept request. Please try again or refresh.',
        );
      }
    } finally {
      if (mounted && _valid) {
        setState(() {
          _requestBusy = false;
          _accepting = false;
        });
      }
    }
  }

  Future<void> _declineRequest() async {
    if (!_valid || !_pendingRequest || _requestBusy || _requestDialogOpen) {
      return;
    }
    _requestDialogOpen = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => ChatDeclineRequestDialog(
          onConfirm: () async {
            if (!_valid || !_pendingRequest || _requestBusy) {
              throw StateError('Session changed');
            }
            setState(() => _requestBusy = true);
            _headerEpoch++;
            try {
              await _repo.resolveRequest(widget.conversation.id, accept: false);
              if (!mounted || !_valid) throw StateError('Session changed');
              _requestResolved = true;
              unawaited(
                ChatReverbScope.unreadOf(context)?.refresh() ?? Future.value(),
              );
              PushNotificationsScope.maybeOf(
                context,
              )?.refreshCount(invalidate: true);
              widget.onRequestResolved?.call(
                _details ?? widget.conversation,
                false,
              );
            } finally {
              if (mounted && _valid) setState(() => _requestBusy = false);
            }
          },
        ),
      );
      if (confirmed == true && mounted && _valid) {
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Message request declined')),
        );
      }
    } finally {
      _requestDialogOpen = false;
    }
  }

  Future<void> _leaveDraft() async {
    if (_requestBusy) {
      _notice('Wait for the request update to finish.');
      return;
    }

    if (_uploading || _sendingSelections) {
      _notice('Wait for the attachment upload to finish.');
      return;
    }
    if (_managing) return;
    _managing = true;
    try {
      if (await _confirm(
            'Discard attachment?',
            'Your unsent recording or attachment will be discarded.',
          ) &&
          mounted) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } finally {
      _managing = false;
    }
  }

  Future<bool> _confirm(
    String title,
    String description, {
    bool destructive = true,
  }) => showGlassConfirmDialog(
    context,
    title: title,
    message: description,
    confirmLabel: 'Confirm',
    destructive: destructive,
  );
  void _notice(String message) {
    if (mounted && _valid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _retryMessage(ChatMessage message) async {
    if (!_valid || !_canSend || _retryBusy) return;
    _retryBusy = true;
    try {
      if (_composer.retryNeedsConfirmation(message.id)) {
        await _refresh();
        if (!mounted || !_valid) return;
        if (_composer.reconcileUnknown(message.id, _list.state.items)) return;
        // Text/body/time similarity cannot prove correlation without a server
        // client reference. Only an explicit choice may repeat an unknown send.
        if (!await _confirm(
          'Delivery unknown',
          'History was refreshed, but this send cannot be identified reliably. Sending again may create a duplicate.',
          destructive: false,
        )) {
          return;
        }
      }
      if (_valid) await _composer.retry(message.id);
    } finally {
      _retryBusy = false;
    }
  }

  Future<void> _showDetails() async {
    if (_managing || !_valid) return;
    if (_audio.recording) {
      _notice('Finish or cancel the recording before opening shared media.');
      return;
    }
    _managing = true;
    try {
      final screen = chatRouteScope(
        context,
        ConversationDetailsScreen(
          conversation: _details ?? widget.conversation,
          messages: _list,
          onRefresh: _refresh,
          onMute: _repo is ChatOperationsRepository ? _toggleMute : null,
          onAction: _userAction,
        ),
      );
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => screen),
      );
    } finally {
      _managing = false;
    }
  }

  Future<void> _userAction(ChatOption option) async {
    await chatUserAction(context, _details ?? widget.conversation, option);
    if (mounted && _valid && option == ChatOption.block) {
      _bindConversation();
      await _refresh();
    }
  }

  Future<void> _toggleMute() async {
    if (!_valid || _repo is! ChatOperationsRepository) return;
    try {
      final result = await (_repo as ChatOperationsRepository).setMuted(
        widget.conversation.id,
        (_details ?? widget.conversation).isMuted != true,
      );
      if (!mounted || !_valid) return;
      _headerEpoch++;
      setState(() {
        _details = result.withSending(
          (result.isAccepted == true || _canSend) && result.isBlocked == false,
        );
        _composer.setConversation(_details!);
      });
    } catch (_) {
      _notice('Unable to update the conversation. Please retry.');
    }
  }

  Future<void> _options() async {
    if (_managing || _requestBusy || _requestDialogOpen || !_valid) return;
    _managing = true;
    try {
      final operation = await showModalBottomSheet<ChatOption>(
        context: context,
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (_) => ChatOptionsSheet(canDelete: _repo.capabilities.remove),
      );
      if (!mounted || !_valid || operation == null) return;
      if (operation == ChatOption.delete) {
        if (_composer.state.sending ||
            _uploading ||
            _sendingSelections ||
            _audio.recording ||
            _audio.draft != null ||
            _pendingMedia != null ||
            _selections.isNotEmpty) {
          _notice(
            'Finish or cancel the current send or attachment before deleting this chat.',
          );
          return;
        }
        final deleted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ChatDeclineRequestDialog(
            title: 'Delete chat?',
            description: 'This will remove the chat from your messages.',
            confirmLabel: 'Delete',
            failureMessage: 'Unable to delete chat. Please try again.',
            onConfirm: () async {
              if (!_valid) throw const FormatException('Session changed.');
              await _repo.remove(widget.conversation.id);
              if (!_valid) throw const FormatException('Session changed.');
            },
          ),
        );
        if (!mounted || !_valid || deleted != true) return;
        // Parent inbox updates only after the successful mutation, not dialog entry.
        _allowPop = true;
        setState(() {});
        widget.onDeleted?.call();
        Navigator.pop(context);
      } else {
        await chatUserAction(
          context,
          _details ?? widget.conversation,
          operation,
        );
      }
    } finally {
      _managing = false;
    }
  }

  Future<void> _messageOptions(ChatMessage message, String? user) async {
    if (message.id.startsWith('local-') ||
        !_valid ||
        _managing ||
        message.isDeleted) {
      return;
    }
    _managing = true;
    try {
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF171717),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.text.isNotEmpty)
                ListTile(
                  title: const Text('Copy text'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              if (_canSend && _repo is ChatOperationsRepository)
                ListTile(
                  title: const Text('Reply'),
                  onTap: () => Navigator.pop(context, 'reply'),
                ),
              if (_repo is ChatOperationsRepository &&
                  user != null &&
                  user.isNotEmpty &&
                  message.senderId == user)
                ListTile(
                  title: const Text('Delete message'),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
            ],
          ),
        ),
      );
      if (!_valid || !mounted) return;
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: message.text));
      } else if (action == 'reply') {
        _composer.setReply(message);
      } else if (action == 'delete' &&
          await _confirm(
            'Delete message?',
            'The message becomes a deleted placeholder for both participants.',
          )) {
        if (!_valid) return;
        await (_repo as ChatOperationsRepository).deleteMessage(message.id);
        if (_audio.currentMessageId == message.id) {
          unawaited(_audio.stopPlayback());
        }
        if (mounted && _valid) {
          _list.appendConfirmed(message.asDeleted(), session: _session);
          await _refresh();
        }
      }
    } catch (_) {
      _notice('Unable to change this message. Refresh before retrying.');
    } finally {
      _managing = false;
    }
  }

  void _typed() {
    if (!_canSend) return;
    if (_typingCooldown == null) {
      unawaited(_sendTyping(_text.text.trim().isNotEmpty));
      _typingCooldown = Timer(
        const Duration(seconds: 2),
        () => _typingCooldown = null,
      );
    }
    _typingIdle?.cancel();
    _typingIdle = Timer(
      const Duration(seconds: 3),
      () => unawaited(_sendTyping(false)),
    );
  }

  Future<void> _sendTyping(bool value) async {
    if (!_valid ||
        _repo is! ChatOperationsRepository ||
        _pendingRequest ||
        !(_details ?? widget.conversation).canSend) {
      return;
    }
    try {
      await (_repo as ChatOperationsRepository).typing(
        widget.conversation.id,
        value,
      );
    } catch (_) {}
  }

  Future<void> _attachments() async {
    if (_picking || _uploading || _sendingSelections || !_valid) return;
    _picking = true;
    try {
      final box =
          _attachmentAnchor.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
      final source = await ChatAttachmentMenu.show(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        enabled: _canSend && _repo.capabilities.attachments,
      );
      if (source == null || !mounted || !_valid) return;
      if (_pendingMedia != null || _audio.draft != null) {
        _notice('Finish or discard the current attachment first.');
        return;
      }
      final List<XFile> files;
      if (widget.pickAttachments != null) {
        files = await widget.pickAttachments!(source);
      } else if (source == ImageSource.camera) {
        final picked = await ImagePicker().pickImage(
          source: source,
          imageQuality: 85,
        );
        files = picked == null ? [] : [picked];
      } else {
        files = await ImagePicker().pickMultipleMedia(
          imageQuality: 85,
          limit: 10,
          requestFullMetadata: false,
        );
      }
      if (!mounted || !_valid || files.isEmpty) return;
      final selected = <ChatMediaSelection>[];
      for (final image in files) {
        if (await image.length() > 100 * 1024 * 1024) {
          _notice('Choose media smaller than 100 MB.');
          return;
        }
        final bytes = await image.readAsBytes();
        if (!mounted || !_valid) return;
        final mime = _imageMime(bytes) ?? _videoMime(bytes);
        if (mime == null) {
          _notice('Choose a supported image or MP4, MOV or WebM video.');
          return;
        }
        if (!mime.startsWith('video/') && bytes.length > 20 * 1024 * 1024) {
          _notice('Choose images smaller than 20 MB.');
          return;
        }
        selected.add(
          ChatMediaSelection(
            bytes,
            'chat-media.${mime == 'video/quicktime' ? 'mov' : mime.split('/').last}',
            mime,
            mime.startsWith('video/')
                ? ChatMessageKind.video
                : ChatMessageKind.image,
          ),
        );
      }
      _selections.addAll(selected);
      setState(() => _mediaError = null);
    } catch (_) {
      _notice('Unable to select this media. Please try again.');
    } finally {
      _picking = false;
    }
  }

  String? _imageMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      return 'image/png';
    }
    if (bytes.length >= 6 && String.fromCharCodes(bytes.take(3)) == 'GIF') {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  String? _videoMime(Uint8List bytes) {
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.skip(4).take(4)) == 'ftyp') {
      return String.fromCharCodes(bytes.skip(8).take(4)) == 'qt  '
          ? 'video/quicktime'
          : 'video/mp4';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return 'video/webm';
    }
    return null;
  }

  void _sendVoice() {
    final draft = _audio.draft;
    if (draft == null || _uploading || !_canSend) return;
    _pendingMedia ??= ChatMediaSelection(
      draft.bytes,
      'recording.m4a',
      'audio/mp4',
      ChatMessageKind.audio,
      durationMs: draft.durationMs,
    );
    unawaited(_sendPendingMedia());
  }

  void _removeSelection(ChatMediaSelection selection) {
    if (_uploading || _sendingSelections) return;
    _selections.remove(selection);
    if (identical(selection, _pendingMedia)) {
      _pendingMedia = null;
      _uploader?.close();
      _uploader = null;
    }
    setState(() => _mediaError = null);
  }

  Future<void> _sendSelections() async {
    if (_sendingSelections || _uploading || !_canSend) return;
    setState(() => _sendingSelections = true);
    try {
      while (mounted && _valid && _selections.isNotEmpty) {
        _pendingMedia ??= _selections.first;
        await _sendPendingMedia();
        if (_pendingMedia != null) {
          break; // Failed item and remaining order retained.
        }
      }
    } finally {
      if (mounted) setState(() => _sendingSelections = false);
    }
  }

  void _discardMedia() {
    if (_uploading || _sendingSelections) return;
    _selections.clear();
    setState(() => _pendingMedia = null);
    _audio.discardDraft();
    _mediaError = null;
    _uploader?.close();
    _uploader = null;
  }

  void _confirmMedia(ChatMediaSelection media) {
    setState(() {
      _selections.remove(media);
      _pendingMedia = null;
      _uploadProgress = null;
      _uploading = false;
    });
    _uploader?.close();
    _uploader = null;
    if (media.kind == ChatMessageKind.audio) _audio.discardDraft();
  }

  Future<void> _sendPendingMedia() async {
    final media = _pendingMedia;
    if (media == null ||
        _uploading ||
        !_canSend ||
        _repo is! ChatOperationsRepository) {
      return;
    }
    final previouslyUncertain = media.sendUncertain;
    if (media.kind == ChatMessageKind.image &&
        _composer.state.draft.runes.length > 1000) {
      setState(
        () => _mediaError = 'Image captions can contain up to 1000 characters.',
      );
      return;
    }
    setState(() {
      _uploading = true;
      _mediaError = null;
    });
    if (media.caption == null) {
      media.caption = _composer.state.draft;
      media.replyTo = _composer.state.replyTo?.id;
      // The pending bubble owns the caption/reply now; never restore them.
      if (media.kind == ChatMessageKind.image) _composer.edit('');
      _composer.setReply(null);
    }
    final caption = media.caption!;
    final reply = media.replyTo;
    try {
      _uploader ??=
          widget.mediaUploader ??
          MediaUploadService(
            allowedContentTypes: const {
              'image/jpeg',
              'image/png',
              'image/gif',
              'image/webp',
              'audio/mp4',
              'video/mp4',
              'video/quicktime',
              'video/webm',
            },
          );
      media.readyId ??= await _uploader!.upload(
        filename: media.filename,
        contentType: media.mime,
        bytes: media.bytes,
        isActive: () => mounted && _valid,
        cancelToken: _uploadCancel,
        onStage: (_) {
          if (mounted && _valid) setState(() => _uploadProgress = null);
        },
        onProgress: (sent, total) {
          if (mounted && _valid && total > 0) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );
      if (!mounted || !_valid) return;
      if (media.sendUncertain) {
        // The media may already be attached to a message. Reconcile before a
        // deliberate retry and reuse the same media ID (never upload another).
        await _refresh();
        if (!mounted || !_valid) return;
        final matches = _list.state.items.where(
          (m) => m.mediaId == media.readyId.toString(),
        );
        if (matches.isNotEmpty) {
          _confirmMedia(media);
          return;
        }
        if (!await _confirm(
          'Delivery unknown',
          'History could not confirm this attachment. Sending again may create a duplicate.',
          destructive: false,
        )) {
          return;
        }
        if (!mounted || !_valid) return;
      }
      media.sendUncertain = true;
      final message = await (_repo as ChatOperationsRepository).sendMedia(
        widget.conversation.id,
        kind: media.kind,
        mediaId: media.readyId!,
        durationMs: media.durationMs,
        caption:
            media.kind == ChatMessageKind.image && caption.trim().isNotEmpty
            ? caption
            : null,
        replyToId: reply,
      );
      if (!mounted || !_valid) return;
      _confirmMedia(media);
      await _receivedSentMessage(message);
    } catch (error) {
      if (!previouslyUncertain &&
          (error is ChatPreSendFailure ||
              error is ApiError &&
                  error.statusCode != null &&
                  error.statusCode! >= 400 &&
                  error.statusCode! < 500)) {
        media.sendUncertain = false;
      }
      if (mounted && _valid) {
        setState(
          () => _mediaError = media.sendUncertain
              ? 'Delivery unknown. Tap the attachment to check.'
              : 'Attachment failed. Tap to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}
