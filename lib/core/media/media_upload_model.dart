/// Confirmed media fields needed by uploads. A URL string does not establish
/// object availability: only ready status permits claiming the image.
enum MediaStatus { pending, processing, ready, failed }

class UploadMedia {
  const UploadMedia({required this.id, required this.status});
  final int id;
  final MediaStatus status;

  /// GET supports both OpenAPI's data envelope and the deployed media envelope.
  /// Reject ambiguous/malformed wrappers rather than falling through to another.
  factory UploadMedia.fromEnvelope(
    dynamic json, {
    String expectedType = 'image',
  }) {
    if (json is! Map || json.containsKey('data') == json.containsKey('media')) {
      throw const FormatException('Expected one media resource envelope');
    }
    return UploadMedia._fromResponseResource(
      json[json.containsKey('data') ? 'data' : 'media'],
      expectedType,
    );
  }

  /// Finalize now has runtime evidence for media as well as documented data.
  factory UploadMedia.fromFinalizeEnvelope(
    dynamic json, {
    String expectedType = 'image',
  }) => UploadMedia.fromEnvelope(json, expectedType: expectedType);

  factory UploadMedia._fromResponseResource(dynamic json, String expectedType) {
    final media = UploadMedia.fromJson(json);
    // Only ID/status are required by this projection. Validate other documented
    // fields when returned, without requiring optional processing metadata.
    if (json.containsKey('type') &&
        json['type'] != null &&
        json['type'] != expectedType) {
      throw const FormatException('Invalid media type');
    }
    for (final field in [
      'mime_type',
      'original_name',
      'error',
      'created_at',
      'updated_at',
    ]) {
      if (json.containsKey(field) &&
          json[field] != null &&
          json[field] is! String) {
        throw const FormatException('Invalid media string field');
      }
    }
    for (final field in ['url', 'thumbnail_url']) {
      if (json.containsKey(field) &&
          json[field] is! String &&
          !(field == 'thumbnail_url' && json[field] == null)) {
        throw const FormatException('Invalid media URL field');
      }
    }
    for (final field in ['size', 'width', 'height']) {
      if (!json.containsKey(field)) continue;
      final value = json[field];
      if (value == null && field != 'size') continue;
      if (value is! int || value < 0) {
        throw const FormatException('Invalid media dimension or size');
      }
    }
    return media;
  }

  factory UploadMedia.fromJson(dynamic json) {
    if (json is! Map || json['id'] is! int || (json['id'] as int) < 1) {
      throw const FormatException('Invalid media response');
    }
    final status = MediaStatus.values
        .where((e) => e.name == json['status'])
        .firstOrNull;
    if (status == null) throw const FormatException('Invalid media status');
    return UploadMedia(id: json['id'] as int, status: status);
  }
}

class MediaPresign {
  const MediaPresign({
    required this.media,
    required this.uploadUrl,
    required this.uploadMethod,
    required this.uploadHeaders,
    required this.expiresAt,
  });
  final UploadMedia media;
  final String uploadUrl;
  final String uploadMethod;
  final Map<String, List<String>> uploadHeaders;
  final DateTime expiresAt;

  factory MediaPresign.fromJson(dynamic json) {
    if (json is! Map) throw const FormatException('Invalid upload response');
    final url = json['upload_url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    final expiry = json['expires_at'];
    final expiresAt = expiry is String ? DateTime.tryParse(expiry) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        expiresAt == null ||
        json['upload_method'] != 'PUT' ||
        json['upload_headers'] is! Map) {
      throw const FormatException('Invalid upload response');
    }
    final headers = <String, List<String>>{};
    for (final entry in (json['upload_headers'] as Map).entries) {
      final value = entry.value;
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          !(value is String ||
              value is List &&
                  value.isNotEmpty &&
                  value.every((e) => e is String))) {
        throw const FormatException('Invalid upload headers');
      }
      headers[entry.key as String] = List<String>.unmodifiable(
        value is String ? [value] : (value as List).cast<String>(),
      );
    }
    return MediaPresign(
      media: UploadMedia.fromJson(json['media']),
      uploadUrl: url as String,
      uploadMethod: 'PUT',
      uploadHeaders: Map.unmodifiable(headers),
      expiresAt: expiresAt,
    );
  }
}
