import 'dart:io';
import 'package:travibe/features/legal/data/legal_documents.dart';

/// Local review artifacts only. Does not publish, upload or contact public URLs.
Future<void> main() async {
  final directory = Directory('docs/legal/drafts');
  await directory.create(recursive: true);
  for (final language in ['en', 'ar']) {
    for (final type in LegalDocumentType.values) {
      final doc = LegalDocuments.get(type, language);
      final text = StringBuffer('# ${doc.title}\n\n')
        ..writeln('> ${doc.reviewNotice}\n')
        ..writeln(doc.lastUpdatedText)
        ..writeln()
        ..writeln(doc.effectiveDateText)
        ..writeln()
        ..writeln('${doc.versionLabel}: ${LegalDocument.contentVersion}\n')
        ..writeln(doc.introduction)
        ..writeln();
      for (final section in doc.sections) {
        text
          ..writeln('## ${section.heading}\n')
          ..writeln(section.body)
          ..writeln();
      }
      final file = File('${directory.path}/${type.name}.$language.md');
      await file.writeAsString(text.toString());
      stdout.writeln(
        'Exported ${file.path} (${LegalDocument.contentVersion}; review required)',
      );
    }
  }
}
