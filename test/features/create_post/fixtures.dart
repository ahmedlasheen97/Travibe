import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/features/create_post/data/create_post_repo.dart';
import 'package:travibe/features/create_post/data/create_post_request.dart';
import 'package:travibe/features/home/data/post_model.dart';

Map<String, dynamic> postJson({
  String content = 'A trip',
  String visibility = 'public',
}) => {
  'id': 42,
  'type': 'text',
  'user_id': 7,
  'user': {'id': 7, 'name': 'Sara', 'username': 'sara'},
  'content': content,
  'visibility': visibility,
  'media': [],
};

class MemoryCreatePostRepo extends CreatePostRepo {
  final requests = <CreatePostRequest>[];
  ApiError? error;
  Completer<PostModel>? gate;

  @override
  Future<PostAuthorModel> getCurrentAuthor() async =>
      PostAuthorModel.fromJson({'id': 7, 'name': 'Sara', 'username': 'sara'});

  @override
  Future<PostModel> create(CreatePostRequest request) async {
    requests.add(request);
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return PostModel.fromJson(
      postJson(
        content: request.content.trim(),
        visibility: request.visibility.name,
      ),
    );
  }
}
