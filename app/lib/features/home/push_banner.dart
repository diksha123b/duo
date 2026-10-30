import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_controller.dart';
import '../../ui/states.dart';
import '../../ui/sticker.dart';
import '../../ui/theme.dart';

/// Hidden for the rest of the session once dismissed.
final pushBannerDismissedProvider = NotifierProvider<_Dismissed, bool>(_Dismissed.new);

class _Dismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

/// "Turn on notifications" nudge, shown until this browser is subscribed.
class PushBanner extends ConsumerWidget {
  const PushBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final push = ref.watch(pushProvider).value;
    if (ref.watch(pushBannerDismissedProvider) || push == null || !push.available || push.subscribed || push.blocked) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Sticker(
        color: DuoColors.grape,
        depth: 3,
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        child: Row(
          children: [
            const Text('🔔', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'get a nudge when it’s your turn or the results are in',
                style: TextStyle(color: DuoColors.ink, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            StickerButton(
              label: 'turn on',
              color: DuoColors.sunflower,
              onPressed: () async {
                try {
                  final ok = await ref.read(pushProvider.notifier).enable();
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('notifications are blocked: allow them in your browser settings')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
            ),
            IconButton(
              tooltip: 'Not now',
              icon: const Icon(Icons.close_rounded, color: DuoColors.ink),
              onPressed: () => ref.read(pushBannerDismissedProvider.notifier).dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
