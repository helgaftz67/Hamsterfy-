import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamsterfy/server/link_import.dart';
import 'package:hamsterfy/server/music_server.dart';

void main() {
  test('only open licences are recognised', () {
    expect(LinkImporter.permits('Creative Commons Attribution license (reuse allowed)'), isTrue);
    expect(LinkImporter.permits('CC-BY 4.0'), isTrue);
    expect(LinkImporter.permits('Public Domain'), isTrue);
    expect(LinkImporter.permits('Standard YouTube License'), isFalse);
    expect(LinkImporter.permits(null), isFalse);
  });

  test('refuses closed recordings before downloading; downloads open ones', () async {
    final dir = Directory.systemTemp.createTempSync('hamsterfy_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    final calls = <List<String>>[];
    String? license;
    final importer = LinkImporter(run: (tool, args) async {
      calls.add(args);
      return ProcessResult(1, 0, args.first == '--dump-json' ? jsonEncode({'title': 'Demo', 'license': license}) : '', '');
    });

    await expectLater(importer.import('not a link', dir),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'bad_link')));
    expect(calls, isEmpty);

    await expectLater(importer.import('https://example.com/v', dir),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'license_not_open')));
    expect(calls.length, 1); // looked at the details, downloaded nothing

    license = 'Creative Commons Attribution license (reuse allowed)';
    expect(await importer.import('https://example.com/v', dir), 'Demo');
    expect(calls.last, containsAll(['-x', 'https://example.com/v']));
  });

  test('a missing tool is reported plainly', () async {
    final importer = LinkImporter(run: (tool, args) => throw const ProcessException('yt-dlp', []));
    await expectLater(importer.import('https://example.com/v', Directory.systemTemp),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'tool_missing')));
  });
}
