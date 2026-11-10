import 'package:travibe/core/widgets/back_button_widget.dart';
import 'package:currency_picker/currency_picker.dart';
import 'package:flutter/material.dart';
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
    _allCurrencies = CurrencyService()
        .getAll()
        .where(
          (currency) =>
              widget.allowedCodes == null ||
              widget.allowedCodes!.contains(currency.code),
        )
        .toList();
    _filtered = _allCurrencies;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _allCurrencies
          : _allCurrencies.where((c) {
              return c.code.toLowerCase().contains(query) ||
                  c.name.toLowerCase().contains(query);
            }).toList();
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
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const CurrencySelection(null)),
              child: const Text('No preferred currency'),
            ),
            _buildSearchField(),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final currency = _filtered[index];
                  return _currencyTile(currency);
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'Currency',
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search for currency',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF1C1C1C),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _currencyTile(Currency currency) {
    final isSelected = currency.code == _selectedCode;
    return InkWell(
      onTap: () {
        setState(() => _selectedCode = currency.code);
        Navigator.pop(context, CurrencySelection(currency.code));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: isSelected
            ? DarkColors.primaryColor.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                currency.code,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                currency.name,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                color: DarkColors.primaryColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
