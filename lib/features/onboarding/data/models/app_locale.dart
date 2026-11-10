class AppLocale {
  const AppLocale({required this.code, required this.name, required this.rtl});
  final String code, name;
  final bool rtl;

  // These are the app's installed Material localization resources.
  bool get supported => const {'en', 'ar'}.contains(code);
}

class LocaleCatalog {
  const LocaleCatalog({required this.locales, required this.defaultCode});
  final List<AppLocale> locales;
  final String defaultCode;

  factory LocaleCatalog.parse(dynamic response) {
    final data = response is Map ? response['data'] : null;
    if (data is! Map ||
        data['locales'] is! List ||
        data['default'] is! String) {
      throw const FormatException('Invalid locales');
    }
    final codes = <String>{};
    final locales = (data['locales'] as List)
        .map((item) {
          if (item is! Map ||
              item['code'] is! String ||
              !RegExp(r'^[a-z]{2}$').hasMatch(item['code']) ||
              item['name'] is! String ||
              (item['name'] as String).trim().isEmpty ||
              item['rtl'] is! bool ||
              !codes.add(item['code'])) {
            throw const FormatException('Invalid locale');
          }
          return AppLocale(
            code: item['code'],
            name: item['name'],
            rtl: item['rtl'],
          );
        })
        .toList(growable: false);
    if (locales.isEmpty || !codes.contains(data['default'])) {
      throw const FormatException('Invalid default locale');
    }
    return LocaleCatalog(
      locales: List.unmodifiable(locales),
      defaultCode: data['default'],
    );
  }
}
