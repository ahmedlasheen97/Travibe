part of 'profile_cubit.dart';

sealed class ProfileState {}

final class ProfileInitial extends ProfileState {}

final class ProfileLoading extends ProfileState {}

final class ProfileLoaded extends ProfileState {
  ProfileLoaded(this.profile, {this.refreshing = false, this.error});
  final ProfileModel profile;
  final bool refreshing;
  final ApiError? error;
}

final class ProfileUnavailable extends ProfileState {}

final class ProfileFailure extends ProfileState {
  ProfileFailure(this.error);
  final ApiError error;
  String get errorMessage => error.message;
}
