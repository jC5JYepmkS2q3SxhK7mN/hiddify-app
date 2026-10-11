import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/text_utils.dart';

/// Builds a zip in memory. A name ending in `/` becomes a folder.
Uint8List zipOf(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, text) {
    archive.add(name.endsWith('/') ? ArchiveFile.directory(name) : ArchiveFile.string(name, text));
  });
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('readZipTexts', () {
    test('reads every file, named without its folders and extension', () {
      final texts = readZipTexts(
        zipOf({'export/': '', 'export/a.conf': 'one\ntwo', 'export/sub/b.txt': 'three', 'c': 'four'}),
      );
      expect(texts, [(name: 'a', text: 'one\ntwo'), (name: 'b', text: 'three'), (name: 'c', text: 'four')]);
    });

    test('skips macOS metadata but keeps names that only start with a dot', () {
      final texts = readZipTexts(
        zipOf({
          'export/. 🇳🇱 Free-1.conf': 'kept',
          '__MACOSX/export/._. 🇳🇱 Free-1.conf': 'junk',
          'export/._other.conf': 'junk',
          'export/.hidden': 'kept too',
        }),
      );
      expect(texts, [(name: '. 🇳🇱 Free-1', text: 'kept'), (name: '.hidden', text: 'kept too')]);
    });

    test('skips files over 256 KB', () {
      final texts = readZipTexts(zipOf({'big.conf': 'x' * (256 * 1024 + 1), 'small.conf': 'ok'}));
      expect(texts, [(name: 'small', text: 'ok')]);
    });

    test('drops a UTF-8 byte order mark', () {
      final archive = Archive()..add(ArchiveFile.bytes('a.conf', [0xEF, 0xBB, 0xBF, ...utf8.encode('text')]));
      expect(readZipTexts(ZipEncoder().encodeBytes(archive)), [(name: 'a', text: 'text')]);
    });

    test('returns an empty list when the bytes are not a zip', () {
      expect(readZipTexts(Uint8List.fromList(utf8.encode('[Interface]\nAddress = 10.0.0.2/32'))), isEmpty);
    });
  });
}
