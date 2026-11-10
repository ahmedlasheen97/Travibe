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

  static const _options = [
    {'label': 'Solo Traveler', 'image': 'assets/images/profile/avatar1.png'},
    {'label': 'Group Traveler', 'image': 'assets/images/profile/avatar2.png'},
    {'label': 'Couple Escapes', 'image': 'assets/images/profile/avatar3.png'},
    {'label': 'Friends Getaway', 'image': 'assets/images/profile/avatar4.png'},
    {'label': 'Family Traveler', 'image': 'assets/images/profile/avatar5.png'},
    {'label': 'Backpacker', 'image': 'assets/images/profile/avatar6.png'},
    {'label': 'Adventure Seeker', 'image': 'assets/images/profile/avatar7.png'},
    {'label': 'Leisure Traveler', 'image': 'assets/images/profile/avatar8.png'},
  ];

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
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.95,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = widget.options[index];
                        final art = _options
                            .where(
                              (e) =>
                                  e['label']!.toLowerCase() ==
                                  item.name.toLowerCase(),
                            )
                            .firstOrNull;
                        return _styleCard(item.slug, item.name, art?['image']);
                      }, childCount: widget.options.length),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
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
        height: 40,
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
              alignment: Alignment.centerLeft,
              child: BackButtonWidget(
                onTap: () => Navigator.of(context).maybePop(),
                size: 36,
                iconSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _styleCard(String slug, String label, String? image) {
    final isSelected = _selected.contains(slug);
    return GestureDetector(
      onTap: () => _toggle(slug),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? DarkColors.primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: image == null
                  ? const Center(
                      child: Icon(
                        Icons.travel_explore,
                        color: Colors.white54,
                        size: 48,
                      ),
                    )
                  : Image.asset(
                      image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
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
