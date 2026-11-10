import 'dart:async';
import 'package:travibe/features/likes/data/like_model.dart';
import 'package:travibe/features/likes/data/likes_repo.dart';

class LikeWrite {
  LikeWrite(this.target, this.liked);
  final LikeTarget target;
  final bool liked;
  final result = Completer<LikeValue>();
}

class PendingLikesRepo extends LikesRepo {
  final List<LikeWrite> writes = [];
  @override
  Future<LikeValue> setLiked(LikeTarget target, bool liked) {
    final call = LikeWrite(target, liked);
    writes.add(call);
    return call.result.future;
  }
}

class StateLessLikesRepo extends LikesRepo {
  final read = Completer<LikeValue>();
  int writes = 0;
  int reads = 0;
  @override
  Future<LikeValue?> setLiked(LikeTarget target, bool liked) async {
    writes++;
    return null;
  }

  @override
  Future<LikeValue> getState(LikeTarget target) {
    reads++;
    return read.future;
  }
}

Future<void> flushLikes() => Future<void>.delayed(Duration.zero);
