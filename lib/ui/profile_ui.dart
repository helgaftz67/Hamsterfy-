import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../profiles.dart';
import 'theme.dart';

Color profileColor(Profile p) => HSLColor.fromAHSL(1, (p.name.hashCode % 360).abs().toDouble(), .5, .55).toColor();

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.profile, {super.key, this.size = 36});
  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: profileColor(profile),
      child: Text(
        profile.name.isEmpty ? '?' : profile.name.characters.first.toUpperCase(),
        style: TextStyle(color: kBg, fontWeight: FontWeight.w800, fontSize: size * .45),
      ),
    );
  }
}

/// First screen: pick who is listening, or create an account.
class ProfileGate extends StatelessWidget {
  const ProfileGate({super.key});

  Future<void> _enter(BuildContext context, Profile p) async {
    if (p.hasPin) {
      final ok = await showDialog<bool>(context: context, builder: (_) => _PinDialog(p));
      if (ok != true) return;
    }
    await profiles.select(p);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: profiles,
          builder: (context, _) {
            if (profiles.list.isEmpty) return const _CreateForm(first: true);
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                const Text('Кто слушает?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('У каждого аккаунта своя медиатека, избранное и рекомендации.',
                    style: TextStyle(color: kMuted)),
                const SizedBox(height: 24),
                for (final p in profiles.list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: ProfileAvatar(p, size: 44),
                        title: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        trailing: Icon(p.hasPin ? Icons.lock_outline : Icons.chevron_right, color: kMuted),
                        onTap: () => _enter(context, p),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(appBar: AppBar(), body: const SafeArea(child: _CreateForm(first: false))),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Создать аккаунт'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CreateForm extends StatefulWidget {
  const _CreateForm({required this.first});
  final bool first;

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    await profiles.create(_name.text, pin: _pin.text);
    if (!widget.first && nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, widget.first ? 48 : 8, 24, 24),
        children: [
          Text(widget.first ? 'Добро пожаловать в Hamsterfy' : 'Новый аккаунт',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Аккаунт хранится только на этом телефоне. Почта и интернет не нужны.',
              style: TextStyle(color: kMuted)),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: const InputDecoration(labelText: 'Имя', border: OutlineInputBorder()),
            validator: (v) {
              final name = (v ?? '').trim();
              if (name.isEmpty) return 'Введите имя';
              if (profiles.list.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
                return 'Такой аккаунт уже есть. Выберите другое имя';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'ПИН-код, 4 цифры (необязательно)',
              helperText: 'Защищает вход в аккаунт. Восстановить забытый ПИН нельзя.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.isEmpty || v.length == 4) ? null : 'Нужно ровно 4 цифры или пустое поле',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Создать аккаунт')),
          ),
        ],
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog(this.profile);
  final Profile profile;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _check() {
    if (profiles.checkPin(widget.profile, _pin.text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Неверный ПИН-код. Попробуйте ещё раз');
      _pin.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('ПИН-код для «${widget.profile.name}»'),
      content: TextField(
        controller: _pin,
        autofocus: true,
        keyboardType: TextInputType.number,
        obscureText: true,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(errorText: _error, border: const OutlineInputBorder()),
        onSubmitted: (_) => _check(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: _check, child: const Text('Войти')),
      ],
    );
  }
}

/// Account sheet opened from the avatar on the home screen.
void showAccountSheet(BuildContext context) {
  final p = profiles.current!;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: kSurface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ProfileAvatar(p, size: 44),
            title: Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            subtitle: Text('Треков: ${library.tracks.length} · в избранном: ${library.favorites.length}'),
          ),
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('Кэш музыки'),
            subtitle: Text(library.autoCache
                ? 'Занято ${formatSize(library.cacheBytes)} из ${formatSize(library.cacheLimitMb * 1024 * 1024)}'
                : 'Выключен'),
            onTap: () {
              Navigator.pop(sheet);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CachePage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.switch_account_outlined),
            title: const Text('Сменить аккаунт'),
            onTap: () {
              Navigator.pop(sheet);
              profiles.signOut();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: kAmber),
            title: const Text('Удалить аккаунт'),
            onTap: () async {
              Navigator.pop(sheet);
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('Удалить аккаунт «${p.name}»?'),
                  content: const Text('Медиатека, избранное и скачанные треки этого аккаунта удалятся с телефона. Вернуть их нельзя.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                  ],
                ),
              );
              if (ok == true) await profiles.delete(p);
            },
          ),
        ],
      ),
    ),
  );
}

String formatSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} ГБ';
  return '${(bytes / (1024 * 1024)).round()} МБ';
}

/// Settings of the listening cache for the current account.
class CachePage extends StatelessWidget {
  const CachePage({super.key});

  static const _limitsGb = [1, 2, 5, 10, 20];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Кэш музыки')),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final limit = library.cacheLimitMb * 1024 * 1024;
          final used = library.cacheBytes;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Треки из каталога сохраняются на телефон, когда вы их слушаете, и потом играют без интернета. '
                'Когда кэш заполнится, первыми удалятся треки, которые вы слушали реже всего. '
                'Избранное удаляется в последнюю очередь.',
                style: TextStyle(color: kMuted),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Сохранять прослушанное'),
                value: library.autoCache,
                onChanged: (v) => library.setCache(enabled: v),
              ),
              const SizedBox(height: 8),
              Text('Занято ${formatSize(used)} из ${formatSize(limit)} · треков: ${library.cached.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: (used / limit).clamp(0, 1).toDouble(), minHeight: 8),
              ),
              const SizedBox(height: 24),
              const Text('Лимит', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final gb in _limitsGb)
                    ChoiceChip(
                      label: Text('$gb ГБ'),
                      selected: library.cacheLimitMb == gb * 1024,
                      onSelected: (_) async {
                        final over = library.overLimit(gb * 1024 * 1024 * 1024).length;
                        if (over > 0) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: Text('Уменьшить кэш до $gb ГБ?'),
                              content: Text('Чтобы уложиться в лимит, с телефона удалится треков: $over. Послушать их снова можно будет через интернет.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Уменьшить')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                        }
                        await library.setCache(limitMb: gb * 1024);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: library.cached.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Очистить кэш?'),
                            content: Text('С телефона удалится треков: ${library.cached.length}. Скачанные вручную и ваши файлы останутся.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Очистить')),
                            ],
                          ),
                        );
                        if (ok == true) await library.clearCache();
                      },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Очистить кэш'),
              ),
            ],
          );
        },
      ),
    );
  }
}
