import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'city_places_provider.dart';
import 'city_autocomplete_cubit.dart';
import 'city_autocomplete_results.dart';

/// Reuses the Photon selection contract. Opening/typing never mutates a profile.
Future<CitySelection?> pickCurrentCity(BuildContext context) =>
    showModalBottomSheet<CitySelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DarkColors.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => BlocProvider(
        create: (_) => CityAutocompleteCubit(
          provider: context.read<CityPlacesProvider?>(),
        ),
        child: const _Picker(),
      ),
    );

class _Picker extends StatelessWidget {
  const _Picker();
  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<CityAutocompleteCubit, CityAutocompleteState>(
    listener: (context, state) {
      if (state.selected != null) Navigator.pop(context, state.selected);
    },
    builder: (context, state) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            children: [
              const Text(
                'Current City',
                style: TextStyle(
                  color: DarkColors.whiteColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoTheme(
                // iOS handles read CupertinoTheme independently of TextSelectionTheme.
                data: CupertinoTheme.of(context).copyWith(
                  primaryColor: DarkColors.primaryColor,
                  selectionHandleColor: DarkColors.primaryColor,
                ),
                child: TextSelectionTheme(
                  data: TextSelectionThemeData(
                    cursorColor: DarkColors.primaryColor,
                    selectionColor: DarkColors.primaryColor.withValues(
                      alpha: .3,
                    ),
                    selectionHandleColor: DarkColors.primaryColor,
                  ),
                  child: TextField(
                    autofocus: true,
                    maxLength: 120,
                    cursorColor: DarkColors.primaryColor,
                    style: const TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: 16,
                    ),
                    onChanged: context.read<CityAutocompleteCubit>().setText,
                    decoration: InputDecoration(
                      hintText: 'Search for your current city',
                      hintStyle: const TextStyle(color: DarkColors.greyColor),
                      counterStyle: const TextStyle(
                        color: DarkColors.greyColor,
                      ),
                      filled: true,
                      fillColor: DarkColors.darkgreyColor,
                      focusColor: DarkColors.darkgreyColor,
                      hoverColor: DarkColors.darkgreyColor,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              CityAutocompleteResults(
                state: state,
                currentCityStyle: true,
                onSelect: context.read<CityAutocompleteCubit>().select,
                onRetry: context.read<CityAutocompleteCubit>().retry,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
