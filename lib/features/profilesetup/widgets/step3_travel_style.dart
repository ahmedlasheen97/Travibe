import 'package:flutter/material.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/widgets/catalog_status_view.dart';

class Step3TravelStyle extends StatefulWidget {
  final List<String> selectedTravelStyles;
  final ValueChanged<List<String>> onTravelStylesChanged;
  final VoidCallback? onFinish;
  final bool isSubmitting;
  final ReferenceCatalog catalog;
  final VoidCallback onRetry;

  const Step3TravelStyle({
    super.key,
    required this.selectedTravelStyles,
    required this.onTravelStylesChanged,
    required this.onFinish,
    required this.isSubmitting,
    required this.catalog,
    required this.onRetry,
  });

  @override
  State<Step3TravelStyle> createState() => _Step3TravelStyleState();
}

class _Step3TravelStyleState extends State<Step3TravelStyle> {
  static const int _maxSelection = 3;

  static const _options = [
    {'label': 'Solo Traveler', 'image': 'assets/images/profile/avatar1.png'},
    {'label': 'Group Traveler', 'image': 'assets/images/profile/avatar2.png'},
    {'label': 'Couple Escapes', 'image': 'assets/images/profile/avatar3.png'},
    {'label': 'Family Traveler', 'image': 'assets/images/profile/avatar5.png'},
    {'label': 'Backpacker', 'image': 'assets/images/profile/avatar6.png'},
    {'label': 'Adventure Seeker', 'image': 'assets/images/profile/avatar7.png'},
    {'label': 'Leisure Traveler', 'image': 'assets/images/profile/avatar8.png'},
    {'label': 'Digital Nomad', 'image': 'assets/images/profile/avatar4.png'},
  ];

  void _toggle(String label) {
    if (widget.isSubmitting) return;
    final current = List<String>.from(widget.selectedTravelStyles);
    if (current.contains(label)) {
      current.remove(label);
    } else if (current.length < _maxSelection) {
      current.add(label);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can select up to $_maxSelection travel styles'),
        ),
      );
      return;
    }
    widget.onTravelStylesChanged(current);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
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
              SliverToBoxAdapter(
                child: CatalogStatusView(
                  catalog: widget.catalog,
                  onRetry: widget.onRetry,
                ),
              ),
              if (widget.catalog.status == CatalogStatus.loaded &&
                  widget.catalog.items.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.95,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final option = _options[index];
                      final item = referenceForName(
                        widget.catalog.items,
                        option['label']!,
                      );
                      final isSelected =
                          item != null &&
                          widget.selectedTravelStyles.contains(item.slug);
                      return _styleCard(
                        item?.label(
                              Localizations.localeOf(context).languageCode,
                            ) ??
                            option['label']!,
                        option['image']!,
                        isSelected,
                        item?.slug,
                      );
                    }, childCount: _options.length),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: CustomButton(
            title: widget.isSubmitting ? 'Saving...' : 'Continue to Home',
            onPressed: widget.onFinish,
          ),
        ),
      ],
    );
  }

  Widget _styleCard(String label, String image, bool isSelected, String? slug) {
    return GestureDetector(
      onTap: slug == null || widget.isSubmitting ? null : () => _toggle(slug),
      child: Opacity(
        opacity: slug == null ? 0.5 : 1,
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
                child: Image.asset(
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
      ),
    );
  }
}
