import 'package:travibe/core/reference/nationality_labels.dart';
import 'package:travibe/core/widgets/country_search_sheet.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/app_loaders.dart';
import 'package:travibe/core/widgets/glass_confirm_dialog.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:country_picker/country_picker.dart';
import 'package:travibe/core/places/current_city_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:travibe/core/widgets/upload_progress_ring.dart';
import 'package:travibe/core/widgets/dashed_avatar_picker.dart';
import 'package:travibe/features/profile/cubit/profile_picture_upload_cubit.dart';
import 'package:travibe/features/profile/widgets/profile_picture_upload_toast.dart';
import 'package:travibe/features/profile/data/profile_avatar_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shimmer/shimmer.dart';
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

  /// Uploads a picked picture; injectable for tests.
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
  late final ProfilePictureUploadCubit _pictures;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
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

  /// The chip section whose option catalog is loading.
  ReferenceKind? _loadingCatalog;
  bool _confirming = false;

  /// A picture still uploading or failed is an unsaved change too.
  bool get _isDirty =>
      _draft.isDirty ||
      _pictures.state is ProfilePictureUploading ||
      _pictures.state is ProfilePictureFailed;
  bool get _isSaving => _editor.state.saving;
  bool get _pickingAvatar => _editor.state.selectingAvatar;
  Map<String, List<String>> _errors = {};

  static const int _bioMaxLength = 180;

  String _nationalityLabel(Country country) =>
      nationalityLabel(country.countryCode, countryName: country.name);

  @override
  void initState() {
    super.initState();
    final loaded = widget.owner.state;
    _initialProfile =
        loaded is ProfileLoaded && loaded.profile.id == widget.profile.id
        ? loaded.profile
        : widget.profile;
    _draft = ProfileDraft(_initialProfile);
    // Owned by this screen: leaving without saving cancels the upload and
    // keeps the old picture.
    _pictures = ProfilePictureUploadCubit(
      uploads: widget.mediaUpload == null ? null : () => widget.mediaUpload!,
    );
    _editor = EditProfileCubit(
      widget.owner,
      pictures: _pictures,
      avatarRepo: widget.avatarRepo,
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
      !_isSaving &&
      !_selecting &&
      !_pickingAvatar &&
      !_pictures.uploading &&
      _draft.isDirty &&
      !_choosingCity &&
      !_confirming &&
      !_editor.state.sessionChanged &&
      ProfileUpdate.validate(_draft.changes).isEmpty;

  @override
  void dispose() {
    _editor.close();
    _pictures.close();
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

  Future<void> _pickNationality() async {
    final code = _nationalityCountry?.countryCode;
    final picked = await showCountrySearchSheet(
      context,
      selected: {?code},
      load: () =>
          _selectionRepo.loadCountries(PreferencesManager().language.value),
    );
    final country = picked == null ? null : Country.tryParse(picked.code);
    if (!mounted || country == null) return;
    setState(() {
      _nationalityCountry = country;
      _draft.set('nationality_code', country.countryCode);
      _errors.remove('nationality_code');
    });
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
    setState(() {
      _selecting = true;
      _loadingCatalog = kind;
    });
    try {
      final catalog = await _selectionRepo.loadCatalog(kind);
      if (!mounted) return;
      setState(() => _loadingCatalog = null);
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
        _messenger.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Unable to load options. Tap Edit to retry.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _selecting = false;
          _loadingCatalog = null;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving ||
        _confirming ||
        _pickingAvatar ||
        _selecting ||
        _choosingCity ||
        _pictures.uploading ||
        _editor.state.sessionChanged ||
        !_draft.isDirty) {
      return;
    }
    setState(() => _errors = ProfileUpdate.validate(_draft.changes));
    if (!_formKey.currentState!.validate() || _errors.isNotEmpty) return;
    if (_draft.clearsRequired) {
      _confirming = true;
      final confirmed = await showGlassConfirmDialog(
        context,
        title: 'Clear profile details?',
        message:
            'Clearing your username or required selections may make your profile incomplete.',
        confirmLabel: 'Clear and Save',
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (!confirmed || _isSaving) return;
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
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: Text(failure.message),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(
              AppSizes.pw20,
              0,
              AppSizes.pw20,
              AppSizes.ph100 + MediaQuery.paddingOf(context).bottom,
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

  /// The picture works like a form field: uploading shows the white-ring
  /// toast; a finished upload marks the form changed (no success toast) and
  /// Save Changes commits it; a failure is a red toast with Retry and X.
  void _onPictureUpload(BuildContext context, ProfilePictureUploadState state) {
    // Float above the bottom Save Changes button instead of covering it.
    final toast = TravibeToast.of(
      context,
      bottomMargin: AppSizes.h56 + AppSizes.ph12 + AppSizes.ph20 + AppSizes.h8,
    );
    final data = profilePictureToast(
      uploading: state is ProfilePictureUploading,
      failed: state is ProfilePictureFailed,
      // The SnackBar is built by the messenger, so bind the cubit directly;
      // progress ticks update the ring without re-presenting the toast.
      progress:
          BlocSelector<
            ProfilePictureUploadCubit,
            ProfilePictureUploadState,
            double
          >(
            bloc: _pictures,
            selector: (state) =>
                state is ProfilePictureUploading ? state.progress : 1,
            builder: (_, progress) => UploadProgressRing(progress: progress),
          ),
      onRetry: _pictures.retry,
      onDiscard: _pictures.discard,
    );
    data == null ? toast.dismiss() : toast.present(data);
    setState(() => _draft.set('avatar_media_id', _pictures.mediaId));
  }

  Widget _buildForm(BuildContext context) {
    // Own messenger: the toast (a floating SnackBar here, since this route
    // covers Root's toast slot) disappears with the screen, leaving Root's.
    return ScaffoldMessenger(
      key: _messenger,
      child: BlocListener<ProfilePictureUploadCubit, ProfilePictureUploadState>(
        bloc: _pictures,
        // Status changes only; progress is drawn by the toast's ring.
        listenWhen: (a, b) => a.runtimeType != b.runtimeType,
        listener: _onPictureUpload,
        child:
            BlocBuilder<ProfilePictureUploadCubit, ProfilePictureUploadState>(
              bloc: _pictures,
              builder: (context, _) => _buildPage(context),
            ),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
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
                  SizedBox(height: AppSizes.h8),
                  _buildTopBar(),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
                      children: [
                        SizedBox(height: AppSizes.h20),
                        Center(child: _buildAvatar()),
                        if (_editor.state.avatarError != null)
                          Text(
                            _editor.state.avatarError!,
                            key: const ValueKey('avatar-error'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        SizedBox(height: AppSizes.h24),
                        _buildLabel('Full Name', required: true),
                        SizedBox(height: AppSizes.h8),
                        _buildTextField(
                          _fullNameController,
                          hint: 'Enter your full name',
                        ),
                        SizedBox(height: AppSizes.h20),
                        _buildLabel('User Name'),
                        SizedBox(height: AppSizes.h8),
                        _buildUsernameField(),
                        SizedBox(height: AppSizes.h20),
                        _buildLabel('Nationality'),
                        SizedBox(height: AppSizes.h8),
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
                        SizedBox(height: AppSizes.h20),
                        _buildLabel('Current City'),
                        SizedBox(height: AppSizes.h8),
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
                        SizedBox(height: AppSizes.h20),
                        _buildLabel('Bio'),
                        SizedBox(height: AppSizes.h8),
                        _buildBioField(),
                        SizedBox(height: AppSizes.h20),
                        _buildLabel('Gender'),
                        SizedBox(height: AppSizes.h8),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('edit-profile-gender'),
                          initialValue: _gender,
                          isExpanded: true,
                          dropdownColor: DarkColors.darkgreyColor,
                          // DropdownButton replaces the fill with focusColor
                          // while focused; the global input theme is light.
                          focusColor: DarkColors.darkgreyColor,
                          borderRadius: BorderRadius.circular(AppSizes.r28),
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: DarkColors.greyColor,
                            size: AppSizes.w20,
                          ),
                          hint: Text(
                            'Not specified',
                            style: TextStyle(
                              color: DarkColors.greyColor,
                              fontSize: AppSizes.sp14,
                            ),
                          ),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.sp14,
                          ),
                          decoration: InputDecoration(
                            errorText: _error('gender'),
                            filled: true,
                            fillColor: DarkColors.darkgreyColor,
                            focusColor: DarkColors.darkgreyColor,
                            hoverColor: Colors.transparent,
                            constraints: BoxConstraints(
                              minHeight: AppSizes.h52,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: AppSizes.pw20,
                              vertical: AppSizes.ph14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSizes.r28),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSizes.r28),
                              borderSide: BorderSide.none,
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSizes.r28),
                              borderSide: BorderSide.none,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSizes.r28),
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
                        SizedBox(height: AppSizes.h24),
                        _buildChipSection(
                          'Languages',
                          _languages,
                          _editLanguages,
                          'languages_spoken',
                          loading: _loadingCatalog == ReferenceKind.languages,
                        ),
                        SizedBox(height: AppSizes.h20),
                        _buildChipSection(
                          'Interests',
                          _interests,
                          _editInterests,
                          'interests',
                          loading: _loadingCatalog == ReferenceKind.interests,
                        ),
                        SizedBox(height: AppSizes.h20),
                        _buildChipSection(
                          'Travel Style',
                          _travelStyles,
                          _editTravelStyle,
                          'travel_styles',
                          loading:
                              _loadingCatalog == ReferenceKind.travelStyles,
                        ),
                        SizedBox(height: AppSizes.h12),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.pw20,
                      AppSizes.ph12,
                      AppSizes.pw20,
                      AppSizes.ph20,
                    ),
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
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      child: SizedBox(
        height: AppSizes.h44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'Edit Profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppSizes.sp17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: BackButtonWidget(onTap: _leave),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    // The picked photo stays on screen while uploading and after success.
    final preview = _pictures.state.preview;
    final ImageProvider? image = preview != null
        ? MemoryImage(preview)
        : _initialProfile.avatarUrl?.isNotEmpty == true
        ? NetworkImage(_initialProfile.avatarUrl!)
        : null;
    return DashedAvatarPicker(
      image: image,
      onTap: _pickAvatar,
      avatarKey: const ValueKey('edit-profile-avatar'),
      badgeKey: const ValueKey('pick-profile-avatar'),
      semanticsLabel: 'Change profile photo',
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white,
          fontSize: AppSizes.sp14,
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
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
      onChanged: (value) => _change('full_name', value.trim()),
      validator: (_) => _error('full_name'),
      key: const ValueKey('full_name'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: EdgeInsets.symmetric(
          vertical: AppSizes.ph14,
          horizontal: AppSizes.pw20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      readOnly: _isSaving,
      controller: _usernameController,
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
      onChanged: (value) => _change('username', _nullable(value)),
      validator: (_) => _error('username'),
      key: const ValueKey('username'),
      decoration: InputDecoration(
        prefixText: '@',
        prefixStyle: const TextStyle(color: Colors.white70),

        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: EdgeInsets.symmetric(
          vertical: AppSizes.ph14,
          horizontal: AppSizes.pw20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r28),
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
          borderRadius: BorderRadius.circular(AppSizes.r28),
          child: Container(
            padding: cityField
                ? EdgeInsets.fromLTRB(
                    AppSizes.pw20,
                    AppSizes.ph4,
                    AppSizes.pw8,
                    AppSizes.ph4,
                  )
                : EdgeInsets.symmetric(
                    horizontal: AppSizes.pw20,
                    vertical: AppSizes.ph14,
                  ),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(AppSizes.r28),
            ),
            child: Row(
              children: [
                if (selected != null) ...[
                  Text(
                    selected.flagEmoji,
                    style: TextStyle(fontSize: AppSizes.sp18),
                  ),
                  SizedBox(width: AppSizes.w10),
                ],
                Expanded(
                  child: Text(
                    displayLabel ?? hint,
                    style: TextStyle(
                      color: displayLabel?.isNotEmpty == true
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                      fontSize: AppSizes.sp14,
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
                        ? BoxConstraints.tightFor(
                            width: AppSizes.w44,
                            height: AppSizes.h44,
                          )
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
                    constraints: BoxConstraints.tightFor(
                      width: AppSizes.w44,
                      height: AppSizes.h44,
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
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
      onChanged: (value) => _change('bio', _nullable(value)),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        counterText: '${_bioController.text.length}/$_bioMaxLength',
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        contentPadding: EdgeInsets.all(AppSizes.pw16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildChipSection(
    String title,
    List<ProfileReference> values,
    VoidCallback onEdit,
    String field, {
    bool loading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.sp15,
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
                  fontSize: AppSizes.sp13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (_error(field) != null)
          Text(_error(field)!, style: const TextStyle(color: Colors.redAccent)),
        SizedBox(height: AppSizes.h10),
        if (loading)
          _chipSkeleton(field)
        else
          Wrap(
            spacing: AppSizes.w8,
            runSpacing: AppSizes.h8,
            children: values.map((v) {
              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.pw14,
                  vertical: AppSizes.ph8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B1E3D),
                  borderRadius: BorderRadius.circular(AppSizes.r20),
                ),
                child: Text(
                  v.name,
                  style: TextStyle(
                    color: const Color(0xFFC9A9E9),
                    fontSize: AppSizes.sp13,
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  /// Placeholder chips shown while a section's option catalog loads.
  Widget _chipSkeleton(String field) => Shimmer.fromColors(
    key: ValueKey('chip-skeleton-$field'),
    enabled: !MediaQuery.disableAnimationsOf(context),
    baseColor: DarkColors.darkgreyColor,
    highlightColor: DarkColors.greyColor.withValues(alpha: .25),
    child: Wrap(
      spacing: AppSizes.w8,
      runSpacing: AppSizes.h8,
      children: [
        for (final width in const [72.0, 96.0, 64.0, 84.0])
          Container(
            width: width.w,
            height: AppSizes.sp13 * 1.4 + AppSizes.ph8 * 2,
            decoration: BoxDecoration(
              color: DarkColors.darkgreyColor,
              borderRadius: BorderRadius.circular(AppSizes.r20),
            ),
          ),
      ],
    ),
  );

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.h56,
      child: ElevatedButton(
        onPressed: _canSave ? _saveChanges : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _canSave
              ? DarkColors.primaryColor
              : DarkColors.primaryColor.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: _isSaving
            ? Semantics(
                label: 'Saving profile',
                child: AppActivityIndicator(radius: AppSizes.r11),
              )
            : const Text('Save Changes', style: ActionButtonStyle.label),
      ),
    );
  }
}
