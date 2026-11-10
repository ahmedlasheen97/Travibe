import 'package:travibe/core/widgets/back_button_widget.dart';
import '../widgets/buddies_loading_overlay.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import '../cubit/buddies_listing_cubit.dart';
import '../data/buddies_filters.dart';
import '../data/buddies_landing_data.dart';
import '../data/buddies_repo.dart';
import '../widgets/buddies_traveler_card.dart';
import 'buddies_filters_screen.dart';

class BuddiesListingScreen extends StatelessWidget {
  const BuddiesListingScreen({
    super.key,
    required this.listing,
    this.repo,
    this.catalogRepo,
  });
  final BuddiesListing listing;
  final BuddiesRepo? repo;
  final ProfileSetupRepo? catalogRepo;
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => BuddiesListingCubit(listing: listing, repo: repo)..refresh(),
    child: _ListingView(listing: listing, catalogRepo: catalogRepo),
  );
}

class _ListingView extends StatelessWidget {
  const _ListingView({required this.listing, this.catalogRepo});
  final BuddiesListing listing;
  final ProfileSetupRepo? catalogRepo;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BuddiesListingCubit, BuddiesListingState>(
    builder: (context, state) {
      final cubit = context.read<BuddiesListingCubit>();
      final block = context.watch<BlockCubit?>();
      Widget body(Set<String> blocked) {
        final items = state.items
            .where((item) => !blocked.contains(item.id.toString()))
            .toList();
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0A0A0A),
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            toolbarHeight: (MediaQuery.textScalerOf(context).scale(24) * 2 + 20)
                .clamp(84, double.infinity),
            leadingWidth: 84,
            leading: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: BackButtonWidget(
                  onTap: () => Navigator.maybePop(context),
                  size: 44,
                  iconSize: 24,
                ),
              ),
            ),
            title: Text(
              listing.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                decoration: TextDecoration.none,
                fontSize: 18,
                height: 24 / 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: BuddiesLoadingOverlay(
              loading:
                  state.loading && (state.page == null || state.refreshing),
              child: RefreshIndicator.noSpinner(
                onRefresh: cubit.refresh,
                child: ListView(
                  key: ValueKey(state.filters),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF2F2E2D),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                fontSize: 18,
                                height: 24 / 18,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                        ),
                        onPressed: () async {
                          final revision = PreferencesManager().sessionRevision;
                          final filters = await Navigator.push<BuddiesFilters>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BuddiesFiltersScreen(
                                initial: state.filters,
                                catalogRepo: catalogRepo,
                              ),
                            ),
                          );
                          if (context.mounted &&
                              !cubit.isClosed &&
                              filters != null &&
                              revision ==
                                  PreferencesManager().sessionRevision) {
                            cubit.apply(filters);
                          }
                        },
                        icon: SvgPicture.asset(
                          'assets/images/interactions/buddies-filter.svg',
                        ),
                        label: const Text('Filters'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (state.page?.hasCurrentCity == false)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No current city is available.'),
                      ),
                    if (!state.loading &&
                        state.error == null &&
                        items.isEmpty &&
                        state.page?.hasCurrentCity != false)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No travelers found.'),
                      ),
                    // Rows grow with their content, preserving chips and large text
                    // without a fixed grid aspect ratio clipping the cards.
                    for (var i = 0; i < items.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var column = 0; column < 2; column++) ...[
                              if (column > 0) const SizedBox(width: 16),
                              Expanded(
                                child: i + column >= items.length
                                    ? const SizedBox()
                                    : BuddiesTravelerCard(
                                        traveler: BuddiesTraveler(
                                          id: items[i + column].id.toString(),
                                          name: items[i + column].name,
                                          photoUrl: items[i + column].avatarUrl,
                                          destination:
                                              listing ==
                                                  BuddiesListing.interests
                                              ? null
                                              : [
                                                      items[i + column].city,
                                                      items[i + column]
                                                          .countryCode,
                                                    ]
                                                    .whereType<String>()
                                                    .where(
                                                      (value) =>
                                                          value.isNotEmpty,
                                                    )
                                                    .join(', ')
                                                    .emptyToNull,
                                          interests: items[i + column].interests
                                              .map((item) => item.name)
                                              .toList(),
                                        ),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (state.error != null) ...[
                      Text(state.error!.message),
                      TextButton(
                        onPressed: state.loading
                            ? null
                            : () {
                                if (state.page == null || state.refreshing) {
                                  cubit.refresh();
                                } else {
                                  cubit.loadMore();
                                }
                              },
                        child: const Text('Retry'),
                      ),
                    ] else if (!state.loading &&
                        state.page?.next != null &&
                        state.page?.hasCurrentCity != false)
                      TextButton(
                        onPressed: cubit.loadMore,
                        child: const Text('Load more'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return block == null
          ? body({})
          : BlocBuilder<BlockCubit, BlockState>(
              bloc: block,
              builder: (_, state) => body(state.blockedIds),
            );
    },
  );
}

extension on String {
  String? get emptyToNull => isEmpty ? null : this;
}
