import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../my_server.dart';
import '../profiles.dart';
import 'aurora.dart';
import 'hamsters.dart';
import 'theme.dart';

Color profileColor(Profile p) => HSLColor.fromAHSL(1, (p.name.hashCode % 360).abs().toDouble(), .5, .55).toColor();

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.profile, {super.key, this.size = 36});
  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final picture = profile.avatar;
    final color = profileColor(profile);
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, HSLColor.fromColor(color).withLightness(.38).toColor()],
        ),
      ),
      child: Text(
        profile.name.isEmpty ? '?' : profile.name.characters.first.toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .44),
      ),
    );
    return ClipOval(
      child: picture == null
          ? letter
          : Image.file(File(picture),
              width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => letter),
    );
  }
}

/// First screen: a welcome for a new install, or "who is listening" when
/// accounts already exist.
class ProfileGate extends StatelessWidget {
  const ProfileGate({super.key});

  Future<void> _enter(BuildContext context, Profile p) async {
    if (p.hasPin) {
      final ok = await showDialog<bool>(context: context, builder: (_) => _PinDialog(p));
      if (ok != true) return;
    }
    await profiles.select(p);
  }

  void _create(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAccountPage()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBackground(fadeTo: kBg),
          SafeArea(
            child: ListenableBuilder(
              listenable: profiles,
              builder: (context, _) => profiles.list.isEmpty ? _welcome(context) : _picker(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(flex: 6, child: HamsterScene()),
          const Text('Музыка,\nкоторая ваша',
              style: TextStyle(fontSize: 44, height: 1.02, fontWeight: FontWeight.w800, letterSpacing: -1.6)),
          const SizedBox(height: 14),
          const Text('Ищите треки, собирайте плейлисты и слушайте без интернета. Два хомяка присмотрят за коллекцией.',
              style: TextStyle(color: kMuted, fontSize: 16, height: 1.4, fontWeight: FontWeight.w500)),
          const SizedBox(height: 22),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Perk(Icons.search_rounded, 'Поиск'),
              _Perk(Icons.graphic_eq_rounded, 'Моя волна'),
              _Perk(Icons.download_done_rounded, 'Офлайн'),
              _Perk(Icons.sensors_rounded, 'Радио'),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              onPressed: () => _create(context),
              child: const Text('Начать', style: TextStyle(fontSize: 17)),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Без почты и паролей. Аккаунт живёт на этом устройстве.',
                textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _picker(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        const Align(alignment: Alignment.centerLeft, child: _Mascot(size: 84)),
        const SizedBox(height: 26),
        const Text('Кто слушает?',
            style: TextStyle(fontSize: 40, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -1.4)),
        const SizedBox(height: 8),
        const Text('У каждого своя медиатека, избранное и рекомендации.',
            style: TextStyle(color: kMuted, fontSize: 15.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 30),
        Wrap(
          spacing: 18,
          runSpacing: 22,
          children: [
            for (final p in profiles.list)
              _Person(
                label: p.name,
                onTap: () => _enter(context, p),
                badge: p.hasPin ? Icons.lock_rounded : null,
                child: ProfileAvatar(p, size: 92),
              ),
            _Person(
              label: 'Добавить',
              onTap: () => _create(context),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .08),
                  border: Border.all(color: Colors.white.withValues(alpha: .28), width: 1.5),
                ),
                child: const Icon(Icons.add_rounded, size: 36, color: kInk),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The app icon, gently bobbing.
class _Mascot extends StatefulWidget {
  const _Mascot({required this.size});
  final double size;

  @override
  State<_Mascot> createState() => _MascotState();
}

class _MascotState extends State<_Mascot> with SingleTickerProviderStateMixin {
  late final _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _bob,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_bob.value);
        return Transform.translate(
          offset: Offset(0, -s * .05 * t),
          child: Transform.rotate(angle: (t - .5) * .07, child: child),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s * .24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: s * .22, offset: Offset(0, s * .1))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(s * .24),
          child: Image.asset('assets/brand/icon.png', width: s, height: s),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: kAccent),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.label, required this.onTap, required this.child, this.badge});
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 104,
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  child,
                  if (badge != null)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: kBg, shape: BoxShape.circle, border: Border.all(color: kSunken)),
                        child: Icon(badge, size: 14, color: kMuted),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Registration: a name, an optional four-digit PIN, and a live preview of
/// the avatar the account will get.
class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pinFocus = FocusNode();
  bool _usePin = false;
  bool _busy = false;
  String? _nameError;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _nameError = null));
    _pin.addListener(() => setState(() => _pinError = null));
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    String? nameError, pinError;
    if (name.isEmpty) {
      nameError = 'Введите имя';
    } else if (profiles.list.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      nameError = 'Такой аккаунт уже есть. Выберите другое имя';
    }
    if (_usePin && _pin.text.length != 4) pinError = 'Введите все 4 цифры или выключите ПИН-код';
    if (nameError != null || pinError != null) {
      setState(() {
        _nameError = nameError;
        _pinError = pinError;
      });
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    await profiles.create(name, pin: _usePin ? _pin.text : null);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final preview = Profile(id: 'preview', name: name);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBackground(fadeTo: kBg, fadeFrom: .12),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Назад',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: name.isEmpty
                        ? Container(
                            key: const ValueKey('empty'),
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: .10),
                              border: Border.all(color: Colors.white.withValues(alpha: .28), width: 1.5),
                            ),
                            child: const Icon(Icons.person_rounded, size: 52, color: kInk),
                          )
                        : ProfileAvatar(preview, key: ValueKey(profileColor(preview)), size: 112),
                  ),
                ),
                const SizedBox(height: 26),
                const Text('Как вас зовут?',
                    style: TextStyle(fontSize: 38, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -1.3)),
                const SizedBox(height: 8),
                const Text('Имя увидят только те, кто берёт в руки это устройство.',
                    style: TextStyle(color: kMuted, fontSize: 15.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 24,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: 'Имя',
                    hintStyle: TextStyle(color: kMuted.withValues(alpha: .7), fontWeight: FontWeight.w600),
                    errorText: _nameError,
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: .07),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: kAccent, width: 1.5)),
                  ),
                  onSubmitted: (_) => _usePin ? _pinFocus.requestFocus() : _submit(),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 6, 10, 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .07), borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Защитить ПИН-кодом', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Спросим только при выборе аккаунта'),
                        value: _usePin,
                        onChanged: (v) {
                          setState(() => _usePin = v);
                          if (v) _pinFocus.requestFocus();
                        },
                      ),
                      if (_usePin) ...[
                        _PinBoxes(controller: _pin, focusNode: _pinFocus, onDone: _submit),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 10, 10),
                          child: Text(_pinError ?? 'Восстановить забытый ПИН-код нельзя.',
                              style: TextStyle(
                                  color: _pinError == null ? kMuted : const Color(0xFFFF7A8A), fontSize: 12.5)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                  onPressed: _busy ? null : _submit,
                  child: const Text('Создать аккаунт', style: TextStyle(fontSize: 17)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four digit cells backed by one hidden text field.
class _PinBoxes extends StatelessWidget {
  const _PinBoxes({required this.controller, required this.focusNode, required this.onDone});
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: focusNode.requestFocus,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // The real input: invisible, but it owns the keyboard and the value.
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 58,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', labelText: 'ПИН-код, 4 цифры'),
                onSubmitted: (_) => onDone(),
              ),
            ),
          ),
          IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, focusNode]),
              builder: (context, _) {
                final typed = controller.text.length;
                return Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        width: 52,
                        height: 58,
                        margin: const EdgeInsets.only(right: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: kBg.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: focusNode.hasFocus && i == typed.clamp(0, 3) ? kAccent : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: i < typed
                            ? Container(
                                width: 12, height: 12, decoration: const BoxDecoration(color: kInk, shape: BoxShape.circle))
                            : null,
                      ),
                  ],
                );
              },
            ),
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

