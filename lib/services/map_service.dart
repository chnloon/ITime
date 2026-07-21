import 'package:url_launcher/url_launcher.dart';

class MapService {
  /// Open navigation to a location using the geo: URI scheme.
  /// This delegates to the system's default map app, which on most Android
  /// devices will offer a chooser. On Android 11+ the geo: intent works
  /// without package visibility queries, unlike custom URI schemes.
  static Future<void> navigateToLocation({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final encodedLabel = label != null ? Uri.encodeComponent(label) : '';
    // geo:0,0?q=lat,lng(label)  — standard geo URI that any map app handles
    final geoUri =
        'geo:0,0?q=$latitude,$longitude${label != null ? '($encodedLabel)' : ''}';
    await launchUrl(Uri.parse(geoUri));
  }

  /// Open navigation with a text address via geo: URI.
  static Future<void> navigateToAddress(String address) async {
    final encodedAddress = Uri.encodeComponent(address);
    final geoUri = 'geo:0,0?q=$encodedAddress';
    await launchUrl(Uri.parse(geoUri));
  }
}
