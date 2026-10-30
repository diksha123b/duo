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

  Future<Invite> createInvite(Relationship relationship, {FamilyRole? iAm, String? label}) async {
    final res = await _api.post('/invites', body: _relationshipBody(relationship, iAm, label));
    return Invite.fromJson(res['invite'] as Map<String, dynamic>);
  }

  Future<void> setRelationship(Relationship relationship, {FamilyRole? iAm, String? label}) async {
    await _api.patch('/pair', body: _relationshipBody(relationship, iAm, label));
    ref.invalidateSelf();
  }

  static Map<String, dynamic> _relationshipBody(Relationship r, FamilyRole? iAm, String? label) => {
    'relationship': r.wire,
    'label': ?label,
    if (r == Relationship.parentChild && iAm != null) 'iAm': iAm == FamilyRole.parent ? 'PARENT' : 'CHILD',
  };

  Future<void> join(String code) async {
    await _api.post('/invites/join', body: {'code': code});
    await ref.read(authProvider.notifier).reload();
  }

  Future<void> unpair() async {
    await _api.delete('/pair');
    await ref.read(authProvider.notifier).reload();
  }
}
