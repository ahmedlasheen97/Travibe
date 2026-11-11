import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/theme/action_button_style.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:travibe/core/theme/dark_colors.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String? _selectedCategory;
  File? _screenshot;
  bool _isSubmitting = false;

  static const int _descMaxLength = 24;

  static const _categories = [
    'Bug / Technical Issue',
    'Harassment or Bullying',
    'Spam',
    'Inappropriate Content',
    'Other',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _screenshot = File(picked.path));
    }
  }

  Future<void> _showCategoryPicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.r24)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: AppSizes.h12),
            Container(
              width: AppSizes.w40,
              height: AppSizes.h4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(AppSizes.r2),
              ),
            ),
            SizedBox(height: AppSizes.h16),
            for (final category in _categories)
              ListTile(
                title: Text(
                  category,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.sp14,
                  ),
                ),
                trailing: _selectedCategory == category
                    ? Icon(Icons.check_rounded, color: DarkColors.primaryColor)
                    : null,
                onTap: () => Navigator.pop(context, category),
              ),
            SizedBox(height: AppSizes.h8),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() => _selectedCategory = result);
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a problem category')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // TODO: wire to your repo, e.g.:
      // await SupportRepo().reportProblem(
      //   category: _selectedCategory!,
      //   description: _descriptionController.text,
      //   screenshot: _screenshot,
      // );
      debugPrint(
        'Submitting report: $_selectedCategory / ${_descriptionController.text}',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit report: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
                  children: [
                    SizedBox(height: AppSizes.h8),
                    _buildTopBar(),
                    SizedBox(height: AppSizes.h24),
                    _buildCategoryField(),
                    SizedBox(height: AppSizes.h24),
                    _buildLabel('Problem', required: true),
                    SizedBox(height: AppSizes.h8),
                    _buildDescriptionField(),
                    SizedBox(height: AppSizes.h24),
                    _buildLabel('Add Screenshot (optional)'),
                    SizedBox(height: AppSizes.h10),
                    _buildScreenshotPicker(),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.pw20,
                  AppSizes.ph12,
                  AppSizes.pw20,
                  AppSizes.ph20,
                ),
                child: _buildSubmitButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: AppSizes.h40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'Report a Problem',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.sp17,
              fontWeight: FontWeight.w700,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: BackButtonWidget(
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white,
          fontSize: AppSizes.sp14,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFDB4A3D)),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryField() {
    return InkWell(
      onTap: _showCategoryPicker,
      borderRadius: BorderRadius.circular(AppSizes.r28),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.pw20,
          vertical: AppSizes.ph14,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(AppSizes.r28),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedCategory ?? 'Problem category',
                style: TextStyle(
                  color: _selectedCategory != null
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: AppSizes.sp14,
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

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLength: _descMaxLength,
      maxLines: 4,
      style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
      onChanged: (_) => setState(() {}),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please describe your problem';
        }
        return null;
      },
      decoration: InputDecoration(
        hintText: 'Describe your problem',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        counterText: '${_descriptionController.text.length}/$_descMaxLength',
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        contentPadding: EdgeInsets.all(AppSizes.pw16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.r20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildScreenshotPicker() {
    if (_screenshot != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.r16),
            child: Image.file(
              _screenshot!,
              height: AppSizes.h100,
              width: AppSizes.w100,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: () => setState(() => _screenshot = null),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black87,
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: AppSizes.w14,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: _pickScreenshot,
      borderRadius: BorderRadius.circular(AppSizes.r16),
      child: Container(
        width: AppSizes.w56,
        height: AppSizes.h56,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(AppSizes.r16),
        ),
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: Colors.white54,
          size: AppSizes.w24,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.h56,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: ActionButtonStyle.shape,
        ),
        child: _isSubmitting
            ? SizedBox(
                width: AppSizes.w22,
                height: AppSizes.h22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text('Submit Report', style: ActionButtonStyle.label),
      ),
    );
  }
}
