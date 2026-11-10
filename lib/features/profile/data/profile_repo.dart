import 'package:dio/dio.dart';
import 'package:travibe/core/places/city_places_provider.dart';
import 'package:travibe/core/media/upload_diagnostics.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/profile/data/profile_model.dart';

import 'package:travibe/features/profile/data/profile_update.dart';

class ProfileRepo {
  ProfileRepo({ApiService? apiService})
    : _api = apiService ?? ApiService(observer: observeProfileApiRequest);
  final ApiService _api;

  Future<ProfileModel> saveLocation(CitySelection city) async {
    final response = await _api.put('profile/location', {
      'location': '${city.cityName}, ${city.countryCode}',
    });
    final data = response is Map ? response['data'] : null;
    if (data is! Map<String, dynamic> ||
        !data.containsKey('current_location') ||
        data['current_location'] is! String) {
      throw ApiError(
        message:
            'Unable to read the saved current location. Reload your profile.',
      );
    }
    return ProfileModel.fromJson(data);
  }

  Future<void> clearLocation() async {
    // ApiService returns response.data; a 204 has no resource to parse.
    await _api.delete('profile/location');
  }

  Future<void> updateProfile(ProfileUpdate update) async {
    if (update.isEmpty) return;
    try {
      // PATCH's response shape is unverified. Read the canonical resource via GET.
      await _api.patch('profile', update.toJson());
    } on ApiError {
      rethrow;
    } on DioException catch (error) {
      throw ApiExceptions.handleError(error);
    } catch (_) {
      throw ApiError(message: 'Unable to save your profile. Please try again.');
    }
  }

  Future<void> reportUser(String userId, String reason) async {
    final id = int.tryParse(userId);
    if (id == null || id < 1) {
      throw ApiError(message: 'This profile is unavailable.');
    }
    if (!const {
      'spam_or_scam',
      'harassment',
      'inappropriate_content',
      'something_else',
    }.contains(reason)) {
      throw ApiError(message: 'Choose a valid report reason.');
    }
    final response = await _api.post('reports', {
      'type': 'user',
      'id': id,
      'reason': reason,
    });
    if (response is! Map || response['data'] is! Map) {
      throw ApiError(message: 'Unable to confirm the report. Please retry.');
    }
  }

  Future<ProfileModel> getMyProfile() async => (await _get('profile'))!;

  Future<ProfileModel?> getPublicProfile(int userId) {
    if (userId < 1) throw ArgumentError.value(userId, 'userId');
    return _get('users/$userId', publicUserId: userId);
  }

  Future<ProfileModel?> _get(String path, {int? publicUserId}) async {
    try {
      final response = await _api.get(path);
      if (response is! Map || !response.containsKey('data')) {
        throw ApiError(
          message: 'Unable to read the profile response. Please try again.',
        );
      }
      final data = response['data'];
      // Only the public endpoint's explicit data:null denotes unavailability.
      if (data == null && publicUserId != null) return null;
      if (data is! Map<String, dynamic>) {
        throw ApiError(
          message: 'Unable to read the profile response. Please try again.',
        );
      }
      final profile = ProfileModel.fromJson(data);
      if (publicUserId != null && profile.id != publicUserId.toString()) {
        throw ApiError(
          message: 'The server returned a different profile. Please try again.',
        );
      }
      return profile;
    } on ApiError {
      rethrow;
    } on DioException catch (error) {
      throw ApiExceptions.handleError(error);
    } catch (_) {
      throw ApiError(message: 'Unable to load this profile. Please try again.');
    }
  }
}
