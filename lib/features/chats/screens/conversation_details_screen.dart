import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import '../cubit/chat_cubit.dart';
import '../data/chat_models.dart';
import '../widgets/chat_loading.dart';
import '../widgets/chat_options.dart';
import 'chat_image_viewer.dart';

List<ChatMessage> sharedChatMedia(Iterable<ChatMessage> messages) => messages
    .where(
      (m) =>
          !m.isDeleted &&
          (m.kind == ChatMessageKind.image ||
              m.kind == ChatMessageKind.video) &&
          m.mediaUrl?.scheme == 'https' &&
          m.mediaUrl!.host.isNotEmpty &&
          m.mediaUrl!.userInfo.isEmpty,
    )
    .toList(growable: false);

class ConversationDetailsScreen extends StatefulWidget {
  const ConversationDetailsScreen({
    super.key,
    required this.conversation,
    required this.messages,
    this.onRefresh,
    this.onMute,
    this.onAction,
  });
  final ChatConversation conversation;

  /// Borrowed from the open conversation; this screen never closes its owner.
  final ChatListCubit<ChatMessage> messages;
  final Future<void> Function()? onRefresh, onMute;
  final Future<void> Function(ChatOption)? onAction;
  @override
  State<ConversationDetailsScreen> createState() =>
      _ConversationDetailsScreenState();
}

class _ConversationDetailsScreenState extends State<ConversationDetailsScreen> {
  final _prefs = PreferencesManager();
  late final int _session;
  bool _acting = false;
  @override
  void initState() {
    super.initState();
    _session = _prefs.sessionRevision;
    _prefs.addListener(_changed);
  }

  bool get _active => _prefs.hasSession && _session == _prefs.sessionRevision;
  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _action(ChatOption action) async {
    if (_acting || !_active) return;
    setState(() => _acting = true);
    try {
      await (widget.onAction?.call(action) ??
          chatUserAction(context, widget.conversation, action));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.conversation.participant;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: const BackButtonWidget(),
        title: const Text('Conversation details'),
        centerTitle: true,
        actions: [
          if (widget.onMute != null || widget.onRefresh != null)
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (!_active || _acting) return;
                setState(() => _acting = true);
                try {
                  await (action == 'mute'
                      ? widget.onMute?.call()
                      : widget.onRefresh?.call());
                } finally {
                  if (mounted) setState(() => _acting = false);
                }
              },
              itemBuilder: (_) => [
                if (widget.onMute != null)
                  PopupMenuItem(
                    value: 'mute',
                    child: Text(
                      widget.conversation.isMuted == true ? 'Unmute' : 'Mute',
                    ),
                  ),
                if (widget.onRefresh != null)
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Text('Refresh messages'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !_active
            ? const Center(child: Text('Sign in again to view shared media.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    HomeUserAvatar(url: user.avatarUrl, size: 96),
                    const SizedBox(height: 16),
                    Text(
                      user.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (user.username?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '@${user.username!.replaceFirst(RegExp(r"^@"), "")}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 24,
                      runSpacing: 16,
                      children: [
                        for (final entry in [
                          (
                            ChatOption.profile,
                            'profilepersonicon.svg',
                            'User Profile',
                          ),
                          (ChatOption.report, 'flag.svg', 'Report'),
                          (ChatOption.block, 'user-remove 2.svg', 'Block User'),
                        ])
                          SizedBox(
                            width: 80,
                            child: Column(
                              children: [
                                IconButton.filled(
                                  tooltip: entry.$3,
                                  onPressed: _acting
                                      ? null
                                      : () => _action(entry.$1),
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFF232323),
                                    minimumSize: const Size.square(48),
                                  ),
                                  icon: SvgPicture.asset(
                                    'assets/images/icons/${entry.$2}',
                                    width: 24,
                                    height: 24,
                                    colorFilter: ColorFilter.mode(
                                      entry.$1 == ChatOption.block
                                          ? Colors.redAccent
                                          : Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  entry.$3,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'Media',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    BlocBuilder<
                      ChatListCubit<ChatMessage>,
                      ChatListState<ChatMessage>
                    >(
                      bloc: widget.messages,
                      builder: (context, state) {
                        final media = sharedChatMedia(state.items);
                        if ((state.loading || state.session == 0) &&
                            state.items.isEmpty &&
                            state.error == null) {
                          return const ChatMediaSkeleton();
                        }
                        return Column(
                          children: [
                            if (media.isEmpty &&
                                state.error == null &&
                                !state.loading)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No shared media in loaded history.',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: media.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemBuilder: (context, index) => InkWell(
                                key: ValueKey(
                                  'shared-media-${media[index].id}',
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ChatImageViewer(
                                      url: media[index].mediaUrl!,
                                      media: media,
                                      initialIndex: index,
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(
                                        color: const Color(0xFF232323),
                                        child:
                                            media[index].kind ==
                                                    ChatMessageKind.video &&
                                                media[index].thumbnailUrl ==
                                                    null
                                            ? const SizedBox()
                                            : Image.network(
                                                (media[index].thumbnailUrl ??
                                                        media[index].mediaUrl!)
                                                    .toString(),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, _, _) =>
                                                    const Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color: Colors.white54,
                                                    ),
                                              ),
                                      ),
                                      if (media[index].kind ==
                                          ChatMessageKind.video)
                                        const Center(
                                          child: Icon(
                                            Icons.play_circle_fill,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (state.error != null)
                              ErrorRetryView(
                                message: state.error!,
                                onRetry: () => widget.messages.load(
                                  more: state.continuation != null,
                                ),
                              ),
                            if (state.loading)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: CupertinoActivityIndicator(),
                              )
                            else if (state.continuation != null)
                              TextButton(
                                onPressed: () =>
                                    widget.messages.load(more: true),
                                child: const Text('Load older media'),
                              ),
                            if (state.continuation != null)
                              const Text(
                                'Showing media from loaded history.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
