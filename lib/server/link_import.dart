import 'dart:convert';
import 'dart:io';

import 'music_server.dart';

/// Runs an external program; replaced in tests.
typedef RunTool = Future<ProcessResult> Function(String tool, List<String> args);

/// Brings one recording into the server's folder from a link the owner
/// pasted, and only when its author published it under a licence that
/// allows copying (Creative Commons or public domain). Anything else is
/// refused. It is never used by search.
class LinkImporter {
  LinkImporter({RunTool? run}) : _run = run ?? ((tool, args) => Process.run(tool, args, stdoutEncoding: utf8, stderrEncoding: utf8));
  final RunTool _run;

  /// True for licence notes that permit downloading and keeping a copy.
  static bool permits(String? license) {
    final l = (license ?? '').toLowerCase();
    return l.contains('creative commons') || RegExp(r'\bcc[ -]?(by|0)\b').hasMatch(l) || l.contains('public domain');
  }

  /// Downloads the audio of [link] into [into]; returns the title.
  Future<String> import(String? link, Directory into) async {
    final uri = Uri.tryParse((link ?? '').trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      throw ApiError(400, 'bad_link', 'Нужна полная ссылка на запись, начинающаяся с https://.');
    }
    final url = uri.toString();
    final info = await _tool(['--dump-json', '--no-playlist', '--', url]);
    Map<String, dynamic> meta;
    try {
      meta = jsonDecode(const LineSplitter().convert(info.trim()).first) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError(502, 'import_failed', 'Не удалось прочитать сведения о записи по этой ссылке.');
    }
    final title = (meta['title'] ?? 'запись').toString();
    final license = meta['license']?.toString();
    if (!permits(license)) {
      throw ApiError(
          403,
          'license_not_open',
          'Запись «$title» не отмечена автором как свободная для копирования '
              '(лицензия: ${license == null || license.isEmpty ? 'не указана' : license}). '
              'Импортируются только записи под Creative Commons или в общественном достоянии.');
    }
    await into.create(recursive: true);
    await _tool([
      '-x', '--audio-format', 'mp3', '--no-playlist', '--embed-metadata', //
      '-o', '${into.path}${Platform.pathSeparator}%(title).120B [%(id)s].%(ext)s', '--', url,
    ]);
    return title;
  }

  Future<String> _tool(List<String> args) async {
    final ProcessResult r;
    try {
      r = await _run('yt-dlp', args);
    } on ProcessException {
      throw ApiError(501, 'tool_missing',
          'На компьютере не найдена программа yt-dlp. Установите yt-dlp и ffmpeg и перезапустите сервер.');
    }
    if (r.exitCode != 0) {
      final lines = const LineSplitter().convert(r.stderr.toString().trim());
      throw ApiError(502, 'import_failed', 'yt-dlp не справился: ${lines.isEmpty ? 'код ${r.exitCode}' : lines.last}');
    }
    return r.stdout.toString();
  }
}
