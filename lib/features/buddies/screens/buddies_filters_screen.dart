import 'package:travibe/core/widgets/back_button_widget.dart';
import '../widgets/buddies_loading_overlay.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import '../data/buddies_filters.dart';

class BuddiesFiltersScreen extends StatefulWidget {
  const BuddiesFiltersScreen({
    super.key,
    required this.initial,
    this.catalogRepo,
  });
  final BuddiesFilters initial;
  final ProfileSetupRepo? catalogRepo;
  @override
  State<BuddiesFiltersScreen> createState() => _BuddiesFiltersScreenState();
}

class _BuddiesFiltersScreenState extends State<BuddiesFiltersScreen> {
  late final ProfileSetupRepo _repo = widget.catalogRepo ?? ProfileSetupRepo();
  final _preferences = PreferencesManager();
  bool _invalidSession = false;
  List<ReferenceCountry> _countries = [];
  String? _countriesError;
  bool _countriesLoading = false;
  int _countryGeneration = 0;
  late final int _session = _preferences.sessionRevision;
  late final Set<String> _gender = {...widget.initial.gender};
  late final Set<String> _nationality = {...widget.initial.nationality};
  late final Map<ReferenceKind, Set<String>> _selected = {
    ReferenceKind.languages: {...widget.initial.languages},
    ReferenceKind.interests: {...widget.initial.interests},
    ReferenceKind.travelStyles: {...widget.initial.travelStyles},
  };
  final Map<ReferenceKind, List<ReferenceItem>> _catalogs = {};
  final Set<ReferenceKind> _loading = {};
  final Map<ReferenceKind, String> _failed = {};
  final Set<ReferenceKind> _expanded = {...ReferenceKind.values};

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_sessionChanged);
    _preferences.language.addListener(_loadCountries);
    _loadCountries();
    for (final kind in ReferenceKind.values) {
      _load(kind);
    }
  }

  void _sessionChanged() {
    if (!mounted || _session == _preferences.sessionRevision) return;
    setState(() => _invalidSession = true);
    _gender.clear();
    _nationality.clear();
    for (final values in _selected.values) {
      values.clear();
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _loadCountries() async {
    final generation = ++_countryGeneration;
    setState(() {
      _countriesLoading = true;
      _countriesError = null;
      _countries = [];
    });
    try {
      final items = await _repo.loadCountries(_preferences.language.value);
      if (mounted && generation == _countryGeneration) {
        setState(() => _countries = items);
      }
    } catch (error) {
      if (mounted && generation == _countryGeneration) {
        setState(
          () => _countriesError = error is ApiError
              ? error.message
              : 'Unable to load countries.',
        );
      }
    } finally {
      if (mounted && generation == _countryGeneration) {
        setState(() => _countriesLoading = false);
      }
    }
  }

  Future<void> _pickNationality() async {
    var text = '';
    final country = await showModalBottomSheet<ReferenceCountry>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search country',
                    ),
                    onChanged: (value) =>
                        setSheetState(() => text = value.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final country in _countries.where(
                        (item) =>
                            item.name.toLowerCase().contains(text) ||
                            item.nameEn.toLowerCase().contains(text) ||
                            item.code.toLowerCase().contains(text),
                      ))
                        ListTile(
                          title: Text(country.name),
                          subtitle: Text(country.code),
                          onTap: () => Navigator.pop(context, country),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted &&
        _session == _preferences.sessionRevision &&
        country != null) {
      setState(() => _nationality.add(country.code));
    }
  }

  Future<void> _load(ReferenceKind kind) async {
    if (_loading.contains(kind)) return;
    setState(() {
      _loading.add(kind);
      _failed.remove(kind);
    });
    try {
      final items = await _repo.loadCatalog(kind);
      if (!mounted || _session != _preferences.sessionRevision) return;
      setState(() {
        _catalogs[kind] = items
            .where((item) => item.status == null || item.status == 'active')
            .toList();
      });
    } catch (error) {
      if (mounted && _session == _preferences.sessionRevision) {
        setState(
          () => _failed[kind] = error is ApiError
              ? error.message
              : 'Unable to load ${kind.path} options.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading.remove(kind));
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_sessionChanged);
    _preferences.language.removeListener(_loadCountries);
    super.dispose();
  }

  Widget _catalog(ReferenceKind kind, String title) {
    final items = _catalogs[kind] ?? [];
    final missing = _selected[kind]!.difference(
      items.map((item) => item.slug).toSet(),
    );
    final shown = (_expanded.contains(kind) ? items : items.take(6)).toList();
    final columns = kind == ReferenceKind.travelStyles ? 2 : 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (_failed.containsKey(kind))
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_failed[kind]!),
              TextButton(
                onPressed: () => _load(kind),
                child: Text('Retry $title'),
              ),
            ],
          ),
        if (!_loading.contains(kind) &&
            !_failed.containsKey(kind) &&
            items.isEmpty)
          const Text(
            'Options are unavailable.',
            style: TextStyle(
              color: DarkColors.greyColor,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
          ),
        for (var offset = 0; offset < shown.length; offset += columns)
          Padding(
            padding: EdgeInsets.only(
              bottom: offset + columns < shown.length ? 8 : 0,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in shown.skip(offset).take(columns))
                  _chip(item.name, _selected[kind]!.contains(item.slug), () {
                    setState(() {
                      if (!_selected[kind]!.add(item.slug)) {
                        _selected[kind]!.remove(item.slug);
                      }
                    });
                  }),
              ],
            ),
          ),
        // Applied values remain explicit and removable when a catalog changes
        // or is unavailable. Never silently broaden the originating query.
        if (missing.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slug in missing)
                InputChip(
                  label: Text('Selected: $slug'),
                  tooltip:
                      'Previously applied selection; not in the available $title options',
                  backgroundColor: DarkColors.primaryColor,
                  labelStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                  onDeleted: () =>
                      setState(() => _selected[kind]!.remove(slug)),
                ),
            ],
          ),
        if (items.length > 6)
          TextButton.icon(
            iconAlignment: IconAlignment.end,
            style: TextButton.styleFrom(
              foregroundColor: DarkColors.primaryColor,
              textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => setState(() {
              if (!_expanded.add(kind)) _expanded.remove(kind);
            }),
            label: Text(_expanded.contains(kind) ? 'Show Less' : 'Show More'),
            icon: Icon(
              _expanded.contains(kind)
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    backgroundColor: const Color(0xFF141414),
    selectedColor: DarkColors.primaryColor,
    side: const BorderSide(color: Color(0xFF292929)),
    shape: const StadiumBorder(),
    labelStyle: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
  );

  void _apply() {
    if (_session != _preferences.sessionRevision) return;
    // New choices come only from returned catalogs. Previously applied values
    // survive catalog changes until the user removes them or resets the draft.
    Navigator.pop(
      context,
      BuddiesFilters(
        gender: _gender,
        nationality: _nationality,
        languages: _selected[ReferenceKind.languages]!,
        interests: _selected[ReferenceKind.interests]!,
        travelStyles: _selected[ReferenceKind.travelStyles]!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _invalidSession
      ? Scaffold(
          appBar: AppBar(
            leading: Navigator.of(context).canPop()
                ? const BackButtonWidget()
                : null,
            title: const Text('Filters'),
          ),
          body: const Center(
            child: Text('Your session changed. Reopen filters.'),
          ),
        )
      : Scaffold(
          backgroundColor: DarkColors.backgroundColor,
          appBar: AppBar(
            centerTitle: true,
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'Filters',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
            leadingWidth: 64,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: BackButtonWidget(
                onTap: () => Navigator.maybePop(context),
                size: 44,
                iconSize: 24,
              ),
            ),
          ),
          body: BuddiesLoadingOverlay(
            loading: _loading.isNotEmpty || _countriesLoading,
            child: SafeArea(
              top: false,
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                children: [
                  const Text(
                    'Traveler Gender',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  for (final entry in {
                    'male': 'Male',
                    'female': 'Female',
                  }.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        entry.value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      activeColor: DarkColors.primaryColor,
                      value: _gender.contains(entry.key),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _gender.add(entry.key);
                        } else {
                          _gender.remove(entry.key);
                        }
                      }),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Color(0xFF292929), thickness: 1),
                  ),
                  const Text(
                    'Nationality',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      foregroundColor: DarkColors.greyColor,
                      side: const BorderSide(color: Color(0xFF292929)),
                      textStyle: Theme.of(context).textTheme.labelLarge!
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w400),
                      backgroundColor: const Color(0xFF141414),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _countriesLoading || _countries.isEmpty
                        ? null
                        : _pickNationality,
                    child: const Row(
                      children: [
                        Expanded(child: Text('Select nationality')),
                        Icon(Icons.keyboard_arrow_down),
                      ],
                    ),
                  ),
                  if (_countriesError != null)
                    TextButton(
                      onPressed: _loadCountries,
                      child: Text('$_countriesError Retry countries'),
                    ),
                  if (!_countriesLoading &&
                      _countriesError == null &&
                      _countries.isEmpty)
                    TextButton(
                      onPressed: _loadCountries,
                      child: const Text('Countries are unavailable. Retry'),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final code in _nationality)
                        InputChip(
                          label: Text(
                            _countries
                                    .where((country) => country.code == code)
                                    .map((country) => country.name)
                                    .firstOrNull ??
                                code,
                          ),
                          backgroundColor: DarkColors.primaryColor,
                          labelStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.none,
                          ),
                          shape: const StadiumBorder(),
                          side: BorderSide.none,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          deleteIcon: const Icon(
                            Icons.cancel_outlined,
                            size: 18,
                          ),
                          deleteIconColor: Colors.white,
                          onDeleted: () =>
                              setState(() => _nationality.remove(code)),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Color(0xFF292929), thickness: 1),
                  ),
                  _catalog(ReferenceKind.languages, 'Languages'),
                  _catalog(ReferenceKind.interests, 'Interests'),
                  _catalog(ReferenceKind.travelStyles, 'Travel Style'),
                ],
              ),
            ),
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: DarkColors.backgroundColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: Color(0xFF292929))),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _gender.clear();
                          _nationality.clear();
                          for (final values in _selected.values) {
                            values.clear();
                          }
                        }),
                        child: const Text(
                          'Reset',
                          style: TextStyle(
                            color: DarkColors.greyColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: DarkColors.primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 46),
                          shape: const StadiumBorder(),
                          textStyle: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                        onPressed: _apply,
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}
