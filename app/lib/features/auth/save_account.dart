import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/sticker.dart';
import '../../ui/theme.dart';
import 'auth_controller.dart';

/// Nudges a guest to add an email, so they can't lose their streak and pet.
class SaveAccountBanner extends ConsumerWidget {
  const SaveAccountBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).value;
    if (me?.guest != true || me!.demo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Sticker(
        color: DuoColors.mint,
        depth: 3,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Text('💾', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'you’re playing as a guest. save your account to keep your streak and pet on any device',
                style: TextStyle(color: DuoColors.ink, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            StickerButton(label: 'save', color: DuoColors.sunflower, onPressed: () => showSaveAccountSheet(context)),
          ],
        ),
      ),
    );
  }
}

Future<void> showSaveAccountSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _SaveAccountSheet(),
);

class _SaveAccountSheet extends ConsumerStatefulWidget {
  const _SaveAccountSheet();

  @override
  ConsumerState<_SaveAccountSheet> createState() => _SaveAccountSheetState();
}

class _SaveAccountSheetState extends ConsumerState<_SaveAccountSheet> {
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

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      await ref.read(authProvider.notifier).saveAccount(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('saved! sign in with your email on any device ✨')));
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('save your account', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text('everything stays: your duo, streak, pet and history.', style: text.bodyMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'password', helperText: 'at least 8 characters'),
                validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 20),
              StickerButton(label: 'save my account', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signing out of a guest account loses it for good, so ask first.
Future<void> signOut(BuildContext context, WidgetRef ref) async {
  final auth = ref.read(authProvider.notifier);
  final me = ref.read(authProvider).value;
  // Demo accounts are throwaway; only a real guest account is worth saving.
  if (me?.guest != true || me!.demo) return auth.logout();
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('sign out of a guest account?'),
      content: const Text(
        'guest accounts have no email, so once you sign out you can’t get back in. '
        'your duo, streak and pet would be lost.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'out'), child: const Text('sign out anyway')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('save it first')),
      ],
    ),
  );
  if (!context.mounted) return;
  if (choice == 'save') return showSaveAccountSheet(context);
  if (choice == 'out') return auth.logout();
}

/// Demo mode: explains Duo Jr., and offers the real thing.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key, required this.onPlayForReal});

  final Future<void> Function() onPlayForReal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authProvider).value?.demo != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Sticker(
        color: DuoColors.sky,
        depth: 3,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Text('✨', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'practice mode: Duo Jr. plays along (it’s not a real person). try a daily game, the arcade, or pat the pet!',
                style: TextStyle(color: DuoColors.ink, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            StickerButton(label: 'play for real', color: DuoColors.sunflower, onPressed: onPlayForReal),
          ],
        ),
      ),
    );
  }
}
