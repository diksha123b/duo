import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../ui/states.dart';
import '../auth/auth_controller.dart';
import 'pair_controller.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _code = TextEditingController();
  Invite? _invite;
  String? _inviteError;
  String? _joinError;
  bool _creating = false;
  Timer? _poll;

  @override
  void dispose() {
    _code.dispose();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _createInvite() async {
    setState(() {
      _creating = true;
      _inviteError = null;
    });
    try {
      final invite = await ref.read(pairProvider.notifier).createInvite();
      setState(() => _invite = invite);
      // The socket tells us when the partner joins; polling is a backstop
      // for flaky connections.
      _poll ??= Timer.periodic(const Duration(seconds: 8), (_) {
        ref.read(authProvider.notifier).reload().catchError((_) {});
      });
    } catch (e) {
      setState(() => _inviteError = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _joinError = 'Codes are 6 characters');
      return;
    }
    setState(() => _joinError = null);
    try {
      await ref.read(pairProvider.notifier).join(code);
    } catch (e) {
      setState(() => _joinError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair up'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Duo is for two', style: text.headlineSmall),
                const SizedBox(height: 4),
                const Text('Share a code with your partner, or enter theirs.'),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _invite == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Invite your partner', style: text.titleMedium),
                              const SizedBox(height: 12),
                              if (_inviteError != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(_inviteError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                ),
                              FilledButton.tonal(
                                onPressed: _creating ? null : _createInvite,
                                child: _creating
                                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('Get an invite code'),
                              ),
                            ],
                          )
                        : _InviteCode(invite: _invite!),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Have a code?', style: text.titleMedium),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 7,
                          style: text.headlineSmall?.copyWith(letterSpacing: 6),
                          decoration: InputDecoration(hintText: 'ABC123', errorText: _joinError, counterText: ''),
                          onSubmitted: (_) => _join(),
                        ),
                        const SizedBox(height: 12),
                        BusyButton(label: 'Join', onPressed: _join),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteCode extends StatelessWidget {
  const _InviteCode({required this.invite});

  final Invite invite;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hours = invite.expiresAt.difference(DateTime.now()).inHours;
    return Column(
      children: [
        Text('Your code', style: text.titleMedium),
        const SizedBox(height: 8),
        SelectableText(
          invite.code,
          style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 8),
        ),
        Text('Expires in ${hours < 1 ? 'under an hour' : '$hours hours'}', style: text.bodySmall),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy invite message'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: 'Play Duo with me! My code is ${invite.code}'));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
          },
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Waiting for your partner to join…'),
          ],
        ),
      ],
    );
  }
}
