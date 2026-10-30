import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../ui/relationship_style.dart';

/// A ready-made kind of duo. [tone] drives which questions fit; [pairLabel]
/// is what the pair is called ("cousins"). Grown-up/young pairs name their
/// two roles so we can ask which one you are.
class RelationshipPreset {
  const RelationshipPreset(this.emoji, this.chip, this.pairLabel, this.tone, {this.roles});

  final String emoji;

  /// "they are my… cousin"
  final String chip;

  /// "cousins"
  final String pairLabel;
  final Relationship tone;

  /// (grown-up, young) role names, for the parent & child tone.
  final (String, String)? roles;

  static const all = [
    RelationshipPreset('💞', 'partner', 'partners', Relationship.partners),
    RelationshipPreset('💍', 'spouse', 'married', Relationship.partners),
    RelationshipPreset('✈️', 'long-distance love', 'long-distance', Relationship.partners),
    RelationshipPreset('👯', 'best friend', 'best friends', Relationship.bestFriends),
    RelationshipPreset('🙌', 'friend', 'friends', Relationship.friends),
    RelationshipPreset('🏠', 'roommate', 'roommates', Relationship.friends),
    RelationshipPreset('🎒', 'classmate', 'classmates', Relationship.friends),
    RelationshipPreset('✉️', 'pen pal', 'pen pals', Relationship.friends),
    RelationshipPreset('🧃', 'sibling', 'siblings', Relationship.siblings),
    RelationshipPreset('♊', 'twin', 'twins', Relationship.siblings),
    RelationshipPreset('🌻', 'cousin', 'cousins', Relationship.siblings),
    RelationshipPreset('🫶', 'parent / kid', 'parent & kid', Relationship.parentChild, roles: ('parent', 'kid')),
    RelationshipPreset(
      '👵',
      'grandparent / grandkid',
      'grandparent & grandkid',
      Relationship.parentChild,
      roles: ('grandparent', 'grandkid'),
    ),
    RelationshipPreset(
      '🧸',
      'aunt, uncle / niece, nephew',
      'aunt, uncle & kiddo',
      Relationship.parentChild,
      roles: ('aunt or uncle', 'niece or nephew'),
    ),
    RelationshipPreset('💼', 'coworker', 'coworkers', Relationship.colleagues),
    RelationshipPreset('🧭', 'mentor / mentee', 'mentor & mentee', Relationship.colleagues),
  ];

  static RelationshipPreset? byLabel(String? label) {
    for (final p in all) {
      if (p.pairLabel == label) return p;
    }
    return null;
  }
}

/// What the picker produced.
class RelationshipChoice {
  const RelationshipChoice(this.tone, this.label, {this.role});

  final Relationship tone;
  final String label;
  final FamilyRole? role;

  /// Ready to send when the label is set and, for grown-up/young pairs, a role is picked.
  bool get complete => label.trim().isNotEmpty && (tone != Relationship.parentChild || role != null);
}

/// Emoji + words for a pair, preferring what they call themselves.
(String emoji, String label) describePair(Relationship tone, String? label) {
  final style = RelationshipStyle.of(tone);
  final preset = RelationshipPreset.byLabel(label);
  return (preset?.emoji ?? style.emoji, label ?? style.label);
}

/// Pick a preset or write your own. Calls [onChanged] on every change.
class RelationshipPicker extends StatefulWidget {
  const RelationshipPicker({super.key, required this.onChanged, this.otherName});

  final ValueChanged<RelationshipChoice?> onChanged;

  /// Used in prompts like "Ravi is my…" when known.
  final String? otherName;

  @override
  State<RelationshipPicker> createState() => _RelationshipPickerState();
}

class _RelationshipPickerState extends State<RelationshipPicker> {
  RelationshipPreset? _preset;
  bool _custom = false;
  final _customLabel = TextEditingController();
  Relationship _customTone = Relationship.friends;
  FamilyRole? _role;

  static const _vibes = [
    (Relationship.partners, '💞 romantic'),
    (Relationship.bestFriends, '👯 besties'),
    (Relationship.friends, '🙌 friendly'),
    (Relationship.siblings, '🧃 family'),
    (Relationship.parentChild, '🫶 family with a kid'),
    (Relationship.colleagues, '💼 work'),
  ];

  @override
  void dispose() {
    _customLabel.dispose();
    super.dispose();
  }

  void _emit() {
    final RelationshipChoice? choice;
    if (_custom) {
      choice = RelationshipChoice(_customTone, _customLabel.text.trim(), role: _role);
    } else if (_preset != null) {
      choice = RelationshipChoice(_preset!.tone, _preset!.pairLabel, role: _role);
    } else {
      choice = null;
    }
    widget.onChanged(choice);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tone = _custom ? _customTone : _preset?.tone;
    final roles = _custom ? ('the grown-up', 'the kid') : _preset?.roles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.otherName == null ? 'they are my…' : '${widget.otherName} is my…', style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in RelationshipPreset.all)
              ChoiceChip(
                label: Text('${p.emoji} ${p.chip}'),
                selected: !_custom && _preset == p,
                onSelected: (_) => setState(() {
                  _custom = false;
                  _preset = p;
                  _role = null;
                  _emit();
                }),
              ),
            ChoiceChip(
              label: const Text('✏️ something else'),
              selected: _custom,
              onSelected: (_) => setState(() {
                _custom = true;
                _preset = null;
                _role = null;
                _emit();
              }),
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _customLabel,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: 'what do you call each other?',
              hintText: 'gym buddies, choir mates, neighbours…',
            ),
            onChanged: (_) => _emit(),
          ),
          Text('what’s the vibe?', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (t, label) in _vibes)
                ChoiceChip(
                  label: Text(label),
                  selected: _customTone == t,
                  onSelected: (_) => setState(() {
                    _customTone = t;
                    _role = null;
                    _emit();
                  }),
                ),
            ],
          ),
        ],
        if (tone == Relationship.parentChild && roles != null) ...[
          const SizedBox(height: 14),
          Text('and I’m the…', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('🧑 ${roles.$1}'),
                selected: _role == FamilyRole.parent,
                onSelected: (_) => setState(() {
                  _role = FamilyRole.parent;
                  _emit();
                }),
              ),
              ChoiceChip(
                label: Text('🧒 ${roles.$2}'),
                selected: _role == FamilyRole.child,
                onSelected: (_) => setState(() {
                  _role = FamilyRole.child;
                  _emit();
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
