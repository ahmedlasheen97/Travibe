import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:flutter/material.dart';
import 'city_autocomplete_cubit.dart';
import 'city_places_provider.dart';

/// Compact inline panel inside the caller's scroll view (also works above a keyboard).
class CityAutocompleteResults extends StatelessWidget {
  const CityAutocompleteResults({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onRetry,
    this.currentCityStyle = false,
  });
  final CityAutocompleteState state;
  final ValueChanged<CitySuggestion> onSelect;
  final VoidCallback onRetry;

  /// Profile-only presentation; destination search keeps its established styling.
  final bool currentCityStyle;
  @override
  Widget build(BuildContext context) {
    if (currentCityStyle &&
        !state.loading &&
        !state.debouncing &&
        !state.resolving &&
        !state.searched &&
        state.error == null &&
        state.suggestions.isEmpty &&
        state.selected == null) {
      return const SizedBox.shrink();
    }
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: currentCityStyle ? DarkColors.whiteColor : Colors.white,
      fontSize: 14,
      decoration: TextDecoration.none,
    );
    return Material(
      color: currentCityStyle
          ? DarkColors.darkgreyColor
          : const Color(0xFF171717),
      shape: RoundedRectangleBorder(
        side: currentCityStyle
            ? BorderSide.none
            : const BorderSide(color: Color(0x66595959)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact attribution stays visible above the scrollable suggestions.
            if (state.suggestions.isNotEmpty || state.selected != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(
                      color: currentCityStyle
                          ? DarkColors.greyColor
                          : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.normal,
                      letterSpacing: 0,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            if (state.selected != null)
              Text(state.selected!.label, style: style),
            if (state.loading || state.debouncing || state.resolving)
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: currentCityStyle
                        ? const AppActivityIndicator(radius: 9)
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.resolving ? 'Confirming city…' : 'Finding cities…',
                      style: style,
                    ),
                  ),
                ],
              ),
            if (state.error != null) ...[
              Text(state.error!, style: style),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onRetry,
                  style: currentCityStyle
                      ? TextButton.styleFrom(
                          foregroundColor: DarkColors.primaryColor,
                        )
                      : null,
                  child: const Text('Retry cities'),
                ),
              ),
            ],
            if (state.searched && state.suggestions.isEmpty)
              Text('No cities found. Try another name.', style: style),
            for (final suggestion in state.suggestions)
              ListTile(
                key: ValueKey(suggestion.id),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.location_city_outlined,
                  color: currentCityStyle
                      ? DarkColors.greyColor
                      : Colors.white70,
                ),
                focusColor: currentCityStyle
                    ? DarkColors.primaryColor.withValues(alpha: .12)
                    : null,
                hoverColor: currentCityStyle
                    ? DarkColors.primaryColor.withValues(alpha: .08)
                    : null,
                title: Text(
                  currentCityStyle
                      ? suggestion.selection?.cityName ?? suggestion.label
                      : suggestion.label,
                  style: style,
                ),
                subtitle: currentCityStyle && suggestion.selection != null
                    ? Text(
                        _region(suggestion),
                        style: style.copyWith(color: DarkColors.greyColor),
                      )
                    : null,
                onTap: () => onSelect(suggestion),
              ),
          ],
        ),
      ),
    );
  }

  String _region(CitySuggestion suggestion) {
    final city = suggestion.selection!;
    final prefix = '${city.cityName},';
    // Display-only removal of a verified city prefix; no code/name inference.
    return suggestion.label.startsWith(prefix)
        ? suggestion.label.substring(prefix.length).trim()
        : city.countryName;
  }
}
