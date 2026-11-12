import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/location/device_location_service.dart';
import 'package:flutter/foundation.dart';
import '../widgets/buddies_loading_overlay.dart';
import '../widgets/buddies_traveler_skeleton.dart';
import '../cubit/allow_location_cubit.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import '../data/buddies_filters.dart';
import 'buddies_listing_screen.dart';
import 'buddies_search_screen.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/features/block/cubit/block_cubit.dart';
import 'package:travibe/features/profilesetup/screens/profile_setup_screen.dart';
import '../cubit/buddies_cubit.dart';
import '../data/buddies_home_response.dart';
import '../data/buddies_repo.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/navigation/bottom_nav_visibility.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/features/buddies/data/buddies_landing_data.dart';
import 'package:travibe/features/buddies/widgets/buddies_traveler_section.dart';
import 'package:travibe/features/buddies/widgets/buddies_visibility_invitation.dart';

class BuddiesScreen extends StatelessWidget {
  const BuddiesScreen({super.key, this.repo, this.refreshSignal});
  final ValueListenable<int>? refreshSignal;
  final BuddiesRepo? repo;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        BuddiesCubit(repo: repo, currentUser: context.read<CurrentUserCubit?>())
          ..load(),
    child: _BuddiesRefreshListener(
      signal: refreshSignal,
      child: BlocBuilder<BuddiesCubit, BuddiesState>(
        builder: (context, state) {
          final block = context.watch<BlockCubit?>();
          void openDiscovery(Widget screen) {
            if (block != null) {
              screen = BlocProvider<BlockCubit>.value(
                value: block,
                child: screen,
              );
            }
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => screen));
          }

          Widget content(Set<String> blocked) {
            List<BuddiesTraveler> travelers(List<BuddyResource> items) => items
                .where((item) => !blocked.contains(item.id.toString()))
                .map(
                  (item) => BuddiesTraveler(
                    id: item.id.toString(),
                    name: item.name,
                    photoUrl: item.avatarUrl,
                    destination:
                        [
                          if (item.city != null) item.city!,
                          if (item.countryCode != null) item.countryCode!,
                        ].join(', ').isEmpty
                        ? null
                        : [
                            if (item.city != null) item.city!,
                            if (item.countryCode != null) item.countryCode!,
                          ].join(', '),
                    interests: item.interests
                        .map((interest) => interest.name)
                        .toList(),
                  ),
                )
                .toList();
            return BuddiesLandingView(
              variant: BuddiesLandingVariant.nearbyTravelers,
              meta: state.home?.meta,
              nearbyTravelers: travelers(state.home?.inYourCity ?? []),
              sharedInterestTravelers: travelers(
                state.home?.withSameInterests ?? [],
              ),
              isLoading: state.loading && state.home == null,
              refreshing: state.loading && state.home != null,
              errorMessage: state.error?.message,
              onRetry: state.loading
                  ? null
                  : () => context.read<BuddiesCubit>().load(),
              onRefresh: context.read<BuddiesCubit>().load,
              onSeeCity: () => openDiscovery(
                BuddiesListingScreen(listing: BuddiesListing.city, repo: repo),
              ),
              onSeeInterests: () => openDiscovery(
                BuddiesListingScreen(
                  listing: BuddiesListing.interests,
                  repo: repo,
                ),
              ),
              onSearch: () => openDiscovery(
                BuddiesSearchScreen(
                  repo: repo,
                  placesProvider: context.read<CityPlacesProvider?>(),
                ),
              ),
            );
          }

          return block == null
              ? content({})
              : BlocBuilder<BlockCubit, BlockState>(
                  bloc: block,
                  builder: (_, state) => content(state.blockedIds),
                );
        },
      ),
    ),
  );
}