/// The user's own page: picture, listening numbers and account actions.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _changePicture(BuildContext context, Profile p) async {
    final action = p.avatar == null
        ? 'pick'
        : await showModalBottomSheet<String>(
            context: context,
            backgroundColor: kSurface,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('Выбрать другое фото'),
                      onTap: () => Navigator.pop(sheet, 'pick')),
                  ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Убрать фото'),
                      onTap: () => Navigator.pop(sheet, 'remove')),
                ],
              ),
            ),
          );
    try {
      if (action == 'pick') await profiles.pickAvatar(p);
      if (action == 'remove') await profiles.removeAvatar(p);
    } catch (_) {
      if (context.mounted) toast(context, 'Не удалось поставить фото. Попробуйте выбрать другое.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListenableBuilder(
        listenable: Listenable.merge([profiles, library]),
        builder: (context, _) {
          final p = profiles.current;
          if (p == null) return const SizedBox.shrink();
          final tracks = library.songs.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Center(
                child: Semantics(
                  button: true,
                  label: 'Изменить фото профиля',
                  child: GestureDetector(
                    onTap: () => _changePicture(context, p),
                    child: Stack(
                      children: [
                        ProfileAvatar(p, size: 132),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: kInk,
                              shape: BoxShape.circle,
                              border: Border.all(color: kBg, width: 3),
                            ),
                            child: const Icon(Icons.photo_camera_rounded, size: 18, color: kBg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(p.name, textAlign: TextAlign.center, style: kTitle),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    _Stat('$tracks', 'треков'),
                    _Stat('${library.favorites.length}', 'в избранном'),
                    _Stat('${library.playlists.length}', 'плейлистов'),
                    _Stat('${library.totalPlays}', 'прослушиваний'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _Row(
                icon: Icons.cached_rounded,
                title: 'Кэш музыки',
                subtitle: library.autoCache
                    ? 'Занято ${formatSize(library.cacheBytes)} из ${formatSize(library.cacheLimitMb * 1024 * 1024)}'
                    : 'Выключен',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CachePage())),
              ),
              _Row(
                icon: Icons.dns_outlined,
                title: 'Мой сервер',
                subtitle: library.hasServer ? library.serverUrl : 'Не подключён',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ServerPage())),
              ),
              if (library.hidden.isNotEmpty)
                _Row(
                  icon: Icons.visibility_off_outlined,
                  title: 'Скрытые треки: ${library.hidden.length}',
                  subtitle: 'Вернуть в медиатеку всё, что вы из неё убрали',
                  onTap: () async {
                    library.unhideAll();
                    final n = await library.scanDevice(ask: false);
                    if (context.mounted) toast(context, n > 0 ? 'Возвращено треков: $n' : 'Скрытые треки вернутся при следующем поиске музыки');
                  },
                ),
              _Row(
                icon: Icons.switch_account_outlined,
                title: 'Сменить аккаунт',
                onTap: () {
                  Navigator.pop(context);
                  profiles.signOut();
                },
              ),
              _Row(
                icon: Icons.delete_outline_rounded,
                title: 'Удалить аккаунт',
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text('Удалить аккаунт «${p.name}»?'),
                      content: const Text(
                          'Медиатека, избранное и скачанные треки этого аккаунта удалятся из приложения. Вернуть их нельзя. Ваши файлы в памяти телефона останутся.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    if (context.mounted) Navigator.pop(context);
                    await profiles.delete(p);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, required this.onTap, this.danger = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFFF7A8A) : kInk;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: danger ? null : const Icon(Icons.chevron_right_rounded, color: kMuted),
      onTap: onTap,
    );
  }
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
                'Треки, которые вы не слушали 30 дней, удаляются сами. Если кэш всё равно заполнится, '
                'первыми уйдут те, что вы слушали реже всего; избранное — в последнюю очередь.',
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

/// Connection to the user's own Hamsterfy server.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  late final _url = TextEditingController(text: library.serverUrl);
  late final _token = TextEditingController(text: library.serverToken);
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_url.text.trim().isEmpty) {
      setState(() {
        _ok = false;
        _result = 'Введите адрес сервера, например 192.168.1.5:8787';
      });
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final tracks = await MyServer(_url.text, token: _token.text).health();
      library.setServer(MyServer.normalize(_url.text), _token.text);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _result = 'Сервер подключён. Треков в его папке: $tracks. Ищите через него во вкладке «Поиск».';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _result = e is ServerProblem ? e.message : 'Не удалось подключиться: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: kSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Мой сервер')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'Сервер Hamsterfy запускается на вашем компьютере и раздаёт музыку из папки на все ваши устройства. '
            'Адрес он показывает при запуске.',
            style: TextStyle(color: kMuted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: field('Адрес сервера', '192.168.1.5:8787'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            autocorrect: false,
            decoration: field('Ключ доступа (если задан)', 'то, что указано в --token'),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: Text(_busy ? 'Проверяю…' : 'Подключить'),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 20, color: _ok ? const Color(0xFF5ED4A8) : const Color(0xFFFF7A8A)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_result!, style: const TextStyle(fontWeight: FontWeight.w500))),
                ],
              ),
            ),
          if (library.hasServer) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () {
                library.setServer('', '');
                _url.clear();
                _token.clear();
                setState(() {
                  _ok = true;
                  _result = 'Сервер отключён. Сохранённая в приложении музыка осталась.';
                });
              },
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Отключить сервер'),
            ),
          ],
        ],
      ),
    );
  }
}
