import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:country_picker/country_picker.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/app_styles.dart';
import 'package:travibe/core/reference/countries_repo.dart';
import 'package:travibe/features/profilesetup/data/profile_identity_validation.dart';
import 'package:travibe/features/profilesetup/widgets/profile_country_picker.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';

class Step1BasicInfo extends StatefulWidget {
  const Step1BasicInfo({super.key, required this.cubit});
  final ProfileSetupCubit cubit;

  @override
  State<Step1BasicInfo> createState() => _Step1BasicInfoState();
}

class _Step1BasicInfoState extends State<Step1BasicInfo> {
  ProfileSetupCubit get cubit => widget.cubit;
  ProfileSetupState get state => cubit.state;
  bool _nameTouched = false;
  bool _usernameTouched = false;
  bool _countryOpen = false;
  String? _countryName;
  String? _countryNameCode;
  bool _avatarImageFailed = false;
  String? _lastAvatarUrl;
  @override
  void initState() {
    super.initState();
    cubit.fullNameController.addListener(_onChanged);
  }

  @override
  void dispose() {
    cubit.fullNameController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canProceed =>
      !state.isSaving &&
      !state.restoring &&
      !state.selectingAvatar &&
      !state.uploadingAvatar &&
      state.avatar == null &&
      !state.fieldErrors.containsKey('full_name') &&
      !state.fieldErrors.containsKey('username') &&
      ProfileIdentityValidation.fullName(cubit.fullNameController.text) ==
          null &&
      ProfileIdentityValidation.username(cubit.usernameController.text) ==
          null &&
      state.usernameStatus == UsernameStatus.available;

  Future<void> _pickCountry() async {
    if (_countryOpen || state.isSaving) return;
    _countryOpen = true;
    final session = PreferencesManager().sessionRevision;
    try {
      final selected = await showModalBottomSheet<ReferenceCountry>(
        context: context,
        isScrollControlled: true,
        backgroundColor: DarkColors.backgroundColor,
        builder: (_) => FractionallySizedBox(
          heightFactor: .85,
          child: ProfileCountryPicker(
            load: cubit.loadCountries,
            locale: Localizations.localeOf(context).languageCode,
          ),
        ),
      );
      if (!mounted ||
          selected == null ||
          cubit.isClosed ||
          session != PreferencesManager().sessionRevision) {
        return;
      }
      setState(() {
        _countryName = selected.name;
        _countryNameCode = selected.code;
      });
      cubit.setCountry(selected.code);
    } finally {
      _countryOpen = false;
    }
  }

  TextStyle get _fieldLabelStyle => AppStyles.smallSubtitlesStyles.copyWith(
    fontSize: AppSizes.adaptiveFont(16),
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  Widget _requiredLabel(String label) => Text.rich(
    TextSpan(
      text: label,
      children: const [
        TextSpan(
          text: ' *',
          style: TextStyle(color: DarkColors.primaryColor),
        ),
      ],
    ),
    style: _fieldLabelStyle,
    semanticsLabel: '$label, required',
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.adaptiveWidth(24)),
      children: [
        const SizedBox(height: 24),
        Center(child: _buildAvatarPicker()),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Add a profile photo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Help others recognize you',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
        if (state.restoring) const Center(child: CupertinoActivityIndicator()),
        if (state.restoreError != null)
          TextButton(
            onPressed: cubit.restore,
            child: Text(state.restoreError!),
          ),
        if (state.avatarError != null) ...[
          Text(
            state.avatarError!,
            style: const TextStyle(color: DarkColors.dangerColor),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: state.avatar != null
                    ? cubit.uploadAvatar
                    : cubit.pickAvatar,
                child: const Text('Retry photo'),
              ),
              if (state.avatar != null)
                TextButton(
                  onPressed: cubit.discardAvatar,
                  child: const Text('Remove selected photo'),
                ),
            ],
          ),
        ],
        SizedBox(height: AppSizes.adaptiveHeight(24)),
        _requiredLabel('Full Name'),
        const SizedBox(height: 8),
        CustomTextField(
          title: '',
          reservePrefixSpace: false,
          enabled: !state.isSaving,
          errorText:
              state.fieldErrors['full_name']?.firstOrNull ??
              (_nameTouched
                  ? ProfileIdentityValidation.fullName(
                      cubit.fullNameController.text,
                    )
                  : null),
          onChanged: (_) => setState(() => _nameTouched = true),
          controller: cubit.fullNameController,
          hintText: 'enter your full name',
        ),
        const SizedBox(height: 16),
        _requiredLabel('User Name'),
        const SizedBox(height: 8),
        CustomTextField(
          title: '',
          enabled: !state.isSaving,
          errorText:
              state.fieldErrors['username']?.firstOrNull ??
              (_usernameTouched
                  ? ProfileIdentityValidation.username(
                      cubit.usernameController.text,
                    )
                  : null),
          controller: cubit.usernameController,
          hintText: 'enter your username',
          prefixIcon: const Icon(
            Icons.alternate_email_rounded,
            color: Colors.white54,
          ),
          suffixIcon: _usernameSuffix(),
          onChanged: (value) {
            setState(() => _usernameTouched = true);
            cubit.onUsernameChanged(value);
          },
        ),
        _buildUsernameStatus(),
        const SizedBox(height: 16),
        Text('Current Country', style: _fieldLabelStyle),
        const SizedBox(height: 8),
        _buildCountryField(),
        if (state.fieldErrors['country_code']?.firstOrNull case final error?)
          Text(error, style: const TextStyle(color: DarkColors.dangerColor)),
        const SizedBox(height: 40),
        CustomButton(
          title: state.isSaving ? 'Saving...' : 'Next',
          onPressed: _canProceed ? cubit.saveBasicInfo : null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget? _usernameSuffix() {
    switch (state.usernameStatus) {
      case UsernameStatus.idle:
        return null;
      case UsernameStatus.checking:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case UsernameStatus.available:
        return const Icon(
          Icons.check_circle_rounded,
          color: Colors.greenAccent,
          size: 22,
        );
      case UsernameStatus.taken:
      case UsernameStatus.invalid:
        return const Icon(
          Icons.cancel_rounded,
          color: Color(0xFFDB4A3D),
          size: 22,
        );
    }
  }

  Widget _buildUsernameStatus() {
    if (state.usernameStatus == UsernameStatus.idle) {
      return const SizedBox.shrink();
    }

    final (String text, Color color) = switch (state.usernameStatus) {
      UsernameStatus.checking => ('Checking availability...', Colors.white54),
      UsernameStatus.available => ('Username is available', Colors.greenAccent),
      UsernameStatus.taken => (
        'Username is already taken',
        const Color(0xFFDB4A3D),
      ),
      UsernameStatus.invalid => (
        state.usernameMessage.isNotEmpty
            ? state.usernameMessage
            : 'Invalid username',
        const Color(0xFFDB4A3D),
      ),
      UsernameStatus.idle => ('', Colors.transparent),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!state.fieldErrors.containsKey('username'))
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8, start: 4),
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        if (state.usernameStatus == UsernameStatus.invalid &&
            !state.fieldErrors.containsKey('username') &&
            ProfileIdentityValidation.username(cubit.usernameController.text) ==
                null)
          TextButton(
            onPressed: state.isSaving
                ? null
                : () => cubit.onUsernameChanged(cubit.usernameController.text),
            child: const Text('Retry username check'),
          ),
      ],
    );
  }

  Widget _buildAvatarPicker() {
    if (_lastAvatarUrl != state.avatarUrl) {
      _lastAvatarUrl = state.avatarUrl;
      _avatarImageFailed = false;
    }
    final ImageProvider? image = state.avatar != null
        ? MemoryImage(state.avatar!.bytes)
        : state.avatarUrl != null && !_avatarImageFailed
        ? NetworkImage(state.avatarUrl!)
        : null;
    return GestureDetector(
      onTap: state.selectingAvatar || state.uploadingAvatar || state.isSaving
          ? null
          : cubit.pickAvatar,
      child: Stack(
        children: [
          DottedBorder(
            options: CircularDottedBorderOptions(
              color: DarkColors.primaryColor,
              strokeWidth: 1.5,
              dashPattern: [
                AppSizes.adaptiveRadius(18),
                AppSizes.adaptiveRadius(12),
              ],
              padding: const EdgeInsets.all(6),
            ),
            child: CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFFE0E0E0),
              backgroundImage: image,
              onBackgroundImageError: image == null
                  ? null
                  : (_, _) {
                      if (mounted) setState(() => _avatarImageFailed = true);
                    },
              child:
                  state.avatar == null &&
                      (state.avatarUrl == null || _avatarImageFailed)
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.grey,
                      size: 48,
                    )
                  : null,
            ),
          ),
          if (state.selectingAvatar || state.uploadingAvatar)
            const Positioned.fill(
              child: Center(
                child: CupertinoActivityIndicator(color: Colors.white),
              ),
            ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: DarkColors.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: DarkColors.backgroundColor, width: 3),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountryField() {
    return InkWell(
      onTap: state.isSaving ? null : _pickCountry,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                state.countryCode == null
                    ? 'Select your current country'
                    : (_countryNameCode == state.countryCode
                              ? _countryName
                              : null) ??
                          Country.tryParse(state.countryCode!)?.name ??
                          state.countryCode!,
                style: TextStyle(
                  color: state.countryCode != null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }
}