class BuddiesLandingView extends StatelessWidget {
  const BuddiesLandingView({
    super.key,
    this.variant = BuddiesLandingVariant.visibilityInvitation,
    this.nearbyTravelers = const [],
    this.sharedInterestTravelers = const [],
    this.isLoading = false,
    this.refreshing = false,
    this.meta,
    this.errorMessage,
    this.onRetry,
    this.onRefresh,
    this.onSeeCity,
    this.onSeeInterests,
    this.onSearch,
  });
  final BuddiesLandingVariant variant;
  final List<BuddiesTraveler> nearbyTravelers;
  final List<BuddiesTraveler> sharedInterestTravelers;
  final bool isLoading;
  final bool refreshing;
  final BuddiesHomeMeta? meta;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onSeeCity, onSeeInterests;
  final VoidCallback? onSearch;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final invitation = meta != null
        ? !meta!.showInTravelBuddy
        : variant == BuddiesLandingVariant.visibilityInvitation;
    final navInset = BottomNavScope.bottomInsetOf(context);
    final empty = nearbyTravelers.isEmpty && sharedInterestTravelers.isEmpty;
    // First load and refresh-from-empty show card skeletons; a refresh over
    // existing cards keeps them and shows the small floating loader.
    final skeleton = isLoading || refreshing && empty;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        // Inside Root the content runs under the hideable bottom bar.
        bottom: navInset == 0,
        child: BuddiesLoadingOverlay(
          loading: refreshing && !skeleton,
          child: RefreshIndicator.noSpinner(
            onRefresh: onRefresh ?? () async {},
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: 20, bottom: 36 + navInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 286,
                          child: Text.rich(
                            TextSpan(
                              text: 'Find people for your next ',
                              children: [
                                TextSpan(
                                  text: 'adventure',
                                  style: TextStyle(
                                    letterSpacing: 0,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              letterSpacing: 0,
                              color: Color(0xFF989693),
                              fontSize: 28,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 27),
                        _DestinationSearch(onTap: onSearch),
                        if (meta?.profileCompleted == false) ...[
                          const SizedBox(height: 20),
                          const Text(
                            'Complete your profile',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Text(
                            'Complete your profile to help travelers get to know you.',
                          ),
                          FilledButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ProfileSetupScreen(),
                                ),
                              );
                              if (context.mounted) onRefresh?.call();
                            },
                            child: const Text('Complete Profile'),
                          ),
                        ],
                        if (meta != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            meta!.hasCurrentCity
                                ? (meta!.currentCity == null
                                      ? 'Current city available'
                                      : [
                                          meta!.currentCity!.city,
                                          if (meta!.currentCity!.countryCode !=
                                              null)
                                            meta!.currentCity!.countryCode!,
                                        ].join(', '))
                                : 'No current city is available.',
                          ),
                        ],
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(errorMessage!),
                          if (onRetry != null)
                            TextButton(
                              onPressed: onRetry,
                              child: const Text('Retry'),
                            ),
                        ],
                        if (invitation) ...[
                          const SizedBox(height: 28),
                          const BuddiesVisibilityInvitation(),
                        ],
                      ],
                    ),
                  ),
                  if (skeleton) ...[
                    SizedBox(height: AppSizes.adaptiveHeight(28)),
                    const BuddiesSectionSkeleton(),
                    SizedBox(height: AppSizes.adaptiveHeight(24)),
                    const BuddiesSectionSkeleton(),
                  ] else ...[
                    if (errorMessage == null && empty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          meta == null
                              ? 'Traveler discovery is not available yet.'
                              : 'No travelers found yet.',
                          style: const TextStyle(color: Color(0xFFBDBCBB)),
                        ),
                      ),
                    if (nearbyTravelers.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      BuddiesTravelerSection(
                        title: 'In Your City',
                        onSeeAll: onSeeCity,
                        travelers: nearbyTravelers,
                      ),
                    ],
                    if (sharedInterestTravelers.isNotEmpty) ...[
                      SizedBox(
                        height: invitation || nearbyTravelers.isEmpty ? 28 : 24,
                      ),
                      BuddiesTravelerSection(
                        title: 'With Same Interests',
                        onSeeAll: onSeeInterests,
                        travelers: sharedInterestTravelers,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationSearch extends StatelessWidget {
  const _DestinationSearch({this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: onTap == null
        ? 'Destination search is unavailable until API integration is verified'
        : 'Choose Destination',
    child: Semantics(
      label: 'Choose Destination',
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0x801F1F1F),
            border: Border.all(color: const Color(0x66595959)),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                'assets/images/interactions/search-normal.svg',
                width: 20,
                height: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Choose Destination',
                  style: TextStyle(
                    letterSpacing: 0,
                    color: Color(0xFFBDBCBB),
                    fontSize: 14,
                    height: 24 / 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BuddiesRefreshListener extends StatefulWidget {
  const _BuddiesRefreshListener({required this.signal, required this.child});
  final ValueListenable<int>? signal;
  final Widget child;
  @override
  State<_BuddiesRefreshListener> createState() =>
      _BuddiesRefreshListenerState();
}

class _BuddiesRefreshListenerState extends State<_BuddiesRefreshListener> {
  void _refresh() {
    if (mounted) context.read<BuddiesCubit>().load();
  }

  @override
  void initState() {
    super.initState();
    widget.signal?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_BuddiesRefreshListener old) {
    super.didUpdateWidget(old);
    if (old.signal != widget.signal) {
      old.signal?.removeListener(_refresh);
      widget.signal?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.signal?.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<CurrentUserCubit?>();
    final places = context.read<CityPlacesProvider?>();
    return user == null
        ? widget.child
        : BlocProvider(
            create: (_) => AllowLocationCubit(
              currentUser: user,
              device: context.read<DeviceLocationService?>(),
              geocoder: places is CityReverseGeocoder
                  ? places as CityReverseGeocoder
                  : null,
            ),
            child: widget.child,
          );
  }
}
