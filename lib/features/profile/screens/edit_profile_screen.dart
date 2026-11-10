import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:country_picker/country_picker.dart';
import 'package:travibe/core/places/current_city_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/profile/cubit/profile_cubit.dart';
import 'package:travibe/features/profile/cubit/edit_profile_cubit.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/features/profile/data/profile_update.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_repo.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/features/profile/screens/interests_screen.dart';
import 'package:travibe/features/profile/screens/languages_screen.dart';
import 'package:travibe/features/profile/screens/travel_style_screen.dart';
import 'package:travibe/features/profile/widgets/discard_changes_dialog_widget.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.owner,
    this.selectionRepo,
    this.avatarRepo,
    this.mediaUpload,
  });
  final ProfileModel profile;
  final ProfileCubit owner;
  final ProfileSetupRepo? selectionRepo;
  final ProfileAvatarRepo? avatarRepo;
  final MediaUploadService? mediaUpload;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final ProfileDraft _draft;
  late final EditProfileCubit _editor;
  late final ProfileSetupRepo _selectionRepo;
  Country? _nationalityCountry;
  late final ProfileModel _initialProfile;
  bool _choosingCity = false;
  late List<ProfileReference> _languages;
  late List<ProfileReference> _interests;
  late List<ProfileReference> _travelStyles;
  String? _gender;
  bool _allowPop = false;
  bool _selecting = false;
  bool _confirming = false;
  bool get _isDirty => _draft.isDirty || _editor.state.avatar != null;
  bool get _isSaving => _editor.state.saving;
  bool get _pickingAvatar => _editor.state.selectingAvatar;
  Map<String, List<String>> _errors = {};

  static const int _bioMaxLength = 180;

  // Common country -> nationality (demonym) map. Extend as needed;
  // falls back to the country name itself if not listed.
  static const Map<String, String> _demonyms = {
    'EG': 'Egyptian',
    'SA': 'Saudi',
    'AE': 'Emirati',
    'JO': 'Jordanian',
    'LB': 'Lebanese',
    'MA': 'Moroccan',
    'DZ': 'Algerian',
    'TN': 'Tunisian',
    'IQ': 'Iraqi',
    'SY': 'Syrian',
    'KW': 'Kuwaiti',
    'QA': 'Qatari',
    'BH': 'Bahraini',
    'OM': 'Omani',
    'US': 'American',
    'GB': 'British',
    'FR': 'French',
    'DE': 'German',
    'IT': 'Italian',
    'ES': 'Spanish',
    'IN': 'Indian',
    'PK': 'Pakistani',
    'TR': 'Turkish',
    'CA': 'Canadian',
    'AU': 'Australian',
  };

  String _nationalityLabel(Country country) {
    return _demonyms[country.countryCode] ?? country.name;
  }

  @override
  void initState() {
    super.initState();
    final loaded = widget.owner.state;
    _initialProfile =
        loaded is ProfileLoaded && loaded.profile.id == widget.profile.id
        ? loaded.profile
        : widget.profile;
    _draft = ProfileDraft(_initialProfile);
    _editor = EditProfileCubit(
      widget.owner,
      avatarRepo: widget.avatarRepo,
      mediaUpload: widget.mediaUpload,
    );
    _selectionRepo = widget.selectionRepo ?? ProfileSetupRepo();
    _fullNameController = TextEditingController(
      text: _initialProfile.name ?? '',
    );
    _usernameController = TextEditingController(
      text: _initialProfile.username ?? '',
    );
    _bioController = TextEditingController(text: _initialProfile.bio ?? '');
    _nationalityCountry = _country(_initialProfile.nationalityCode);
    _gender = ['male', 'female', 'other'].contains(_initialProfile.gender)
        ? _initialProfile.gender
        : null;
    _languages = List.of(_initialProfile.languageSelections);
    _interests = List.of(_initialProfile.interestSelections);
    _travelStyles = List.of(_initialProfile.travelStyleSelections);
  }

  Country? _country(String? code) =>
      code == null ? null : Country.tryParse(code);
  String? _nullable(String text) => text.trim().isEmpty ? null : text.trim();
  void _change(String key, dynamic value) {
    setState(() {
      _draft.set(key, value);
      _errors.removeWhere(
        (field, _) => field == key || field.startsWith('$key.'),
      );
    });
  }

  String? _error(String key) {
    final errors = {...ProfileUpdate.validate(_draft.changes), ..._errors};
    return errors[key]?.firstOrNull ??
        errors.entries
            .where((entry) => entry.key.startsWith('$key.'))
            .firstOrNull
            ?.value
            .firstOrNull;
  }

  bool get _canSave =>
      _isDirty &&
      !_isSaving &&
      !_selecting &&
      !_pickingAvatar &&
      !_choosingCity &&
      !_confirming &&
      !_editor.state.sessionChanged &&
      ProfileUpdate.validate(_draft.changes).isEmpty;

  @override
  void dispose() {
    _editor.close();
    _fullNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_isSaving || _selecting || _pickingAvatar || _choosingCity) {
      return false;
    }
    if (!_isDirty) return true;
    return showDiscardChangesDialogWidget(context);
  }

  Future<void> _leave() async {
    if (!await _onWillPop() || !mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _pickAvatar() async {
    if (_selecting ||
        _confirming ||
        _isSaving ||
        _editor.state.sessionChanged) {
      return;
    }
    await _editor.pickAvatar();
  }

  void _pickNationality() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      exclude: const ['AC', 'XK'],
      countryListTheme: CountryListThemeData(
        backgroundColor: const Color(0xFF141414),
        textStyle: const TextStyle(color: Colors.white, fontSize: 14),
        searchTextStyle: const TextStyle(color: Colors.white),
        bottomSheetHeight: MediaQuery.of(context).size.height * 0.75,
        inputDecoration: InputDecoration(
          hintText: 'Search country',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          filled: true,
          fillColor: const Color(0xFF1C1C1C),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      onSelect: (country) {
        setState(() {
          _nationalityCountry = country;
          _draft.set('nationality_code', country.countryCode);
          _errors.remove('nationality_code');
        });
      },
    );
  }

  Future<void> _pickCurrentCity() async {
    if (_choosingCity ||
        _selecting ||
        _isSaving ||
        _pickingAvatar ||
        _editor.state.sessionChanged) {
      return;
    }
    _choosingCity = true;
    final session = PreferencesManager().sessionRevision;
    try {
      final city = await pickCurrentCity(context);
      if (!mounted ||
          city == null ||
          session != PreferencesManager().sessionRevision) {
        return;
      }
      setState(() {
        _draft.selectCity(city);
        _errors.remove('current_location');
      });
    } finally {
      if (mounted) setState(() => _choosingCity = false);
    }
  }

  void _clearCurrentCity() {
    if (_isSaving || _choosingCity || _editor.state.sessionChanged) return;
    setState(() {
      _draft.selectCity(null);
      _errors.remove('current_location');
    });
  }

  Future<void> _editLanguages() =>
      _editSelection(ReferenceKind.languages, 'languages_spoken', _languages);
  Future<void> _editInterests() =>
      _editSelection(ReferenceKind.interests, 'interests', _interests);
  Future<void> _editTravelStyle() => _editSelection(
    ReferenceKind.travelStyles,
    'travel_styles',
    _travelStyles,
  );

  Future<void> _editSelection(
    ReferenceKind kind,
    String field,
    List<ProfileReference> current,
  ) async {
    if (_selecting || _isSaving || _pickingAvatar) return;
    setState(() => _selecting = true);
    try {
      final catalog = await _selectionRepo.loadCatalog(kind);
      if (!mounted) return;
      final options = <String, ProfileReference>{
        for (final item in current) item.slug: item,
        for (final item in catalog)
          item.slug: ProfileReference(slug: item.slug, name: item.name),
      }.values.toList();
      final selected = current.map((e) => e.slug).toList();
      final Widget page = switch (kind) {
        ReferenceKind.languages => LanguagesScreen(
          initiallySelected: selected,
          options: options,
        ),
        ReferenceKind.interests => InterestsScreen(
          initiallySelected: selected,
          options: options,
        ),
        ReferenceKind.travelStyles => TravelStyleScreen(
          initiallySelected: selected,
          options: options,
        ),
      };
      final result = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (!mounted || result == null) return;
      final values = options.where((e) => result.contains(e.slug)).toList();
      setState(() {
        switch (kind) {
          case ReferenceKind.languages:
            _languages = values;
          case ReferenceKind.interests:
            _interests = values;
          case ReferenceKind.travelStyles:
            _travelStyles = values;
        }
        _draft.set(field, result.isEmpty ? null : result);
        _errors.remove(field);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load options. Tap Edit to retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving ||
        _confirming ||
        _pickingAvatar ||
        _selecting ||
        _choosingCity ||
        _editor.state.sessionChanged ||
        !_isDirty) {
      return;
    }
    setState(() => _errors = ProfileUpdate.validate(_draft.changes));
    if (!_formKey.currentState!.validate() || _errors.isNotEmpty) return;
    if (_draft.clearsRequired) {
      _confirming = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear profile details?'),
          content: const Text(
            'Clearing your username or required selections may make your profile incomplete.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear and Save'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (confirmed != true || _isSaving) return;
    }
    final saving = _editor.save(_draft);
    setState(() {});
    final saved = await saving;
    if (!mounted || _editor.state.sessionChanged) return;
    if (saved) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } else {
      final failure = _editor.state.error;
      setState(() => _errors = Map.of(failure?.fieldErrors ?? {}));
      _formKey.currentState!.validate();
      if (failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.message),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              100 + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EditProfileCubit, EditProfileState>(
      bloc: _editor,
      builder: (context, state) {
        if (state.sessionChanged) {
          return Scaffold(
            backgroundColor: DarkColors.backgroundColor,
            appBar: AppBar(
              leading: Navigator.of(context).canPop()
                  ? const BackButtonWidget()
                  : null,
              title: const Text('Edit Profile'),
            ),
            body: const Center(
              child: Text('Your session changed. Reopen Edit Profile.'),
            ),
          );
        }
        return _buildForm(context);
      },
    );
  }

  Widget _buildForm(BuildContext context) {
    return PopScope(
      canPop:
          _allowPop ||
          (!_isDirty && !_isSaving && !_selecting && !_pickingAvatar),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leave();
      },
      child: Scaffold(
        backgroundColor: DarkColors.backgroundColor,
        body: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: AbsorbPointer(
              absorbing: _isSaving || _selecting || _pickingAvatar,
              child: Column(
                children: [
                  if (_selecting || _pickingAvatar)
                    const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  _buildTopBar(),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        const SizedBox(height: 20),
                        Center(child: _buildAvatar()),
                        if (_pickingAvatar)
                          const Text(
                            'Opening photo library…',
                            textAlign: TextAlign.center,
                          ),
                        if (_editor.state.avatar != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            switch (_editor.state.uploadStage) {
                              MediaUploadStage.uploading => 'Uploading photo…',
                              MediaUploadStage.finalizing => 'Verifying photo…',
                              MediaUploadStage.processing =>
                                'Processing photo…',
                              null =>
                                _isSaving
                                    ? 'Saving profile…'
                                    : 'Photo selected. Save Changes to upload.',
                            },
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('discard-avatar-preview'),
                            onPressed: _editor.discardAvatarPreview,
                            child: const Text('Discard preview'),
                          ),
                        ],
                        if (_editor.state.avatarError != null)
                          Text(
                            _editor.state.avatarError!,
                            key: const ValueKey('avatar-error'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        const SizedBox(height: 24),
                        _buildLabel('Full Name', required: true),
                        const SizedBox(height: 8),
                        _buildTextField(
                          _fullNameController,
                          hint: 'Enter your full name',
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('User Name'),
                        const SizedBox(height: 8),
                        _buildUsernameField(),
                        const SizedBox(height: 20),
                        _buildLabel('Nationality'),
                        const SizedBox(height: 8),
                        _buildCountryField(
                          selected: _nationalityCountry,
                          displayLabel: _nationalityCountry != null
                              ? _nationalityLabel(_nationalityCountry!)
                              : _draft.changes.containsKey('nationality_code')
                              ? null
                              : _initialProfile.nationality,
                          hint: 'Select your nationality',
                          onTap: _pickNationality,
                          field: 'nationality_code',
                          onClear: _nationalityCountry == null
                              ? null
                              : () {
                                  _nationalityCountry = null;
                                  _change('nationality_code', null);
                                },
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('Current City'),
                        const SizedBox(height: 8),
                        _buildCountryField(
                          selected: null,
                          displayLabel: _draft.currentLocation,
                          hint: 'Select your current city',
                          onTap: _pickCurrentCity,
                          onClear: _draft.currentLocation == null
                              ? null
                              : _clearCurrentCity,
                          field: 'current_location',
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('Bio'),
                        const SizedBox(height: 8),
                        _buildBioField(),
                        const SizedBox(height: 20),
                        _buildLabel('Gender'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('edit-profile-gender'),
                          initialValue: _gender,
                          isExpanded: true,
                          dropdownColor: DarkColors.darkgreyColor,
                          // DropdownButton replaces the fill with focusColor
                          // while focused; the global input theme is light.
                          focusColor: DarkColors.darkgreyColor,
                          borderRadius: BorderRadius.circular(28),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: DarkColors.greyColor,
                            size: 20,
                          ),
                          hint: const Text(
                            'Not specified',
                            style: TextStyle(
                              color: DarkColors.greyColor,
                              fontSize: 14,
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            errorText: _error('gender'),
                            filled: true,
                            fillColor: DarkColors.darkgreyColor,
                            focusColor: DarkColors.darkgreyColor,
                            hoverColor: Colors.transparent,
                            constraints: const BoxConstraints(minHeight: 52),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                'Not specified',
                                style: TextStyle(color: DarkColors.greyColor),
                              ),
                            ),
                            for (final value in ['male', 'female', 'other'])
                              DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                          ],
                          onChanged: (value) {
                            _gender = value;
                            _change('gender', value);
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildChipSection(
                          'Languages',
                          _languages,
                          _editLanguages,
                          'languages_spoken',
                        ),
                        const SizedBox(height: 20),
                        _buildChipSection(
                          'Interests',
                          _interests,
                          _editInterests,
                          'interests',
                        ),
                        const SizedBox(height: 20),
                        _buildChipSection(
                          'Travel Style',
                          _travelStyles,
                          _editTravelStyle,
                          'travel_styles',
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: _buildSaveButton(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'Edit Profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: BackButtonWidget(onTap: _leave, size: 36, iconSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final preview = _editor.state.avatar;
    final ImageProvider? image = preview != null
        ? MemoryImage(preview.bytes)
        : _initialProfile.avatarUrl?.isNotEmpty == true
        ? NetworkImage(_initialProfile.avatarUrl!)
        : null;
    return Stack(
      children: [
        CircleAvatar(
          key: const ValueKey('edit-profile-avatar'),
          radius: 48,
          backgroundColor: const Color(0xFF1C1C1C),
          backgroundImage: image,
          child: image != null
              ? null
              : const Icon(Icons.person, size: 48, color: Colors.white54),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Semantics(
            label: 'Change profile photo',
            button: true,
            child: InkWell(
              key: const ValueKey('pick-profile-avatar'),
              onTap: _pickAvatar,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: DarkColors.primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: DarkColors.backgroundColor,
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFDB4A3D)),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, {
    required String hint,
  }) {
    return TextFormField(
      readOnly: _isSaving,
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (value) => _change('full_name', value.trim()),
      validator: (_) => _error('full_name'),
      key: const ValueKey('full_name'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      readOnly: _isSaving,
      controller: _usernameController,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (value) => _change('username', _nullable(value)),
      validator: (_) => _error('username'),
      key: const ValueKey('username'),
      decoration: InputDecoration(
        prefixText: '@',
        prefixStyle: const TextStyle(color: Colors.white70),

        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildCountryField({
    required Country? selected,
    required String hint,
    required VoidCallback onTap,
    String? displayLabel,
    required String field,
    VoidCallback? onClear,
  }) {
    final cityField = field == 'current_location';
    final enabled =
        !_isSaving && !_selecting && !_pickingAvatar && !_choosingCity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: ValueKey('edit-profile-$field'),
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: cityField
                ? const EdgeInsets.fromLTRB(20, 4, 8, 4)
                : const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                if (selected != null) ...[
                  Text(
                    selected.flagEmoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    displayLabel ?? hint,
                    style: TextStyle(
                      color: displayLabel?.isNotEmpty == true
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: cityField ? 'Clear current city' : 'Clear',
                    style: cityField
                        ? IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )
                        : null,
                    constraints: cityField
                        ? const BoxConstraints.tightFor(width: 44, height: 44)
                        : null,
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: enabled ? onClear : null,
                  ),
                if (cityField)
                  IconButton(
                    tooltip: 'Choose current city',
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                    ),
                    onPressed: enabled ? onTap : null,
                  )
                else
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                  ),
              ],
            ),
          ),
        ),
        if (_error(field) != null)
          Text(_error(field)!, style: const TextStyle(color: Colors.redAccent)),
      ],
    );
  }

  Widget _buildBioField() {
    return TextFormField(
      readOnly: _isSaving,
      controller: _bioController,
      key: const ValueKey('bio'),
      validator: (_) => _error('bio'),
      maxLength: _bioMaxLength,
      maxLines: 4,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (value) => _change('bio', _nullable(value)),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        counterText: '${_bioController.text.length}/$_bioMaxLength',
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildChipSection(
    String title,
    List<ProfileReference> values,
    VoidCallback onEdit,
    String field,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            InkWell(
              onTap: onEdit,
              child: Text(
                'Edit',
                style: TextStyle(
                  color: DarkColors.primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (_error(field) != null)
          Text(_error(field)!, style: const TextStyle(color: Colors.redAccent)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((v) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2B1E3D),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                v.name,
                style: const TextStyle(color: Color(0xFFC9A9E9), fontSize: 13),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _canSave ? _saveChanges : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isDirty
              ? DarkColors.primaryColor
              : DarkColors.primaryColor.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: _isSaving
            ? Semantics(
                label: 'Saving profile',
                child: const CupertinoActivityIndicator(
                  radius: 11,
                  color: DarkColors.primaryColor,
                ),
              )
            : const Text('Save Changes', style: ActionButtonStyle.label),
      ),
    );
  }
}
