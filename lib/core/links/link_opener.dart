import 'package:url_launcher/url_launcher.dart';

/// Opens web links in the in-app browser (SFSafariViewController on iOS,
/// Chrome Custom Tabs on Android). Tests pass a fake.
class LinkOpener {
  const LinkOpener();

  /// False when the page couldn't be opened.
  Future<bool> openInApp(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      return false;
    }
  }
}
