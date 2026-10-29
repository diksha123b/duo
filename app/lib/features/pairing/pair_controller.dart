import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../auth/auth_controller.dart';

final pairProvider = AsyncNotifierProvider<PairController, PairInfo?>(PairController.new);

class PairController extends AsyncNotifier<PairInfo?> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<PairInfo?> build() async {
    // Refetch whenever the signed-in user's pair changes.
    final pairId = ref.watch(authProvider.select((a) => a.value?.pairId));
    if (pairId == null) return null;
    final pair = (await _api.get('/pair'))['pair'] as Map<String, dynamic>?;
    return pair == null ? null : PairInfo.fromJson(pair);
  }

  Future<Invite> createInvite() async =>
      Invite.fromJson((await _api.post('/invites'))['invite'] as Map<String, dynamic>);

  Future<void> join(String code) async {
    await _api.post('/invites/join', body: {'code': code});
    await ref.read(authProvider.notifier).reload();
  }

  Future<void> unpair() async {
    await _api.delete('/pair');
    await ref.read(authProvider.notifier).reload();
  }
}
