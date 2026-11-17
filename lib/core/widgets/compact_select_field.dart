import 'package:flutter/material.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';

/// One choice of a [CompactSelectField]; a null [value] means "none".
class SelectOption<T> {
  const SelectOption(this.value, this.label);
  final T? value;
  final String label;
}

/// Dark rounded field that opens a compact menu (44-tall items, 14 text,
/// rounded corners, subtle highlight on the selected item). Replaces
/// DropdownButton, whose items cannot be shorter than 48.
class CompactSelectField<T> extends StatelessWidget {
  const CompactSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.errorText,
    this.enabled = true,
  });
  final T? value;
  final List<SelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? errorText;
  final bool enabled;

  static const itemHeight = 44.0;
  static const menuRadius = 16.0;
  static const selectedColor = Color(0x14FFFFFF);

  SelectOption<T>? get _selected =>
      options.where((option) => option.value == value).firstOrNull;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset(0, box.size.height + 4), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final picked = await showMenu<SelectOption<T>>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      constraints: BoxConstraints.tightFor(width: box.size.width),
      color: DarkColors.darkgreyColor,
      elevation: 8,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(menuRadius),
      ),
      items: [
        for (final option in options)
          PopupMenuItem<SelectOption<T>>(
            value: option,
            height: itemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Container(
              key: ValueKey('select-option-${option.value}'),
              height: itemHeight,
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: option.value == value ? selectedColor : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  color: option.value == null
                      ? DarkColors.greyColor
                      : Colors.white,
                  fontSize: 14,
                  fontWeight: option.value == value
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
          ),
      ],
    );
    if (picked != null && picked.value != value) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.r28),
      borderSide: BorderSide.none,
    );
    return Semantics(
      button: true,
      child: InkWell(
        onTap: enabled ? () => _open(context) : null,
        borderRadius: BorderRadius.circular(AppSizes.r28),
        child: InputDecorator(
          decoration: InputDecoration(
            errorText: errorText,
            filled: true,
            fillColor: DarkColors.darkgreyColor,
            constraints: BoxConstraints(minHeight: AppSizes.h52),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSizes.pw20,
              vertical: AppSizes.ph14,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border,
            disabledBorder: border,
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: DarkColors.greyColor,
              size: AppSizes.w20,
            ),
          ),
          child: Text(
            selected?.value == null
                ? (selected?.label ?? options.first.label)
                : selected!.label,
            style: TextStyle(
              color: selected?.value == null
                  ? DarkColors.greyColor
                  : Colors.white,
              fontSize: AppSizes.sp14,
            ),
          ),
        ),
      ),
    );
  }
}
