import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import 'package:travibe/core/widgets/custom_button.dart';
import 'package:travibe/core/widgets/sheet_handle.dart';
import 'package:travibe/features/home/data/report_reason.dart';

export 'package:travibe/features/home/data/report_reason.dart';

/// Figma: post/report_sheet. Returns null when dismissed.
class ReportReasonSheet extends StatefulWidget {
  const ReportReasonSheet({super.key});

  static Future<ReportSubmission?> show(BuildContext context) {
    return showModalBottomSheet<ReportSubmission>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ReportReasonSheet(),
    );
  }

  // Same frame colour as the post menu sheet.
  static const _sheetColor = Color(0xFF0A0A0A);

  @override
  State<ReportReasonSheet> createState() => _ReportReasonSheetState();
}

class _ReportReasonSheetState extends State<ReportReasonSheet> {
  ReportReason? _selected;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _selected!;
    final note = _details.text.trim();
    Navigator.pop(
      context,
      ReportSubmission(
        reason,
        reason == ReportReason.somethingElse && note.isNotEmpty ? note : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSizes.pw24,
            AppSizes.ph16,
            AppSizes.pw24,
            AppSizes.ph20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: SheetHandle()),
              SizedBox(height: AppSizes.ph24),
              Text(
                'Why are you reporting this?',
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  color: DarkColors.whiteColor,
                  fontSize: AppSizes.sp18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppSizes.ph12),
              for (final reason in ReportReason.values)
                InkWell(
                  key: ValueKey('report-reason-${reason.apiValue}'),
                  onTap: () => setState(() => _selected = reason),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSizes.pw14,
                      vertical: AppSizes.ph16,
                    ),
                    child: Row(
                      children: [
                        _RadioCircle(selected: _selected == reason),
                        SizedBox(width: AppSizes.pw16),
                        Expanded(
                          child: Text(
                            reason.label,
                            style: TextStyle(
                              fontFamily: 'Plus Jakarta Sans',
                              color: DarkColors.whiteColor,
                              fontSize: AppSizes.sp14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_selected == ReportReason.somethingElse) ...[
                SizedBox(height: AppSizes.ph8),
                TextField(
                  key: const ValueKey('report-details'),
                  controller: _details,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: reportDescriptionMaxLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    color: DarkColors.whiteColor,
                    fontSize: AppSizes.sp14,
                  ),
                  cursorColor: DarkColors.whiteColor,
                  decoration: InputDecoration(
                    hintText: 'Tell us more (optional)',
                    hintStyle: TextStyle(
                      color: DarkColors.greyColor,
                      fontSize: AppSizes.sp14,
                    ),
                    counterStyle: TextStyle(
                      color: DarkColors.greyColor,
                      fontSize: AppSizes.sp12,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.r12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              SizedBox(height: AppSizes.ph16),
              CustomButton(
                key: const ValueKey('report-submit'),
                title: 'Submit Report',
                onPressed: _selected == null ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioCircle extends StatelessWidget {
  final bool selected;

  const _RadioCircle({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? DarkColors.primaryColor : const Color(0xFFBDBDBD),
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: DarkColors.primaryColor,
                ),
              ),
            )
          : null,
    );
  }
}
