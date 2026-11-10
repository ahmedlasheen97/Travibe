import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'profile_model.dart';
import 'settings_update.dart';

class SettingsRepo {
  SettingsRepo({
    ApiService? apiService,
    Set<String> supportedCurrencies = const {'AED'},
  }) : _api = apiService ?? ApiService(),
       supportedCurrencies = Set.unmodifiable(supportedCurrencies);
  final ApiService _api;
  // AED is explicitly present in the supplied backend contract. Extend this
  // only with a backend-confirmed list, not the generic currency picker data.
  final Set<String> supportedCurrencies;

  Future<ProfileModel> update(SettingsUpdate update) async {
    final response = await _api.patch('settings', update.toJson());
    final data = response is Map ? response['data'] : null;
    if (data is! Map<String, dynamic> ||
        !{'en', 'ar'}.contains(data['locale']) ||
        !data.containsKey('currency_code') ||
        (data['currency_code'] != null &&
            (data['currency_code'] is! String ||
                !RegExp(r'^[A-Z]{3}$').hasMatch(data['currency_code']))) ||
        [
          'show_active_status',
          'show_in_travel_buddy',
          'push_notifications_enabled',
        ].any((key) => data[key] is! bool)) {
      throw ApiError(
        message:
            'Unable to read the confirmed settings. Refresh and try again.',
      );
    }
    return ProfileModel.fromJson(data);
  }
}
