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

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _code = TextEditingController();
  Relationship? _relationship;
  FamilyRole? _role;
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

  bool get _ready => _relationship != null && (_relationship != Relationship.parentChild || _role != null);

  Future<void> _createInvite() async {
    setState(() => _inviteError = null);
    try {
      final invite = await ref.read(pairProvider.notifier).createInvite(_relationship!, iAm: _role);
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
    final style = _relationship == null ? null : RelationshipStyle.of(_relationship!);

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
                  'your partner, your bestie, your sibling, your mum. anyone you’d play with every day.',
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
                        Text('they are my…', style: text.labelLarge),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final r in Relationship.values)
                              ChoiceChip(
                                label: Text('${RelationshipStyle.of(r).emoji} ${_choiceLabel(r)}'),
                                selected: _relationship == r,
                                onSelected: (_) => setState(() {
                                  _relationship = r;
                                  if (r != Relationship.parentChild) _role = null;
                                }),
                              ),
                          ],
                        ),
                        if (_relationship == Relationship.parentChild) ...[
                          const SizedBox(height: 14),
                          Text('and I’m the…', style: text.labelLarge),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('👩 parent'),
                                selected: _role == FamilyRole.parent,
                                onSelected: (_) => setState(() => _role = FamilyRole.parent),
                              ),
                              ChoiceChip(
                                label: const Text('🧒 kid'),
                                selected: _role == FamilyRole.child,
                                onSelected: (_) => setState(() => _role = FamilyRole.child),
                              ),
                            ],
                          ),
                        ],
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
                        _InviteCode(invite: _invite!, style: style!),
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

  static String _choiceLabel(Relationship r) => switch (r) {
    Relationship.partners => 'partner',
    Relationship.bestFriends => 'best friend',
    Relationship.friends => 'friend',
    Relationship.siblings => 'sibling',
    Relationship.parentChild => 'parent / kid',
  };
}

class _InviteCode extends StatelessWidget {
  const _InviteCode({required this.invite, required this.style});

  final Invite invite;
  final RelationshipStyle style;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hours = invite.expiresAt.difference(DateTime.now()).inHours;
    return Column(
      children: [
        Tag('${style.emoji} ${style.label}', color: style.left),
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
