import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../ui/buddies.dart';
import '../../ui/relationship_style.dart';
import '../../ui/sticker.dart';
import '../../ui/theme.dart';
import '../auth/auth_controller.dart';
import 'pair_controller.dart';
import 'relationship_picker.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _code = TextEditingController();
  RelationshipChoice? _choice;
  Invite? _invite;
  String? _inviteError;
  String? _joinError;
  Timer? _poll;

  @override
  void dispose() {
    _code.dispose();
    _poll?.cancel();
    super.dispose();
  }

  bool get _ready => _choice?.complete ?? false;

  Future<void> _createInvite() async {
    setState(() => _inviteError = null);
    try {
      final invite = await ref
          .read(pairProvider.notifier)
          .createInvite(_choice!.tone, iAm: _choice!.role, label: _choice!.label);
      setState(() => _invite = invite);
      // The socket tells us when they join; polling is a backstop for flaky connections.
      _poll ??= Timer.periodic(const Duration(seconds: 8), (_) {
        ref.read(authProvider.notifier).reload().catchError((_) {});
      });
    } catch (e) {
      setState(() => _inviteError = e.toString());
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _joinError = 'codes are 6 characters');
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
    final style = _choice == null ? null : RelationshipStyle.of(_choice!.tone);

    return Scaffold(
      appBar: AppBar(
        title: const Text('duo'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                Center(
                  child: Buddies(
                    size: 96,
                    mood: _invite == null ? BuddyMood.happy : BuddyMood.waiting,
                    left: style?.left ?? DuoColors.bubblegum,
                    right: style?.right ?? DuoColors.sky,
                  ),
                ),
                const SizedBox(height: 8),
                Text('who’s your duo?', style: text.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  'partner, bestie, cousin, grandma, roommate, coworker… anyone you’d play with every day.',
                  style: text.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Sticker(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('invite someone', style: text.titleLarge),
                      const SizedBox(height: 12),
                      if (_invite == null) ...[
                        RelationshipPicker(onChanged: (c) => setState(() => _choice = c)),
                        if (_inviteError != null) ...[
                          const SizedBox(height: 12),
                          Text(_inviteError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 16),
                        StickerButton(
                          label: 'get an invite code',
                          color: style?.left ?? DuoColors.sunflower,
                          onPressed: _ready ? _createInvite : null,
                        ),
                      ] else
                        _InviteCode(invite: _invite!, tone: _choice!.tone),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Sticker(
                  color: DuoColors.mint,
                  pattern: StickerPattern.dots,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('got a code?', style: text.titleLarge?.copyWith(color: DuoColors.ink)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 7,
                        textAlign: TextAlign.center,
                        style: text.headlineSmall?.copyWith(letterSpacing: 8, color: DuoColors.ink),
                        decoration: InputDecoration(
                          hintText: 'ABC123',
                          errorText: _joinError,
                          counterText: '',
                          fillColor: Colors.white,
                        ),
                        onSubmitted: (_) => _join(),
                      ),
                      const SizedBox(height: 12),
                      StickerButton(label: 'join', color: Colors.white, onPressed: _join),
                    ],
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
  const _InviteCode({required this.invite, required this.tone});

  final Invite invite;
  final Relationship tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hours = invite.expiresAt.difference(DateTime.now()).inHours;
    return Column(
      children: [
        Tag(
          '${describePair(tone, invite.label).$1} ${describePair(tone, invite.label).$2}',
          color: RelationshipStyle.of(tone).left,
        ),
        const SizedBox(height: 12),
        Sticker(
          color: DuoColors.sunflower,
          tilt: -2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: SelectableText(
            invite.code,
            style: text.displaySmall?.copyWith(letterSpacing: 8, color: DuoColors.ink),
          ),
        ),
        const SizedBox(height: 6),
        Text('expires in ${hours < 1 ? 'under an hour' : '$hours hours'}', style: text.bodySmall),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('copy invite message'),
          onPressed: () {
            Clipboard.setData(
              ClipboardData(text: 'Play Duo with me! One tiny game a day for the two of us. My code: ${invite.code}'),
            );
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('copied!')));
          },
        ),
        const SizedBox(height: 12),
        const Text('waiting for them to join…'),
      ],
    );
  }
}
