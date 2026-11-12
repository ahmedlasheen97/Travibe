import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';

/// Figma ⋮ menu frame shared by the post and profile option sheets.
const optionsSheetColor = Color(0xFF0A0A0A);

/// Opens a ⋮ menu: rounded top 24, handle bar, rows from [builder].
Future<T?> showOptionsSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: optionsSheetColor,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(AppSizes.adaptiveRadius(24)),
    ),
  ),
  builder: builder,
);

/// Handle bar plus option rows.
class OptionsSheetBody extends StatelessWidget {
  const OptionsSheetBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: AppSizes.adaptiveHeight(16)),
        const SheetHandle(),
        SizedBox(height: AppSizes.adaptiveHeight(16)),
        ...children,
        SizedBox(height: AppSizes.adaptiveHeight(12)),
      ],
    ),
  );
}

/// 24px SVG icon from `assets/images/...`, optionally tinted.
Widget optionSvg(String path, {Color? tint}) => SvgPicture.asset(
  path,
  width: AppSizes.adaptiveRadius(24),
  height: AppSizes.adaptiveRadius(24),
  colorFilter: tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
);

/// One icon + label row. [color] tints the label (e.g. danger red).
class OptionSheetTile extends StatelessWidget {
  const OptionSheetTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.adaptiveWidth(24),
        vertical: AppSizes.adaptiveHeight(14),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: AppSizes.adaptiveRadius(24),
            child: Center(child: icon),
          ),
          SizedBox(width: AppSizes.adaptiveWidth(8)),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                color: color ?? DarkColors.whiteColor,
                fontSize: AppSizes.adaptiveFont(16),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
