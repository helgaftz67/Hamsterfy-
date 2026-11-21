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
