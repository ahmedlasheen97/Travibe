import 'package:travibe/core/constants/app_sizes.dart';
import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:travibe/core/theme/dark_colors.dart';
import '../data/settings_update.dart';

class CurrencyScreen extends StatefulWidget {
  final String? selectedCurrencyCode;
  final Set<String>? allowedCodes;

  const CurrencyScreen({
    super.key,
    required this.selectedCurrencyCode,
    this.allowedCodes,
  });

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  late List<Currency> _allCurrencies;
  late List<Currency> _filtered;
  late String? _selectedCode = widget.selectedCurrencyCode;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _allCurrencies =
        CurrencyService()
            .getAll()
            .where(
              (currency) =>
                  widget.allowedCodes == null ||
                  widget.allowedCodes!.contains(currency.code),
            )
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    _filtered = _allCurrencies;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  void _onSearchChanged() {
    final query = _normalize(_searchController.text);
    setState(() {
      _filtered = query.isEmpty
          ? _allCurrencies
          : _allCurrencies
                .where(
                  (c) =>
                      _normalize(c.code).contains(query) ||
                      _normalize(c.name).contains(query),
                )
                .toList();
    });
  }

  bool get _searching => _searchController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // "None" leads the list (clears the preference) unless a search is active.
    final offset = _searching ? 0 : 1;
    return Scaffold(
      backgroundColor: DarkColors.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: AppSizes.h8),
            _buildTopBar(),
            SizedBox(height: AppSizes.h16),
            _buildSearchField(),
            SizedBox(height: AppSizes.h16),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length + offset,
                itemBuilder: (context, index) {
                  if (index < offset) return _noneTile();
                  return _currencyTile(_filtered[index - offset]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      child: SizedBox(
        height: AppSizes.h44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'Currency',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppSizes.sp17,
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

  Widget _buildSearchField() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.pw20),
      child: TextField(
        key: const ValueKey('currency-search'),
        controller: _searchController,
        cursorColor: DarkColors.whiteColor,
        style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
        decoration: InputDecoration(
          hintText: 'Search for currency',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: AppSizes.sp14,
          ),
          prefixIcon: Padding(
            padding: EdgeInsets.all(AppSizes.pw14),
            child: SvgPicture.asset(
              'assets/images/interactions/search-normal.svg',
              width: AppSizes.w20,
              height: AppSizes.w20,
            ),
          ),
          filled: true,
          fillColor: const Color(0xFF1C1C1C),
          contentPadding: EdgeInsets.symmetric(vertical: AppSizes.ph14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.r28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _row({
    Key? key,
    required String code,
    required String name,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.pw20,
          vertical: AppSizes.ph14,
        ),
        color: selected
            ? DarkColors.primaryColor.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            SizedBox(
              width: AppSizes.w44,
              child: Text(
                code,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: AppSizes.sp13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                name,
                style: TextStyle(color: Colors.white, fontSize: AppSizes.sp14),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                color: DarkColors.primaryColor,
                size: AppSizes.w20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _noneTile() => _row(
    key: const ValueKey('currency-none'),
    code: '—',
    name: 'None',
    selected: _selectedCode == null,
    onTap: () => Navigator.pop(context, const CurrencySelection(null)),
  );

  Widget _currencyTile(Currency currency) => _row(
    code: currency.code,
    name: currency.name,
    selected: currency.code == _selectedCode,
    onTap: () {
      setState(() => _selectedCode = currency.code);
      Navigator.pop(context, CurrencySelection(currency.code));
    },
  );
}
