import 'dart:async';

import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';

/// Picks a user to mention. Reuses the app's user search (3+ characters).
Future<PublicUserModel?> showStoryMentionSheet(
  BuildContext context, {
  SearchRepo? repo,
}) => showModalBottomSheet<PublicUserModel>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: DarkColors.backgroundColor,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => StoryMentionSheet(repo: repo ?? SearchRepo()),
);

class StoryMentionSheet extends StatefulWidget {
  const StoryMentionSheet({super.key, required this.repo});
  final SearchRepo repo;

  @override
  State<StoryMentionSheet> createState() => _StoryMentionSheetState();
}

class _StoryMentionSheetState extends State<StoryMentionSheet> {
  static const _debounce = Duration(milliseconds: 350);
  final _controller = TextEditingController();
  Timer? _timer;
  int _generation = 0;
  bool _loading = false;
  String? _error;
  List<PublicUserModel> _results = const [];

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _timer?.cancel();
    final term = value.trim().replaceFirst(RegExp('^@'), '');
    final generation = ++_generation;
    if (term.runes.length < 3) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    _timer = Timer(_debounce, () => _search(term, generation));
  }

  Future<void> _search(String term, int generation) async {
    try {
      final page = await widget.repo.searchUsers(term);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = null;
        // Only users with a username can be mentioned.
        _results = page.users
            .where(
              (user) => (user.username ?? '').isNotEmpty && !user.isBlocked,
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _results = const [];
        _error = error is ApiError
            ? error.message
            : 'Unable to search people. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _controller.text.trim().replaceFirst(RegExp('^@'), '');
    final Widget body;
    if (_loading) {
      body = const Center(
        child: AppActivityIndicator(key: ValueKey('story-mention-loading')),
      );
    } else if (_error != null) {
      body = _message(_error!);
    } else if (term.runes.length < 3) {
      body = _message('Type at least 3 characters to search.');
    } else if (_results.isEmpty) {
      body = _message('No people found.');
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        itemCount: _results.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final user = _results[index];
          return PersonResultTile(
            key: ValueKey('story-mention-user-${user.id}'),
            user: user,
            onFollowTap: null,
            showFollow: false,
            onTap: () => Navigator.pop(context, user),
          );
        },
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            children: [
              const SheetHandle(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Mention someone',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Plus Jakarta Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextField(
                key: const ValueKey('story-mention-search'),
                controller: _controller,
                autofocus: true,
                onChanged: _changed,
                textInputAction: TextInputAction.search,
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search people',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  prefixIcon: const Icon(
                    Icons.alternate_email,
                    color: Colors.white70,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF141414),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                  ),
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white54),
    ),
  );
}
