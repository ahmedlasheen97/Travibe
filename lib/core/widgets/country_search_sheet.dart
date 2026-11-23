import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/core/widgets/options_sheet.dart';

/// Dark searchable country list (nationality pickers). [load] supplies the
/// `/reference/countries` list; codes in [selected] show a check mark.
Future<ReferenceCountry?> showCountrySearchSheet(
  BuildContext context, {
  required Future<List<ReferenceCountry>> Function() load,
  Set<String> selected = const {},
  String title = 'Nationality',
}) => showOptionsSheet<ReferenceCountry>(
  context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      CountrySearchSheet(load: load, selected: selected, title: title),
);

class CountrySearchSheet extends StatefulWidget {
  const CountrySearchSheet({
    super.key,
    required this.load,
    this.selected = const {},
    this.title = 'Nationality',
  });
  final Future<List<ReferenceCountry>> Function() load;
  final Set<String> selected;
  final String title;

  @override
  State<CountrySearchSheet> createState() => _CountrySearchSheetState();
}

class _CountrySearchSheetState extends State<CountrySearchSheet> {
  List<ReferenceCountry>? _countries;
  String? _error;
  String _query = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _countries = null;
      _error = null;
    });
    try {
      final items = await widget.load();
      if (mounted && generation == _generation) {
        setState(() => _countries = items);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = error is ApiError
              ? error.message
              : 'Unable to load countries.',
        );
      }
    }
  }

  bool _matches(ReferenceCountry country) {
    final query = _query.toLowerCase();
    return query.isEmpty ||
        country.name.toLowerCase().contains(query) ||
        country.nameEn.toLowerCase().contains(query) ||
        country.nameAr.contains(_query) ||
        country.code.toLowerCase() == query;
  }

  @override
  Widget build(BuildContext context) {
    final countries = _countries?.where(_matches).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: AppSizes.adaptiveHeight(12)),
            const Center(child: SheetHandle()),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.adaptiveWidth(20),
                AppSizes.adaptiveHeight(16),
                AppSizes.adaptiveWidth(20),
                AppSizes.adaptiveHeight(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: DarkColors.whiteColor,
                      fontSize: AppSizes.adaptiveFont(18),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppSizes.adaptiveHeight(16)),
                  _SearchField(
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? _ErrorRow(message: _error!, onRetry: _load)
                  : countries == null
                  ? const _CountrySkeleton()
                  : countries.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(AppSizes.adaptiveRadius(20)),
                      child: Text(
                        'No countries found.',
                        style: TextStyle(
                          color: DarkColors.greyColor,
                          fontSize: AppSizes.adaptiveFont(14),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      itemCount: countries.length,
                      itemBuilder: (context, index) {
                        final country = countries[index];
                        final selected = widget.selected.contains(country.code);
                        return ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSizes.adaptiveWidth(20),
                          ),
                          title: Text(
                            country.name,
                            style: TextStyle(
                              color: DarkColors.whiteColor,
                              fontSize: AppSizes.adaptiveFont(15),
                            ),
                          ),
                          subtitle: Text(
                            country.code,
                            style: TextStyle(
                              color: DarkColors.greyColor,
                              fontSize: AppSizes.adaptiveFont(12),
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: DarkColors.primaryColor,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, country),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.r28),
      borderSide: BorderSide.none,
    );
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(
        primaryColor: DarkColors.primaryColor,
        selectionHandleColor: DarkColors.primaryColor,
      ),
      child: TextSelectionTheme(
        data: TextSelectionThemeData(
          cursorColor: DarkColors.primaryColor,
          selectionColor: DarkColors.primaryColor.withValues(alpha: .3),
          selectionHandleColor: DarkColors.primaryColor,
        ),
        child: TextField(
          cursorColor: DarkColors.primaryColor,
          style: TextStyle(
            color: DarkColors.whiteColor,
            fontSize: AppSizes.adaptiveFont(16),
          ),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Search country',
            hintStyle: const TextStyle(color: DarkColors.greyColor),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: DarkColors.greyColor,
            ),
            filled: true,
            fillColor: DarkColors.darkgreyColor,
            focusColor: DarkColors.darkgreyColor,
            hoverColor: DarkColors.darkgreyColor,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSizes.adaptiveWidth(20),
              vertical: AppSizes.adaptiveHeight(14),
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border,
          ),
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(AppSizes.adaptiveRadius(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(
            color: DarkColors.greyColor,
            fontSize: AppSizes.adaptiveFont(14),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: DarkColors.primaryColor,
            padding: EdgeInsets.zero,
          ),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _CountrySkeleton extends StatelessWidget {
  const _CountrySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bone(double width, double height) => Container(
      width: AppSizes.adaptiveWidth(width),
      height: AppSizes.adaptiveHeight(height),
      decoration: BoxDecoration(
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return ListView.builder(
      key: const ValueKey('country-skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.adaptiveWidth(20),
          vertical: AppSizes.adaptiveHeight(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bone(140 + (index % 3) * 30, 14),
            SizedBox(height: AppSizes.adaptiveHeight(6)),
            bone(28, 10),
          ],
        ),
      ),
    );
  }
}
