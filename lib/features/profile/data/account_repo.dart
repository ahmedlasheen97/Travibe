import 'package:travibe/core/datasource/remotedata/api_service.dart';

class AccountRepo {
  AccountRepo({ApiService? apiService}) : _api = apiService ?? ApiService();
  final ApiService _api;
  Future<void> delete(String password) => _api.deleteAccount(password);
}
