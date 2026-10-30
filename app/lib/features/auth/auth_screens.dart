import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
import '../../core/models.dart';
import '../../ui/buddies.dart';
import '../../ui/game_style.dart';
import '../../ui/marquee.dart';
import '../../ui/states.dart';
import '../../ui/sticker.dart';
import '../../ui/theme.dart';
import 'auth_controller.dart';
import 'google_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await ref.read(authProvider.notifier).login(email: _email.text.trim(), password: _password.text);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'welcome back!',
      subtitle: 'your duo is waiting. probably.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EmailField(controller: _email),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) _ErrorText(_error!),
            const SizedBox(height: 20),
            BusyButton(label: 'sign in', onPressed: _submit),
            if (AppConfig.googleEnabled) ...[
              const _OrDivider(),
              GoogleButton(onError: (e) => setState(() => _error = e.toString())),
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: () => context.go('/register'), child: const Text('new here? make an account')),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await ref
          .read(authProvider.notifier)
          .register(email: _email.text.trim(), password: _password.text, displayName: _name.text.trim());
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'make an account',
      subtitle: 'then invite your person. any person.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.givenName],
              decoration: const InputDecoration(labelText: 'Your name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'What should your partner call you?' : null,
            ),
            const SizedBox(height: 12),
            _EmailField(controller: _email),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Password', helperText: 'At least 8 characters'),
              validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) _ErrorText(_error!),
            const SizedBox(height: 20),
            BusyButton(label: 'let’s go', onPressed: _submit),
            if (AppConfig.googleEnabled) ...[
              const _OrDivider(),
              GoogleButton(onError: (e) => setState(() => _error = e.toString())),
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: () => context.go('/login'), child: const Text('already have one? sign in')),
          ],
        ),
      ),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Text('duo', style: text.displaySmall),
                          const Spacer(),
                          const Buddies(size: 64, mood: BuddyMood.celebrating),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text('one tiny game a day,\nfor you and your person.', style: text.headlineMedium),
                    ),
                    const SizedBox(height: 18),
                    const _GameMarquee(),
                    const SizedBox(height: 14),
                    const _Banter(),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Sticker(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(title, style: text.headlineSmall),
                            const SizedBox(height: 2),
                            Text(subtitle, style: text.bodyMedium),
                            const SizedBox(height: 18),
                            child,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '6 daily games · live chess, ludo & more · free',
                      style: text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The game shelf, drifting past like a shop window.
class _GameMarquee extends StatelessWidget {
  const _GameMarquee();

  static const _extras = [
    ('♟️', 'chess', DuoColors.mint),
    ('🎲', 'ludo', DuoColors.sunflower),
    ('🔤', 'word tiles', DuoColors.grape),
    ('🔴', 'four in a row', DuoColors.bubblegum),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget card(String emoji, String name, Color color, int i) => SizedBox(
      width: 118,
      child: Sticker(
        color: color,
        depth: 4,
        tilt: i.isEven ? -3 : 3,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(height: 6),
            Text(name, style: text.labelLarge?.copyWith(color: DuoColors.ink), maxLines: 2),
          ],
        ),
      ),
    );
    final daily = [
      for (final t in GameType.values) (GameStyle.of(t).emoji, GameStyle.of(t).name, GameStyle.of(t).color),
    ];
    final all = [...daily, ..._extras];
    return Marquee(height: 140, children: [for (final (i, g) in all.indexed) card(g.$1, g.$2, g.$3, i)]);
  }
}

/// A few chat bubbles from different kinds of duos.
class _Banter extends StatelessWidget {
  const _Banter();

  @override
  Widget build(BuildContext context) {
    Widget bubble(String who, String line, Color color, {required bool right, double tilt = 0}) => Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Sticker(
          color: color,
          depth: 3,
          radius: 18,
          tilt: tilt,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$who  ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: line),
              ],
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DuoColors.ink),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          bubble('aarav', 'you picked pineapple?? i can’t look at you 😭', DuoColors.tangerine, right: false, tilt: -1),
          const SizedBox(height: 6),
          bubble('mum', 'who taught you chess like that 👀', DuoColors.sky, right: true, tilt: 1),
          const SizedBox(height: 6),
          bubble('zoya', '9 day streak. don’t you dare break it', DuoColors.bubblegum, right: false, tilt: -0.5),
        ],
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      decoration: const InputDecoration(labelText: 'Email'),
      validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider()),
          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
          Expanded(child: Divider()),
        ],
      ),
    );
  }
}
