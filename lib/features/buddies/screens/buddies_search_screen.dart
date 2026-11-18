import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/widgets/recent_searches_section.dart';
import '../widgets/buddies_loading_overlay.dart';
import '../widgets/buddies_traveler_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/widgets/user_profile_link.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/city_autocomplete_cubit.dart';
import 'package:travibe/core/places/city_autocomplete_results.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import '../cubit/buddies_search_cubit.dart';
import '../cubit/buddies_filters_cubit.dart';
import '../cubit/buddies_recents_cubit.dart';
import '../data/recent_destination.dart';
import '../widgets/buddies_filter_button.dart';
import '../data/buddies_landing_data.dart';
import '../data/buddies_filters.dart';
import '../data/buddies_repo.dart';
import '../widgets/buddies_traveler_card.dart';
import 'buddies_filters_screen.dart';

class BuddiesSearchScreen extends StatelessWidget {
  const BuddiesSearchScreen({
    super.key,
    this.repo,
    this.catalogRepo,
    this.placesProvider,
    this.onOpenTraveler,
  });
  final BuddiesRepo? repo;

  /// Opens a traveler's profile; defaults to [openUserProfile].
  final ValueChanged<String>? onOpenTraveler;
  final CityPlacesProvider? placesProvider;
  final ProfileSetupRepo? catalogRepo;
  @override
  Widget build(BuildContext context) {
    final source = repo ?? BuddiesRepo();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => BuddiesRecentsCubit(repo: source)..load()),
        BlocProvider(
          create: (context) => BuddiesSearchCubit(
            repo: source,
            filtersStore: context.read<BuddiesFiltersCubit?>(),
            onRecentSaved: context.read<BuddiesRecentsCubit>().saved,
          ),
        ),
        BlocProvider(
          create: (_) => CityAutocompleteCubit(
            provider: placesProvider ?? context.read<CityPlacesProvider?>(),
          ),
        ),
      ],
      child: _SearchView(
        catalogRepo: catalogRepo,
        onOpenTraveler: onOpenTraveler,
      ),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView({this.catalogRepo, this.onOpenTraveler});
  final ProfileSetupRepo? catalogRepo;
  final ValueChanged<String>? onOpenTraveler;
  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _text = TextEditingController();
  bool _openingFilters = false;

  /// A recent destination being resolved back into a city selection.
  String? _pendingRecent;

  void _openRecent(RecentDestination recent, CityAutocompleteCubit cities) {
    FocusScope.of(context).unfocus();
    final label = recent.destination;
    _text.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );
    _pendingRecent = label;
    cities.setText(label);
  }

  /// Selects the suggestion matching [_pendingRecent] once results arrive;
  /// otherwise leaves the suggestions for the user to choose.
  void _resolvePendingRecent(
    CityAutocompleteState city,
    CityAutocompleteCubit cities,
  ) {
    final pending = _pendingRecent;
    if (pending == null || city.debouncing || city.loading) return;
    _pendingRecent = null;
    if (city.text != pending || !city.searched) return;
    final wanted = pending.trim().toLowerCase();
    for (final suggestion in city.suggestions) {
      final label = suggestion.selection?.label ?? suggestion.label;
      if (label.trim().toLowerCase() == wanted) {
        cities.select(suggestion);
        return;
      }
    }
  }

  void _openTraveler(String id) => widget.onOpenTraveler != null
      ? widget.onOpenTraveler!(id)
      : openUserProfile(context, id);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _filters(BuddiesSearchCubit cubit) async {
    if (_openingFilters) return;
    _openingFilters = true;
    FocusScope.of(context).unfocus();
    final session = PreferencesManager().sessionRevision;
    try {
      final filters = await Navigator.of(context).push<BuddiesFilters>(
        MaterialPageRoute(
          builder: (_) => BuddiesFiltersScreen(
            initial: cubit.state.filters,
            catalogRepo: widget.catalogRepo,
          ),
        ),
      );
      if (mounted &&
          !cubit.isClosed &&
          filters != null &&
          session == PreferencesManager().sessionRevision) {
        cubit.apply(filters);
      }
    } finally {
      _openingFilters = false;
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<CityAutocompleteCubit, CityAutocompleteState>(
    listener: (context, city) {
      final search = context.read<BuddiesSearchCubit>();
      _resolvePendingRecent(city, context.read<CityAutocompleteCubit>());
      if (city.selected != null) {
        search.selectCity(city.selected!);
        FocusScope.of(context).unfocus();
      } else {
        search.setCity(city.text);
      }
      if (_text.text != city.text) {
        _text.value = TextEditingValue(
          text: city.text,
          selection: TextSelection.collapsed(offset: city.text.length),
        );
      }
    },
    builder: (context, city) => BlocBuilder<BuddiesSearchCubit, BuddiesSearchState>(
      builder: (context, state) {
        final cubit = context.read<BuddiesSearchCubit>();
        final cities = context.read<CityAutocompleteCubit>();
        final recents = context.watch<BuddiesRecentsCubit>();
        final showRecents =
            city.text.isEmpty &&
            city.selected == null &&
            recents.state.isNotEmpty;
        final blocks = context.watch<BlockCubit?>();
        Widget content(Set<String> blocked) {
          final items = state.items
              .where((item) => !blocked.contains(item.id.toString()))
              .toList();
          return Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0A0A0A),
              surfaceTintColor: Colors.transparent,
              centerTitle: true,
              toolbarHeight: 84,
              leadingWidth: 84,
              leading: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: BackButtonWidget(
                    onTap: () => Navigator.maybePop(context),
                  ),
                ),
              ),
              title: const Text(
                'Search',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  height: 24 / 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            body: SafeArea(
              top: false,
              child: BuddiesLoadingOverlay(
                loading: state.loading && state.refreshing && items.isNotEmpty,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSizes.pw20,
                        AppSizes.ph8,
                        AppSizes.pw20,
                        AppSizes.ph16,
                      ),
                      child: TextField(
                        controller: _text,
                        cursorColor: Colors.white,
                        onChanged: (text) {
                          _pendingRecent = null;
                          cities.setText(text);
                        },
                        onSubmitted: (_) {
                          FocusScope.of(context).unfocus();
                        },
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        textInputAction: TextInputAction.search,
                        maxLength: 120,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(120),
                        ],
                        style: const TextStyle(
                          fontSize: 14,
                          height: 24 / 14,
                          color: Colors.white,
                          letterSpacing: 0,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search by destination',
                          hintStyle: const TextStyle(
                            color: Color(0xFFBDBCBB),
                            fontSize: 14,
                          ),
                          hintFadeDuration: Duration.zero,
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0x801F1F1F),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(14),
                            child: SvgPicture.asset(
                              'assets/images/interactions/search-normal.svg',
                              width: 20,
                              height: 20,
                            ),
                          ),
                          suffixIcon: city.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _pendingRecent = null;
                                    _text.clear();
                                    cities.clear();
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(32),
                            borderSide: const BorderSide(
                              color: Color(0x66595959),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(32),
                            borderSide: const BorderSide(
                              color: Color(0xFFBDBCBB),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            BuddiesFilterButton(
                              count: cubit.state.filters.activeCount,
                              onPressed: () => _filters(cubit),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: RefreshIndicator.noSpinner(
                        onRefresh: cubit.refresh,
                        child: ListView(
                          key: ValueKey(state.query),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          children: [
                            if (showRecents)
                              Padding(
                                padding: EdgeInsets.only(bottom: AppSizes.ph16),
                                child: RecentSearchesSection<RecentDestination>(
                                  items: recents.state,
                                  labelOf: (recent) => recent.destination,
                                  onSelect: (recent) =>
                                      _openRecent(recent, cities),
                                  onRemove: recents.remove,
                                  onClearAll: recents.clear,
                                ),
                              ),
                            if (city.loading ||
                                city.debouncing ||
                                city.resolving ||
                                city.error != null ||
                                city.searched ||
                                city.selected != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: CityAutocompleteResults(
                                  state: city,
                                  onSelect: cities.select,
                                  onRetry: cities.retry,
                                ),
                              ),
                            if (!showRecents &&
                                city.text.trim().runes.length < 2 &&
                                city.selected == null)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Type at least 2 characters and choose a city.',
                                ),
                              ),
                            if (!state.loading &&
                                state.page != null &&
                                state.error == null &&
                                items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No buddies found in this city yet.',
                                ),
                              ),
                            if (state.loading &&
                                items.isEmpty &&
                                (state.page == null || state.refreshing))
                              const BuddiesGridSkeleton(),
                            for (var i = 0; i < items.length; i += 2)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var column = 0;
                                      column < 2;
                                      column++
                                    ) ...[
                                      if (column > 0) const SizedBox(width: 16),
                                      Expanded(
                                        child: i + column >= items.length
                                            ? const SizedBox()
                                            : Builder(
                                                builder: (_) {
                                                  final item =
                                                      items[i + column];
                                                  final location =
                                                      [
                                                            item.city,
                                                            item.countryCode,
                                                          ]
                                                          .whereType<String>()
                                                          .where(
                                                            (value) => value
                                                                .isNotEmpty,
                                                          )
                                                          .join(', ');
                                                  return BuddiesTravelerCard(
                                                    key: ValueKey(item.id),
                                                    onTap: () => _openTraveler(
                                                      item.id.toString(),
                                                    ),
                                                    traveler: BuddiesTraveler(
                                                      id: item.id.toString(),
                                                      name: item.name,
                                                      photoUrl: item.avatarUrl,
                                                      destination:
                                                          location.isEmpty
                                                          ? null
                                                          : location,
                                                      interests: item.interests
                                                          .map(
                                                            (interest) =>
                                                                interest.name,
                                                          )
                                                          .toList(),
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (state.loading &&
                                state.page != null &&
                                !state.refreshing &&
                                items.isNotEmpty)
                              const BuddiesGridSkeleton(rows: 1),
                            if (state.recentError != null)
                              Text(
                                'Results are available, but the recent destination could not be saved.',
                              ),
                            if (state.error != null) ...[
                              Text(state.error!.message),
                              if (state.query != null)
                                TextButton(
                                  onPressed: state.loading
                                      ? null
                                      : () {
                                          if (state.page == null ||
                                              state.refreshing) {
                                            cubit.refresh();
                                          } else {
                                            cubit.loadMore();
                                          }
                                        },
                                  style: TextButton.styleFrom(
                                    textStyle: Theme.of(context)
                                        .textTheme
                                        .labelLarge!
                                        .copyWith(
                                          fontSize: 14,
                                          height: 24 / 14,
                                          letterSpacing: 0,
                                          decoration: TextDecoration.none,
                                        ),
                                  ),
                                  child: const Text('Retry'),
                                ),
                            ] else if (!state.loading &&
                                state.page?.next != null)
                              TextButton(
                                onPressed: cubit.loadMore,
                                child: const Text('Load more'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return blocks == null
            ? content({})
            : BlocBuilder<BlockCubit, BlockState>(
                bloc: blocks,
                builder: (_, state) => content(state.blockedIds),
              );
      },
    ),
  );
}

/// Kept for existing callers; delegates to the shared shimmer grid.
class BuddiesSearchSkeleton extends StatelessWidget {
  const BuddiesSearchSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const BuddiesGridSkeleton();
}
