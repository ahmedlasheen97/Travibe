import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// Uses the public, localized countries catalog, not city/place geocoding.
class ProfileCountryPicker extends StatefulWidget {
  const ProfileCountryPicker({
    super.key,
    required this.load,
    required this.locale,
  });
  final Future<List<ReferenceCountry>> Function(String) load;
  final String locale;

  @override
  State<ProfileCountryPicker> createState() => _ProfileCountryPickerState();
}

class _ProfileCountryPickerState extends State<ProfileCountryPicker> {
  late Future<List<ReferenceCountry>> _request = widget.load(widget.locale);
  String _query = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(AppSizes.adaptiveRadius(16)),
                  child: const Text('Current Country'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.adaptiveWidth(16),
                  ),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search country',
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
              ],
            ),
          ),
          FutureBuilder<List<ReferenceCountry>>(
            future: _request,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _request = widget.load(widget.locale);
                    }),
                    child: const Text('Unable to load countries. Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: DarkColors.primaryColor,
                      ),
                    ),
                  ),
                );
              }
              final values = snapshot.data!
                  .where(
                    (e) => [
                      e.name,
                      e.nameEn,
                      e.nameAr,
                      e.code,
                    ].any((name) => name.toLowerCase().contains(_query)),
                  )
                  .toList();
              if (values.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text('No countries found')),
                );
              }
              return SliverList.builder(
                itemCount: values.length,
                itemBuilder: (context, index) {
                  final country = values[index];
                  return ListTile(
                    title: Text(country.name),
                    trailing: Text(country.code),
                    onTap: () => Navigator.pop(context, country),
                  );
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}
