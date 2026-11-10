class OnboardingModel {
  const OnboardingModel({
    required this.key,
    required this.title,
    required this.description,
    this.assetUrl,
  });

  final String key, title, description;
  final String? assetUrl;

  // The live API currently supplies null artwork. Keep the existing artwork
  // only for its matching slide key; all production copy comes from the API.
  String? get localImage => const {
    'discover': 'assets/images/onboarding/on1.png',
    'plan': 'assets/images/onboarding/on2.png',
    'together': 'assets/images/onboarding/on3 (1).png',
  }[key];

  static List<OnboardingModel> parse(dynamic response) {
    final data = response is Map ? response['data'] : null;
    if (data is! List || data.isEmpty) throw const FormatException('No slides');
    final keys = <String>{};
    return List.unmodifiable(
      data.map((item) {
        if (item is! Map ||
            ['key', 'title', 'body'].any(
              (field) =>
                  item[field] is! String ||
                  (item[field] as String).trim().isEmpty,
            ) ||
            !item.containsKey('asset_url') ||
            !keys.add(item['key'] as String)) {
          throw const FormatException('Invalid onboarding slide');
        }
        final asset = item['asset_url'];
        if (asset != null) {
          final uri = asset is String ? Uri.tryParse(asset) : null;
          if (uri == null ||
              !{'https', 'http'}.contains(uri.scheme) ||
              uri.host.isEmpty) {
            throw const FormatException('Invalid onboarding artwork');
          }
        }
        return OnboardingModel(
          key: item['key'],
          title: item['title'],
          description: item['body'],
          assetUrl: asset as String?,
        );
      }),
    );
  }
}
