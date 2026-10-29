import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/states.dart';
import '../auth/auth_controller.dart';

const _suggested = [
  'movies', 'music', 'cricket', 'football', 'travel', 'food', 'cooking', 'books', 'anime', 'gaming',
  'fitness', 'tech', 'coding', 'art', 'photography', 'fashion', 'science', 'history', 'pets', 'bollywood',
];

const minInterests = 3;
const maxInterests = 10;

/// Picks the interests the AI uses to personalise games. Used for first-run
/// onboarding and, with [editing], from the home menu.
class InterestsScreen extends ConsumerStatefulWidget {
  const InterestsScreen({super.key, this.editing = false});

  final bool editing;

  @override
  ConsumerState<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends ConsumerState<InterestsScreen> {
  late final Set<String> _selected = {...?ref.read(authProvider).value?.profile.interests};
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggle(String interest) {
    setState(() {
      if (!_selected.remove(interest) && _selected.length < maxInterests) _selected.add(interest);
    });
  }

  void _addCustom() {
    final value = _custom.text.trim().toLowerCase();
    if (value.isEmpty || value.length > 30 || _selected.length >= maxInterests) return;
    setState(() => _selected.add(value));
    _custom.clear();
  }

  Future<void> _save() async {
    try {
      await ref.read(authProvider.notifier).updateProfile(interests: _selected.toList());
      if (widget.editing && mounted) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(authProvider).value?.profile.displayName ?? '';
    final all = {..._suggested, ..._selected}.toList();
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.editing ? 'Your interests' : 'Hi $name 👋')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('What are you into?', style: text.headlineSmall),
                const SizedBox(height: 4),
                Text('Pick $minInterests–$maxInterests. Your daily games are built around both of your interests.'),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in all)
                      FilterChip(label: Text(i), selected: _selected.contains(i), onSelected: (_) => _toggle(i)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _custom,
                  maxLength: 30,
                  decoration: InputDecoration(
                    labelText: 'Add your own',
                    suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addCustom),
                  ),
                  onSubmitted: (_) => _addCustom(),
                ),
                const SizedBox(height: 12),
                Text('${_selected.length} selected', style: text.bodySmall),
                const SizedBox(height: 12),
                BusyButton(
                  label: widget.editing ? 'Save' : 'Continue',
                  onPressed: _selected.length >= minInterests ? _save : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
