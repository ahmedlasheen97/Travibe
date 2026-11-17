import 'package:travibe/core/widgets/travibe_toast.dart';
import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/travibe_choice_chip.dart';
import 'package:travibe/features/profilesetup/widgets/setup_skip_button.dart';
import 'package:travibe/features/profilesetup/data/profile_selection_options.dart';

/// "Add Another" language chip; hidden until custom languages are supported.
const showAddAnotherLanguage = false;

class Step2LanguagesInterests extends StatefulWidget {
  final List<String> selectedLanguages;
  final ValueChanged<List<String>> onLanguagesChanged;
  final List<String> selectedInterests;
  final ValueChanged<List<String>> onInterestsChanged;
  final VoidCallback onNext;
  final VoidCallback? onSkip;
  final bool isSaving;

  const Step2LanguagesInterests({
    super.key,
    required this.selectedLanguages,
    required this.onLanguagesChanged,
    required this.selectedInterests,
    required this.onInterestsChanged,
    required this.onNext,
    this.onSkip,
    required this.isSaving,
  });

  @override
  State<Step2LanguagesInterests> createState() =>
      _Step2LanguagesInterestsState();
}

class _Step2LanguagesInterestsState extends State<Step2LanguagesInterests> {
  static const int _maxLanguages = 4;
  static const int _maxInterests = 6;

  void _toggleLanguage(String value) {
    if (widget.isSaving) return;
    final current = List<String>.from(widget.selectedLanguages);
    if (current.contains(value)) {
      current.remove(value);
    } else if (current.length < _maxLanguages) {
      current.add(value);
    } else {
      TravibeToast.show(
        context,
        TravibeToastData.error('You can select up to $_maxLanguages languages'),
      );
      return;
    }
    widget.onLanguagesChanged(current);
  }

  void _toggleInterest(String value) {
    if (widget.isSaving) return;
    final current = List<String>.from(widget.selectedInterests);
    if (current.contains(value)) {
      current.remove(value);
    } else if (current.length < _maxInterests) {
      current.add(value);
    } else {
      TravibeToast.show(
        context,
        TravibeToastData.error('You can select up to $_maxInterests interests'),
      );
      return;
    }
    widget.onInterestsChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    // Spacing follows Figma (docs/figma/profile/setup_step2.png).
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 30),
        const _SectionTitle('Languages Spoken'),
        const SizedBox(height: 6),
        _SectionSubtitle('Select languages you speak ($_maxLanguages max)'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in profileLanguageOptions)
              TravibeChoiceChip(
                label: option,
                selected: widget.selectedLanguages.contains(option),
                onTap: widget.isSaving ? null : () => _toggleLanguage(option),
              ),
            if (showAddAnotherLanguage) _addAnotherChip(),
          ],
        ),
        const SizedBox(height: 32),
        const _SectionTitle('Interests'),
        const SizedBox(height: 6),
        _SectionSubtitle('What excites you most? ($_maxInterests max)'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in profileInterestOptions)
              TravibeChoiceChip(
                label: option,
                selected: widget.selectedInterests.contains(option),
                onTap: widget.isSaving ? null : () => _toggleInterest(option),
              ),
          ],
        ),
        const SizedBox(height: 40),
        CustomButton(
          title: widget.isSaving ? 'Saving...' : 'Next',
          onPressed: widget.isSaving ? null : widget.onNext,
        ),
        if (widget.onSkip != null) ...[
          const SizedBox(height: 16),
          SetupSkipButton(onPressed: widget.onSkip),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _addAnotherChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3B3B3B)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, color: Colors.white70, size: 16),
          SizedBox(width: 4),
          Text(
            'Add Another',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _SectionSubtitle extends StatelessWidget {
  const _SectionSubtitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: DarkColors.greyColor,
      fontSize: 14,
      height: 20 / 14,
    ),
  );
}
