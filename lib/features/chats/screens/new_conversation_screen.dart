import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/home/widgets/home_user_avatar.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import '../cubit/chat_discovery_cubit.dart';
import '../data/chat_repository.dart';
import 'chat_navigation.dart';
import 'conversation_screen.dart';

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({super.key, this.repository, this.search});
  final ChatRepository? repository;
  final SearchRepo? search;
  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  late final _repo = widget.repository ?? LaravelChatRepository();
  late final ChatDiscoveryCubit _discovery;
  final _preferences = PreferencesManager();
  late final _session = _preferences.sessionRevision;
  final _text = TextEditingController();
  StreamSubscription<BlockState>? _blocks;
  bool _creating = false;
  String? _error;
  bool get _valid =>
      _session == _preferences.sessionRevision && _preferences.hasSession;
  @override
  void initState() {
    super.initState();
    _discovery = ChatDiscoveryCubit(
      repo: widget.search,
      currentUserId: context.read<CurrentUserCubit?>()?.state.profile?.id,
    );
    final blocks = context.read<BlockCubit?>();
    _discovery.setBlocked(blocks?.state.blockedIds ?? {});
    _blocks = blocks?.stream.listen(
      (state) => _discovery.setBlocked(state.blockedIds),
    );
    _preferences.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    _repo.cancel();
    _text.clear();
    if (mounted) {
      setState(() {
        _error = null;
        _creating = false;
      });
    }
  }

  Future<void> _select(PublicUserModel user) async {
    final blocks = context.read<BlockCubit?>();
    if (_creating ||
        !_valid ||
        user.isBlocked ||
        blocks?.state.isBlocked(user.id) == true ||
        blocks?.state.pending.contains(user.id) == true ||
        !_repo.capabilities.create) {
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final conversation = await _repo.create(user.id);
      if (mounted && _valid) {
        final screen = chatRouteScope(
          context,
          ConversationScreen(
            conversation: conversation,
            repository: widget.repository,
          ),
        );
        await Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
      }
    } catch (error) {
      if (mounted && _valid) {
        setState(
          () => _error = error is ApiError
              ? error.message
              : 'Unable to start conversation. Please retry.',
        );
      }
    } finally {
      if (mounted && _valid) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_sessionChanged);
    _blocks?.cancel();
    _discovery.close();
    _repo.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: DarkColors.backgroundColor,
    body: SafeArea(
      child: Padding(
        padding: EdgeInsets.all(AppSizes.w20),
        child: Column(
          children: [
            Row(
              children: [
                const BackButtonWidget(),
                const Expanded(
                  child: Text(
                    'New conversation',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
            SizedBox(height: AppSizes.h20),
            TextField(
              controller: _text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: Colors.white,
              enabled: _valid && !_creating,
              onChanged: (value) {
                setState(() => _error = null);
                _discovery.query(value);
              },
              decoration: InputDecoration(
                hintText: 'Search people (3+ characters)',
                hintFadeDuration: Duration.zero,
                filled: true,
                fillColor: const Color(0xFF141414),
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SvgPicture.asset(
                    'assets/images/interactions/search-normal.svg',
                    width: 20,
                    height: 20,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
              ),
            ),
            SizedBox(height: AppSizes.h16),
            if (!_valid) const Text('Sign in again to find people.'),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.white70)),
            if (_creating)
              const LinearProgressIndicator(color: DarkColors.primaryColor),
            Expanded(
              child: BlocBuilder<ChatDiscoveryCubit, ChatDiscoveryState>(
                bloc: _discovery,
                builder: (context, state) {
                  if (!_valid) return const SizedBox.shrink();
                  if (state.status == ChatDiscoveryStatus.loading) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  if (state.status == ChatDiscoveryStatus.idle) {
                    return const Center(
                      child: Text('Enter 3–100 characters to find people.'),
                    );
                  }
                  return ListView(
                    children: [
                      if (state.error != null) ...[
                        Text(state.error!.message),
                        TextButton(
                          onPressed: _discovery.retry,
                          child: const Text('Retry'),
                        ),
                      ],
                      if (state.status == ChatDiscoveryStatus.loaded &&
                          state.users.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            state.filteredCount > 0
                                ? 'No available people match. Your account and blocked users are hidden.'
                                : 'No people found. Try another name or username.',
                          ),
                        ),
                      for (final user in state.users)
                        ListTile(
                          key: ValueKey('discover-${user.id}'),
                          leading: IconButton(
                            tooltip: 'View ${user.name} profile',
                            padding: EdgeInsets.zero,
                            onPressed: _creating
                                ? null
                                : () {
                                    final id = int.tryParse(user.id);
                                    if (id != null) {
                                      ProfileScreen.open(context, userId: id);
                                    }
                                  },
                            icon: HomeUserAvatar(url: user.avatarUrl, size: 44),
                          ),
                          title: Text(
                            user.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: user.handle.isEmpty
                              ? null
                              : Text(user.handle),
                          enabled: !_creating && _repo.capabilities.create,
                          onTap: () => _select(user),
                        ),
                      if (state.loadingMore)
                        const Center(child: CupertinoActivityIndicator()),
                      if (state.hasMore && !state.loadingMore)
                        TextButton(
                          onPressed: _discovery.more,
                          child: const Text('Load more'),
                        ),
                    ],
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
