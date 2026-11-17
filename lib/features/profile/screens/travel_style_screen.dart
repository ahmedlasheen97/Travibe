import 'package:travibe/core/widgets/travibe_choice_chip.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:flutter/material.dart';
import 'package:travibe/features/profile/data/profile_model.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class TravelStyleScreen extends StatefulWidget {
  final List<String> initiallySelected;
  final List<ProfileReference> options;

  const TravelStyleScreen({
    super.key,
    required this.initiallySelected,
    required this.options,
  });

  @override
  State<TravelStyleScreen> createState() => _TravelStyleScreenState();
}

class _TravelStyleScreenState extends State<TravelStyleScreen> {
  static const int _maxSelection = 3;

  late final Set<String> _selected = widget.initiallySelected.toSet();

  void _toggle(String label) {
    setState(() {
      if (_selected.contains(label)) {
        _selected.remove(label);
      } else {
        if (_selected.length >= _maxSelection) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You can select up to $_maxSelection travel styles',
              ),
            ),
          );
          return;
        }
        _selected.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildTopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 12),
                  const Text(
                    'Travel Style',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How do you love to travel? ($_maxSelection max)',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in widget.options)
                        TravibeChoiceChip(
                          label: option.name,
                          selected: _selected.contains(option.slug),
                          onTap: () => _toggle(option.slug),
                        ),
                    ],
                  ),
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
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'Travel Style',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: BackButtonWidget(
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () => Navigator.pop(context, _selected.toList()),
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: const Text('Save', style: ActionButtonStyle.label),
      ),
    );
  }
}
