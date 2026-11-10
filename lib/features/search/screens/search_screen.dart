import 'package:travibe/features/profile/screens/profile_screen.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/error_retry_view.dart';
import 'package:travibe/features/home/widgets/suggested_users_section.dart';
import 'package:travibe/features/search/cubit/search_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_cubit.dart';
import 'package:travibe/features/follow/cubit/follow_users_cubit.dart';
import 'package:travibe/features/follow/data/follow_repo.dart';
import 'package:travibe/features/follow/widgets/follow_action_builder.dart';
import 'package:travibe/features/search/data/search_repo.dart';
import 'package:travibe/features/search/widgets/person_result_tile.dart';
import 'package:travibe/features/search/widgets/recent_searches_section.dart';
import 'package:travibe/features/search/widgets/search_field.dart';
import 'package:travibe/features/search/widgets/search_tabs.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key, this.repo});
  final SearchRepo? repo;

  @override
  Widget build(BuildContext context) {
    final source = repo ?? SearchRepo();
    return BlocProvider<SearchCubit>(
      create: (context) => SearchCubit(repo: source)..loadRecents(),
      child: _SearchView(repo: source),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView({required this.repo});
  final SearchRepo repo;

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  late final FollowUsersCubit _suggestions;
  late Future<String> _viewerId;

  @override
  void initState() {
    super.initState();
    _viewerId = widget.repo.getCurrentUserId();
    _suggestions = FollowUsersCubit(
      type: FollowListType.suggested,
      repo: context.read<FollowCubit>().repo,
    )..load();
  }

  @override
  void dispose() {
    _suggestions.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<BlockCubit, BlockState>(
    listenWhen: (previous, current) =>
        previous.unblockRevision != current.unblockRevision,
    listener: (context, _) {
      final search = context.read<SearchCubit>();
      if (search.state.canSearch) search.retry();
    },
    child: BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        final cubit = context.read<SearchCubit>();

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            leading: const BackButtonWidget(),
            title: const Text(
              'Search',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SearchField(
                    controller: cubit.searchController,
                    onChanged: cubit.onQueryChanged,
                    onSubmitted: (_) {
                      FocusScope.of(context).unfocus();
                      cubit.submit();
                    },
                    onClear: cubit.clearQuery,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: state.hasInput
                      ? _buildResults(context, state, cubit)
                      : _buildIdle(state, cubit),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  // ---------------- nothing typed: recents + suggestions ----------------

  Widget _buildIdle(SearchState state, SearchCubit cubit) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        if (state.recentSearches.isNotEmpty) ...[
          RecentSearchesSection(
            searches: state.recentSearches,
            onSelect: cubit.selectRecent,
            onRemove: cubit.removeRecent,
            onClearAll: cubit.clearRecents,
          ),
          const SizedBox(height: 24),
        ],
        FutureBuilder<String>(
          future: _viewerId,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return ErrorRetryView(
                message: 'Unable to load your account. Please try again.',
                onRetry: () => setState(() {
                  _viewerId = widget.repo.getCurrentUserId();
                }),
              );
            }
            return SuggestedUsersSection(
              compact: true,
              currentUserId: snapshot.data,
              cubit: _suggestions,
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ---------------- typing: tabs + results ----------------

  Widget _buildResults(
    BuildContext context,
    SearchState state,
    SearchCubit cubit,
  ) {
    return Column(
      children: [
        SearchTabs(selected: state.tab, onSelected: cubit.setTab),
        const SizedBox(height: 8),
        Expanded(
          child: state.tab == SearchTab.people
              ? _buildPeople(state, cubit)
              : _message('Post search is coming soon.\nTry the People tab.'),
        ),
      ],
    );
  }

  Widget _buildPeople(SearchState state, SearchCubit cubit) {
    if (state.isTooShort) {
      return _message('Type at least 3 characters to search');
    }
    if (state.isTooLong) return _message('Use no more than 100 characters');

    switch (state.status) {
      case SearchStatus.failure:
        return ErrorRetryView(
          message: state.errorMessage,
          onRetry: cubit.retry,
        );

      case SearchStatus.loaded:
        if (state.people.isEmpty) {
          return _message('No people found for “${state.searchTerm}”');
        }
        return BlocBuilder<BlockCubit, BlockState>(
          builder: (context, block) {
            final people = state.people
                .where(
                  (user) => !block.isBlocked(user.id, fallback: user.isBlocked),
                )
                .toList();
            if (people.isEmpty) {
              return _message('No people found for “${state.searchTerm}”');
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 300) {
                  cubit.loadMorePeople();
                }
                return false;
              },
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount:
                    people.length +
                    (state.isLoadingMore || state.paginationError.isNotEmpty
                        ? 1
                        : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index >= people.length) {
                    if (state.paginationError.isNotEmpty) {
                      return ErrorRetryView(
                        message: state.paginationError,
                        onRetry: () => cubit.loadMorePeople(retry: true),
                      );
                    }
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final user = people[index];
                  return FollowActionBuilder(
                    key: ValueKey(user.id),
                    userId: user.id,
                    initialFollowing: user.isFollowing,
                    builder: (context, following, pending, onToggle) =>
                        PersonResultTile(
                          user: user.copyWith(isFollowing: following),
                          followsYou:
                              context
                                  .read<FollowCubit>()
                                  .state
                                  .followsYou[user.id] ??
                              user.followsYou,
                          onTap: int.tryParse(user.id) == null
                              ? null
                              : () => ProfileScreen.open(
                                  context,
                                  userId: int.parse(user.id),
                                ),
                          isFollowingPending: pending,
                          onFollowTap: onToggle,
                        ),
                  );
                },
              ),
            );
          },
        );

      case SearchStatus.idle:
      case SearchStatus.loading:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
