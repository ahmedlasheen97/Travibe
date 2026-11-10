import 'package:travibe/core/datasource/remotedata/api_error.dart';

class SettingsUpdate {
  SettingsUpdate(Map<String, dynamic> values)
    : _values = Map.unmodifiable(values) {
    if (values.isEmpty) throw ApiError(message: 'Choose a setting to update.');
    for (final entry in values.entries) {
      final valid = switch (entry.key) {
        'locale' => {'en', 'ar'}.contains(entry.value),
        'currency_code' =>
          entry.value == null ||
              entry.value is String &&
                  RegExp(r'^[A-Z]{3}$').hasMatch(entry.value),
        'show_active_status' ||
        'show_in_travel_buddy' ||
        'push_notifications_enabled' => entry.value is bool,
        _ => false,
      };
      if (!valid) throw ApiError(message: 'Invalid settings update.');
    }
  }
  final Map<String, dynamic> _values;
  Map<String, dynamic> toJson() => Map.of(_values);
}

class CurrencySelection {
  const CurrencySelection(this.code);
  final String? code;
}
