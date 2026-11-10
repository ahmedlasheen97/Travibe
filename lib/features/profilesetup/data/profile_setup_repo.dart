import 'package:travibe/core/reference/countries_repo.dart';
import 'package:dio/dio.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/datasource/remotedata/api_exceptions.dart';
import 'package:travibe/core/datasource/remotedata/api_service.dart';
import 'package:travibe/features/profilesetup/data/username_availability_model.dart';
import 'package:travibe/features/profilesetup/data/reference_item.dart';
import 'package:travibe/features/profilesetup/data/profile_selection_options.dart';
import 'package:travibe/features/profilesetup/data/profile_setup_result.dart';

class ProfileSetupRepo {
  ProfileSetupRepo({ApiService? apiService})
    : _apiService = apiService ?? ApiService();
  final ApiService _apiService;
  final Map<ReferenceKind, List<ReferenceItem>> _catalogs = {};
  final Set<String> _savedTravelStyles = {};
  final Set<String> _savedLanguages = {};
  final Set<String> _savedInterests = {};

  Future<List<ReferenceCountry>> loadCountries(String locale) =>
      CountriesRepo.shared.load(locale);

  Future<List<ReferenceItem>> loadCatalog(ReferenceKind kind) async {
    final items = ReferenceItem.parseCatalog(
      await _apiService.get('reference/${kind.path}'),
    );
    _catalogs[kind] = items;
    return items;
  }

  Future<void> _validate(ReferenceKind kind, List<String>? selected) async {
    if (selected == null) return;
    if (selected.length > kind.limit ||
        selected.toSet().length != selected.length) {
      throw ApiError(
        message: 'Select up to ${kind.limit} distinct ${kind.path}.',
      );
    }
    if (selected.isEmpty ||
        kind == ReferenceKind.travelStyles &&
            selected.every(_savedTravelStyles.contains)) {
      return;
    }
    final items = _catalogs[kind] ?? await loadCatalog(kind);
    final allowed = items.map((item) => item.slug).toSet();
    if (selected.any((slug) => !allowed.contains(slug))) {
      throw ApiError(message: 'Select ${kind.path} from the current catalog.');
    }
  }

  /// Shape-rule failures (too short, bad characters) come back as a 422,
  /// which surfaces here as a thrown ApiError.
  Future<UsernameAvailabilityModel> checkUsername(String username) async {
    try {
      final response = await _apiService.get(
        'profile/username-availability',
        queryParameters: {'username': username},
      );

      if (response is Map<String, dynamic>) {
        return UsernameAvailabilityModel.fromJson(response);
      } else {
        throw ApiError(message: 'Invalid response format');
      }
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(
        message: 'Unable to update profile setup. Please try again.',
      );
    }
  }

  /// Saves any subset of the setup fields (idempotent).
  Future<ProfileSetupResult> saveSetup({
    String? fullName,
    String? username,
    String? gender,
    List<String>? languages,
    List<String>? interests,
    List<String>? travelStyles,
  }) async {
    try {
      if (username != null &&
          (username.runes.length < 3 || username.runes.length > 30)) {
        throw ApiError(message: 'Use a username of 3–30 characters.');
      }
      if (gender != null && !{'male', 'female', 'other'}.contains(gender)) {
        throw ApiError(message: 'Select male, female or other.');
      }
      final languageSlugs = serializeProfileSelections(
        languages,
        mapping: profileLanguageSlugs,
        limit: 4,
        field: 'languages',
        verifiedSlugs: _savedLanguages,
      );
      final interestSlugs = serializeProfileSelections(
        interests,
        mapping: profileInterestSlugs,
        limit: 6,
        field: 'interests',
        verifiedSlugs: _savedInterests,
      );
      await _validate(ReferenceKind.travelStyles, travelStyles);
      final result = ProfileSetupResult.fromJson(
        await _apiService.patch('profile/setup', {
          'full_name': ?fullName,
          'username': ?username,
          'gender': ?gender,
          'languages_spoken': ?languageSlugs,
          'interests': ?interestSlugs,
          'travel_styles': ?travelStyles,
        }),
      );
      if (result.resourceFields.contains('travel_styles')) {
        _savedTravelStyles
          ..clear()
          ..addAll(
            result.profile!.travelStyleSelections.map((item) => item.slug),
          );
      }
      if (result.resourceFields.contains('languages_spoken') ||
          result.resourceFields.contains('languages')) {
        _savedLanguages
          ..clear()
          ..addAll(result.profile!.languageSelections.map((item) => item.slug));
      }
      if (result.resourceFields.contains('interests')) {
        _savedInterests
          ..clear()
          ..addAll(result.profile!.interestSelections.map((item) => item.slug));
      }
      return result;
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(
        message: 'Unable to update profile setup. Please try again.',
      );
    }
  }

  /// Uses the existing completion endpoint after PATCH reports the review step.
  /// Missing requirements remain server validation errors, not local guesses.
  Future<ProfileSetupResult> completeSetup() async {
    try {
      return ProfileSetupResult.completion(
        await _apiService.post('profile/setup/complete', {}),
      );
    } on ApiError {
      rethrow;
    } on DioException catch (e) {
      throw ApiExceptions.handleError(e);
    } catch (e) {
      throw ApiError(
        message: 'Unable to update profile setup. Please try again.',
      );
    }
  }
}
