import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/location/device_location_service.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/places/device_city_reverse_geocoder.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/options_sheet.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/features/buddies/cubit/allow_location_cubit.dart';
import 'package:travibe/features/profile/cubit/current_user_cubit.dart';

const showInBuddiesSuccessMessage = "You're now visible in Buddies.";

/// "Show me in Buddies" sheet, shared by the Buddies visibility card, Settings
/// and the Profile Setup switch. Only a city is ever sent to Travibe.
///
/// Two buttons, like Figma: **Allow Location** and **Not Now**.
/// - With a saved current city, Allow Location never asks for permission; it
///   only PATCHes `show_in_travel_buddy`.
/// - Without one: permission → reverse geocode (device, English) → save city
///   → turn on.
///
/// Returns true once visibility is confirmed by the server.
Future<bool> showShowInBuddiesSheet(
  BuildContext context, {
  CurrentUserCubit? currentUser,
  DeviceLocationService? device,
  CityReverseGeocoder? geocoder,
}) async {
  final user = currentUser ?? context.read<CurrentUserCubit?>();
  if (user == null) return false;
  final places = context.read<CityPlacesProvider?>();
  final toast = TravibeToast.of(context);
  final enabled = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: optionsSheetColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSizes.adaptiveRadius(24)),
      ),
    ),
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: user),
        BlocProvider(
          create: (_) => AllowLocationCubit(
            currentUser: user,
            device: device ?? context.read<DeviceLocationService?>(),
            // Device geocoder first; a provided Photon provider is only
            // its fallback.
            geocoder:
                geocoder ??
                (places is CityReverseGeocoder
                    ? DeviceCityReverseGeocoder(
                        fallback: places as CityReverseGeocoder,
                      )
                    : null),
          ),
        ),
      ],
      child: const ShowInBuddiesSheet(),
    ),
  );
  if (enabled == true) {
    toast.present(const TravibeToastData.success(showInBuddiesSuccessMessage));
  }
  return enabled == true;
}

class ShowInBuddiesSheet extends StatefulWidget {
  const ShowInBuddiesSheet({super.key});

  @override
  State<ShowInBuddiesSheet> createState() => _ShowInBuddiesSheetState();
}

class _ShowInBuddiesSheetState extends State<ShowInBuddiesSheet> {
  /// The mode is frozen while a request runs so saving the city midway does
  /// not swap the buttons under the user's finger.
  String? _city;

  @override
  Widget build(BuildContext context) {
    final location = context.select(
      (CurrentUserCubit user) => user.state.profile?.currentLocation,
    );
    return BlocConsumer<AllowLocationCubit, AllowLocationState>(
      listenWhen: (a, b) => !a.enabled && b.enabled,
      listener: (context, _) => Navigator.of(context).pop(true),
      builder: (context, state) {
        if (!state.busy) _city = location;
        final city = _city;
        final cubit = context.read<AllowLocationCubit>();
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSizes.adaptiveWidth(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: AppSizes.adaptiveHeight(12)),
                  const SheetHandle(),
                  SizedBox(height: AppSizes.adaptiveHeight(24)),
                  Container(
                    width: AppSizes.adaptiveRadius(64),
                    height: AppSizes.adaptiveRadius(64),
                    decoration: const BoxDecoration(
                      color: Color(0x4DE45C10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: DarkColors.primaryColor,
                      size: AppSizes.adaptiveRadius(36),
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(12)),
                  Text(
                    'Show me in Buddies',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.adaptiveFont(18),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(4)),
                  Text(
                    city != null
                        ? "We'll show you in $city"
                        : 'Allow Travibe to use your current location to show you to people nearby.',
                    key: const ValueKey('show-in-buddies-message'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: DarkColors.greyColor,
                      fontSize: AppSizes.adaptiveFont(14),
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(16)),
                  const _CityOnlyNote(),
                  if (state.error != null) ...[
                    SizedBox(height: AppSizes.adaptiveHeight(12)),
                    Text(
                      state.error!,
                      key: const ValueKey('show-in-buddies-error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: DarkColors.dangerColor,
                        fontSize: AppSizes.adaptiveFont(13),
                      ),
                    ),
                  ],
                  SizedBox(height: AppSizes.adaptiveHeight(16)),
                  _PrimaryButton(
                    label: 'Allow Location',
                    busy: state.busy,
                    onPressed: state.busy
                        ? null
                        : (city != null ? cubit.turnOn : cubit.useLocation),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(8)),
                  // Recovery only, after a permanent permission denial.
                  if (state.openSettings) ...[
                    SizedBox(height: AppSizes.adaptiveHeight(8)),
                    _SecondaryButton(
                      label: 'Open Settings',
                      onPressed: cubit.device.openSettings,
                    ),
                    SizedBox(height: AppSizes.adaptiveHeight(8)),
                  ],
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: DarkColors.greyColor,
                      minimumSize: Size(
                        double.infinity,
                        AppSizes.adaptiveHeight(44),
                      ),
                    ),
                    child: Text(
                      'Not Now',
                      style: TextStyle(
                        fontSize: AppSizes.adaptiveFont(16),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(8)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppSizes.adaptiveHeight(48),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: DarkColors.primaryColor,
        disabledBackgroundColor: DarkColors.primaryColor,
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white70,
        elevation: 0,
        shape: ActionButtonStyle.shape,
      ),
      child: busy
          ? const AppActivityIndicator()
          : Text(label, style: ActionButtonStyle.label),
    ),
  );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: AppSizes.adaptiveHeight(48),
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF3B3B3B)),
        shape: ActionButtonStyle.shape,
      ),
      child: Text(label, style: ActionButtonStyle.label),
    ),
  );
}

class _CityOnlyNote extends StatelessWidget {
  const _CityOnlyNote();
  static const _green = Color(0xFF5BD07A);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(
      horizontal: AppSizes.adaptiveWidth(12),
      vertical: AppSizes.adaptiveHeight(8),
    ),
    decoration: BoxDecoration(
      color: const Color(0xFF13241A),
      borderRadius: BorderRadius.circular(AppSizes.adaptiveRadius(12)),
    ),
    child: Row(
      children: [
        Icon(
          Icons.error_outline_rounded,
          color: _green,
          size: AppSizes.adaptiveRadius(20),
        ),
        SizedBox(width: AppSizes.adaptiveWidth(8)),
        Expanded(
          child: Text(
            "We'll show your city, not your exact location.",
            style: TextStyle(
              color: _green,
              fontSize: AppSizes.adaptiveFont(13),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}
