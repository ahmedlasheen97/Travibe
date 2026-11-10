import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/profilesetup/data/profile_selection_options.dart';

class Step2LanguagesInterests extends StatefulWidget {
  final List<String> selectedLanguages;
  final ValueChanged<List<String>> onLanguagesChanged;
  final List<String> selectedInterests;
  final ValueChanged<List<String>> onInterestsChanged;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isSaving;

  const Step2LanguagesInterests({
    super.key,
    required this.selectedLanguages,
    required this.onLanguagesChanged,
    required this.selectedInterests,
    required this.onInterestsChanged,
    required this.onNext,
    required this.onSkip,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can select up to $_maxLanguages languages'),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can select up to $_maxInterests interests'),
        ),
      );
      return;
    }
    widget.onInterestsChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 24),
        const Text(
          'Languages Spoken',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select languages you speak ($_maxLanguages max)',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in profileLanguageOptions)
              _chip(
                option,
                widget.selectedLanguages.contains(option),
                _toggleLanguage,
              ),
            _addAnotherChip(),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Interests',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'What excites you most? ($_maxInterests max)',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in profileInterestOptions)
              _chip(
                option,
                widget.selectedInterests.contains(option),
                _toggleInterest,
              ),
          ],
        ),
        const SizedBox(height: 40),
        CustomButton(
          title: widget.isSaving ? 'Saving...' : 'Next',
          onPressed: widget.isSaving ? null : widget.onNext,
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: widget.onSkip,
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

  Widget _chip(String label, bool isSelected, ValueChanged<String> onTap) {
    return GestureDetector(
      onTap: widget.isSaving ? null : () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? DarkColors.primaryColor : const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
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
