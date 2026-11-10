import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travibe/core/datasource/localdata/preferences_manager.dart';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/media/media_upload_service.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/chats/screens/conversation_screen.dart';
import 'package:travibe/features/chats/widgets/chat_selected_media_tray.dart';
import 'chat_fakes.dart';
import 'chat_interactions_test.dart' show png;

class UploadFake extends MediaUploadService {
  int uploads = 0;
  @override
  Future<int> upload({
    required String filename,
    required String contentType,
    required Uint8List bytes,
    required bool Function() isActive,
    required CancelToken cancelToken,
    required void Function(MediaUploadStage) onStage,
    void Function(int, int)? onProgress,
  }) async {
    uploads++;
    onStage(MediaUploadStage.uploading);
    onProgress?.call(bytes.length, bytes.length);
    return 100 + uploads;
  }

  @override
  void close() {}
}

class MediaRepositoryFake extends FakeChatRepository
    implements ChatOperationsRepository {
  MediaRepositoryFake() {
    capabilities = const ChatCapabilities(
      list: true,
      messages: true,
      sendText: true,
      attachments: true,
    );
    messageItems = [];
  }
  bool failSecond = true, recordBeforeFailure = false;
  final sent = <int>[];
  @override
  Future<ChatMessage> sendMedia(
    String id, {
    required ChatMessageKind kind,
    required int mediaId,
    String? caption,
    int? durationMs,
    int? posterMediaId,
    String? replyToId,
  }) async {
    sent.add(mediaId);
    final message = ChatMessage(
      id: '${sent.length}',
      senderId: 'self',
      kind: kind,
      text: caption ?? '',
      mediaId: '$mediaId',
      conversationId: id,
    );
    if (sent.length == 2 && failSecond) {
      if (recordBeforeFailure) messageItems.add(message);
      throw ApiError(message: 'Unconfirmed', statusCode: 503);
    }
    messageItems.add(message);
    return message;
  }

  @override
  Future<ChatPage<ChatMessage>> messageChanges(
    String id, {
    String? afterId,
    DateTime? updatedSince,
    String? continuation,
  }) async => ChatPage([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PreferencesManager().init();
    await PreferencesManager().saveToken('fixture');
  });
  for (final recorded in [false, true]) {
    testWidgets(
      'ordered multi-image send preserves uncertain item and reconciles before retry; stored=$recorded',
      (tester) async {
        final repo = MediaRepositoryFake()..recordBeforeFailure = recorded;
        final upload = UploadFake();
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: ConversationScreen(
                conversation: conversation,
                currentUserId: 'self',
                repository: repo,
                mediaUploader: upload,
                pickAttachments: (_) async => [
                  XFile.fromData(png, name: 'one.png'),
                  XFile.fromData(png, name: 'two.png'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Attachments'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gallery'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatSelectedMediaTray), findsOneWidget);
        expect(repo.sent, isEmpty);
        expect(upload.uploads, 0);
        await tester.tap(find.byTooltip('Send attachments'));
        await tester.pumpAndSettle();
        expect(repo.sent, [101, 102]);
        expect(upload.uploads, 2);
        expect(
          tester
              .widget<ChatSelectedMediaTray>(find.byType(ChatSelectedMediaTray))
              .items,
          hasLength(1),
        );
        await tester.tap(find.text('Failed to send. Tap to retry.'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (!recorded) {
          expect(find.text('Delivery unknown'), findsOneWidget);
          expect(repo.sent, [101, 102]);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.byType(ChatSelectedMediaTray), findsOneWidget);
          await tester.tap(find.text('Failed to send. Tap to retry.'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.text('Confirm'));
        }
        await tester.pumpAndSettle();
        expect(upload.uploads, 2);
        expect(repo.sent, recorded ? [101, 102] : [101, 102, 102]);
        expect(find.byType(ChatSelectedMediaTray), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
