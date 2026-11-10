import 'dart:io';
import 'package:travibe/core/places/current_city_picker.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/custom_text_field.dart';
import 'package:travibe/features/profilesetup/cubit/profile_setup_cubit.dart';

class Step1BasicInfo extends StatefulWidget {
  final TextEditingController fullNameController;
  final TextEditingController usernameController;
  final UsernameStatus usernameStatus;
  final String usernameMessage;
  final ValueChanged<String> onUsernameChanged;
  final File? avatarFile;
  final ValueChanged<File> onAvatarPicked;
  final String? currentLocation;
  final ValueChanged<CitySelection>? onCityChanged;
  final bool isSaving;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const Step1BasicInfo({
    super.key,
    required this.fullNameController,
    required this.usernameController,
    required this.usernameStatus,
    required this.usernameMessage,
    required this.onUsernameChanged,
    required this.avatarFile,
    required this.onAvatarPicked,
    this.currentLocation,
    this.onCityChanged,
    required this.isSaving,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<Step1BasicInfo> createState() => _Step1BasicInfoState();
}

class _Step1BasicInfoState extends State<Step1BasicInfo> {
  @override
  void initState() {
    super.initState();
    widget.fullNameController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.fullNameController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canProceed =>
      !widget.isSaving &&
      widget.fullNameController.text.trim().isNotEmpty &&
      widget.usernameStatus == UsernameStatus.available;

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      widget.onAvatarPicked(File(picked.path));
    }
  }

  Future<void> _pickCity() async {
    if (widget.isSaving) return;
    final city = await pickCurrentCity(context);
    if (mounted && !widget.isSaving && city != null) {
      widget.onCityChanged?.call(city);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
        const SizedBox(height: 28),
        CustomTextField(
          title: 'Full Name',
          controller: widget.fullNameController,
          hintText: 'enter your full name',
        ),
        const SizedBox(height: 16),
        CustomTextField(
          title: 'User Name',
          controller: widget.usernameController,
          hintText: 'enter your username',
          prefixIcon: const Icon(
            Icons.alternate_email_rounded,
            color: Colors.white54,
          ),
          suffixIcon: _usernameSuffix(),
          onChanged: widget.onUsernameChanged,
        ),
        _buildUsernameStatus(),
        const SizedBox(height: 16),
        const Text(
          'Current City',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildCityField(),
        const SizedBox(height: 40),
        CustomButton(
          title: widget.isSaving ? 'Saving...' : 'Next',
          onPressed: _canProceed ? widget.onNext : null,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: widget.isSaving ? null : widget.onSkip,
            child: Text(
              'Skip For Now',
              style: TextStyle(
                color: DarkColors.primaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget? _usernameSuffix() {
    switch (widget.usernameStatus) {
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
    if (widget.usernameStatus == UsernameStatus.idle) {
      return const SizedBox.shrink();
    }

    final (String text, Color color) = switch (widget.usernameStatus) {
      UsernameStatus.checking => ('Checking availability...', Colors.white54),
      UsernameStatus.available => ('Username is available', Colors.greenAccent),
      UsernameStatus.taken => (
        'Username is already taken',
        const Color(0xFFDB4A3D),
      ),
      UsernameStatus.invalid => (
        widget.usernameMessage.isNotEmpty
            ? widget.usernameMessage
            : 'Invalid username',
        const Color(0xFFDB4A3D),
      ),
      UsernameStatus.idle => ('', Colors.transparent),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }

  Widget _buildAvatarPicker() {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Stack(
        children: [
          DottedBorder(
            options: CircularDottedBorderOptions(
              color: DarkColors.primaryColor,
              strokeWidth: 1.5,
              dashPattern: const [6, 4],
              padding: const EdgeInsets.all(6),
            ),
            child: CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFF2A2A2A),
              backgroundImage: widget.avatarFile != null
                  ? FileImage(widget.avatarFile!)
                  : null,
              child: widget.avatarFile == null
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.white54,
                      size: 48,
                    )
                  : null,
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

  Widget _buildCityField() {
    return InkWell(
      onTap: _pickCity,
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
                widget.currentLocation ?? 'Select your current city',
                style: TextStyle(
                  color: widget.currentLocation != null
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
