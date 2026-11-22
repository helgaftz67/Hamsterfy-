import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../server/music_server.dart';
import '../ui/theme.dart';
import 'controller.dart';

const _green = Color(0xFF5ED4A8);
const _red = Color(0xFFFF7A8A);

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  return '${(bytes / 1024).round()} КБ';
}

String formatUptime(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return d.inDays > 0 ? '${d.inDays} д $clock' : clock;
}

/// Desktop control panel for the Hamsterfy server.
class ServerPanel extends StatefulWidget {
  const ServerPanel({super.key, required this.controller});
  final ServerController controller;

  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  EventFilter _filter = EventFilter.all;
  final _scroll = ScrollController();
  int _shown = 0;

  ServerController get c => widget.controller;

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: c.mainAddress));
    if (mounted) _say('Адрес скопирован: ${c.mainAddress}');
  }

  Future<void> _openFolder(Directory dir) async {
    var opened = false;
    try {
      await dir.create(recursive: true);
      opened = await launchUrl(Uri.directory(dir.path));
    } catch (_) {}
    if (!opened && mounted) _say('Не удалось открыть папку. Её путь: ${dir.path}');
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Очистить кэш?'),
        content: Text('С диска удалится сохранённых треков: ${c.cachedTracks}. Ваши файлы в папке хранилища останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Очистить')),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await c.clearCache();
    if (mounted) _say('Кэш очищен. Удалено треков: $removed');
  }

  late final _lifecycle = AppLifecycleListener(
    // Closing the window: stop the server and release the journal file.
    onExitRequested: () async {
      await c.shutdown();
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // start listening
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 900;
              final controls = ListView(
                padding: const EdgeInsets.all(20),
                shrinkWrap: !wide,
                physics: wide ? null : const NeverScrollableScrollPhysics(),
                children: [_header(), const SizedBox(height: 16), _statusCard(), const SizedBox(height: 12), _addressCard(), const SizedBox(height: 12), _counters(), const SizedBox(height: 12), _folders()],
              );
              final journal = Padding(
                padding: EdgeInsets.fromLTRB(wide ? 0 : 20, wide ? 20 : 0, 20, 20),
                child: _journal(),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [SizedBox(width: 440, child: controls), Expanded(child: journal)],
                );
              }
              return ListView(children: [controls, SizedBox(height: 520, child: journal)]);
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset('assets/brand/icon.png', width: 44, height: 44),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hamsterfy Server', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.4)),
              Text('Музыкальный сервер для ваших устройств', style: TextStyle(color: kMuted, fontSize: 13)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Настройки',
          onPressed: () => showDialog<void>(context: context, builder: (_) => _SettingsDialog(controller: c)),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _statusCard() {
    final on = c.running;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: on ? _green : kMuted, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(c.busy ? (on ? 'Останавливается…' : 'Запускается…') : (on ? 'Работает' : 'Остановлен'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: on ? _green : kInk)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _fact('Порт', '${c.port ?? c.settings.port}'),
              const SizedBox(width: 28),
              _fact('Аптайм', on ? formatUptime(c.uptime) : '—'),
              const SizedBox(width: 28),
              _fact('Треков', on ? '${c.libraryTracks}' : '—'),
            ],
          ),
          if (c.problem != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, size: 18, color: _red),
                const SizedBox(width: 8),
                Expanded(child: Text(c.problem!, style: const TextStyle(color: _red, fontSize: 13.5))),
              ],
            ),
            if (c.portBusy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.tonalIcon(
                  onPressed: c.busy ? null : c.startOnFreePort,
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: const Text('Запустить на свободном порту'),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: on || c.busy ? null : c.start,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Запустить'),
              ),
              OutlinedButton.icon(
                onPressed: !on || c.busy ? null : c.stop,
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text('Остановить'),
              ),
              OutlinedButton.icon(
                onPressed: !on || c.busy ? null : c.restart,
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                label: const Text('Перезапустить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      );

  Widget _addressCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Адрес для приложения', style: TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  c.running ? c.mainAddress : 'Появится после запуска',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: c.running ? kInk : kMuted,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.running ? _copy : null,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Копировать'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            c.addresses.length > 1
                ? 'Другие адреса этого компьютера: ${c.addresses.skip(1).join(', ')}'
                : 'Введите его в Hamsterfy: Профиль → «Мой сервер». Телефон должен быть в той же сети.',
            style: const TextStyle(color: kMuted, fontSize: 12.5),
          ),
          if (c.settings.token.trim().isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Доступ закрыт ключом — он задаётся в настройках.', style: TextStyle(color: kMuted, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _counters() {
    Widget tile(String label, String value, {Color? color}) => Expanded(
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color ?? kInk,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('Запросов', '${c.requests}'),
        const SizedBox(width: 10),
        tile('Ошибок', '${c.errorCount}', color: c.errorCount > 0 ? _red : _green),
        const SizedBox(width: 10),
        tile('Кэш на диске', formatBytes(c.cacheBytes)),
      ],
    );
  }

  Widget _folders() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('В кэше треков: ${c.cachedTracks} · лимит ${c.settings.cacheGb.toStringAsFixed(0)} ГБ',
              style: const TextStyle(color: kMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openFolder(c.logsDir),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Папка журналов'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openFolder(c.storageDir),
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Хранилище'),
              ),
              OutlinedButton.icon(
                onPressed: c.running ? () => _importLink(context, c) : null,
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Импорт по ссылке'),
              ),
              OutlinedButton.icon(
                onPressed: c.running ? c.rescan : null,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Перечитать папку'),
              ),
              OutlinedButton.icon(
                onPressed: c.running && c.cachedTracks > 0 ? _clearCache : null,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Очистить кэш'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _journal() {
    final lines = c.visible(_filter);
    // Follow new lines unless the user scrolled up to read.
    if (lines.length != _shown) {
      _shown = lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (pos.maxScrollExtent - pos.pixels < 160) _scroll.jumpTo(pos.maxScrollExtent);
      });
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Журнал событий', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              TextButton(onPressed: c.journal.isEmpty ? null : c.clearJournal, child: const Text('Очистить')),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in EventFilter.values)
                ChoiceChip(
                  label: Text('${f.label} · ${c.visible(f).length}'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Text(
                      c.running
                          ? (_filter == EventFilter.errors ? 'Ошибок нет.' : 'Событий пока нет. Они появятся, когда приложение обратится к серверу.')
                          : 'Запустите сервер, чтобы видеть события.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kMuted),
                    ),
                  )
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      itemCount: lines.length,
                      itemBuilder: (_, i) => _EventLine(lines[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine(this.event);
  final ServerEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final failed = e.kind == 'error' || (e.status ?? 0) >= 500;
    final warn = (e.status ?? 0) >= 400 && !failed;
    final color = failed ? _red : (warn ? kAmber : (e.kind == 'info' ? kAccent : kInk));
    // The app font with fixed-width digits: a monospace face may lack Cyrillic.
    const mono = TextStyle(fontSize: 12.5, height: 1.5, fontFeatures: [FontFeature.tabularFigures()]);
    final time = e.time.toIso8601String().substring(11, 19);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time, style: mono.copyWith(color: kMuted)),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(e.status?.toString() ?? (e.kind == 'error' ? 'ERR' : '·'), style: mono.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: SelectableText(e.text, style: mono.copyWith(color: failed ? _red : kInk))),
          if (e.ms != null) Text('${e.ms} мс', style: mono.copyWith(color: kMuted)),
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.controller});
  final ServerController controller;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _folder = TextEditingController(text: widget.controller.settings.musicFolder);
  late final _port = TextEditingController(text: '${widget.controller.settings.port}');
  late final _token = TextEditingController(text: widget.controller.settings.token);
  late double _cacheGb = widget.controller.settings.cacheGb;
  String? _error;

  @override
  void dispose() {
    _folder.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickDirectory(dialogTitle: 'Папка с музыкой');
    if (picked != null) setState(() => _folder.text = picked.toFilePath());
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim());
    if (_folder.text.trim().isEmpty) {
      setState(() => _error = 'Укажите папку с музыкой.');
      return;
    }
    if (port == null || port < 1024 || port > 65535) {
      setState(() => _error = 'Порт — число от 1024 до 65535, например 8765.');
      return;
    }
    final nav = Navigator.of(context);
    await widget.controller.applySettings(
        ServerSettings(musicFolder: _folder.text.trim(), port: port, token: _token.text.trim(), cacheGb: _cacheGb));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: kSunken,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        );
    return AlertDialog(
      title: const Text('Настройки сервера'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: TextField(controller: _folder, decoration: field('Папка с музыкой (хранилище)'))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pick, child: const Text('Выбрать')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: field('Порт'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _token, decoration: field('Ключ доступа', 'необязательно'))),
              ],
            ),
            const SizedBox(height: 16),
            Text('Лимит кэша: ${_cacheGb.toStringAsFixed(0)} ГБ', style: const TextStyle(fontWeight: FontWeight.w600)),
            Slider(
              min: 1,
              max: 100,
              divisions: 99,
              value: _cacheGb.clamp(1, 100).toDouble(),
              label: '${_cacheGb.toStringAsFixed(0)} ГБ',
              onChanged: (v) => setState(() => _cacheGb = v.roundToDouble()),
            ),
            const Text('Сохранённое, которое не слушали 30 дней, удаляется само. Работающий сервер перезапустится с новыми настройками.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: _red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}


/// Asks for a link and imports it; the server refuses anything that is not
/// openly licensed and the reason is shown here.
Future<void> _importLink(BuildContext context, ServerController c) async {
  final field = TextEditingController();
  String? note;
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('Импорт по ссылке'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Только записи, которые автор выложил под Creative Commons или в общественное достояние. '
                  'Остальные сервер отклонит.'),
              const SizedBox(height: 14),
              TextField(controller: field, autofocus: true, decoration: const InputDecoration(hintText: 'https://…')),
              if (busy) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
              if (note != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(note!)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(d), child: const Text('Закрыть')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    set(() {
                      busy = true;
                      note = null;
                    });
                    final text = await c.importLink(field.text);
                    set(() {
                      busy = false;
                      note = text;
                    });
                  },
            child: const Text('Импортировать'),
          ),
        ],
      ),
    ),
  );
}
