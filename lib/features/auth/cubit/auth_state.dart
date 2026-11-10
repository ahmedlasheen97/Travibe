part of 'auth_cubit.dart';

@immutable
sealed class AuthState {}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

final class AuthSuccess extends AuthState {
  AuthSuccess({this.response});
  final AuthResponseModel? response;
}

final class AuthFailure extends AuthState {
  final String errorMessage;
  AuthFailure(this.errorMessage);
}
