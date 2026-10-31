import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../auth/auth_controller.dart';

final petProvider = AsyncNotifierProvider<PetController, PetInfo>(PetController.new);

class PetController extends AsyncNotifier<PetInfo> {
  ApiClient get _api => ref.read(apiProvider);

  @override
  Future<PetInfo> build() async {
    ref.watch(authProvider.select((a) => a.value?.pairId));
    return _parse(await _api.get('/pet'));
  }

  PetInfo _parse(Map<String, dynamic> res) => PetInfo.fromJson(res['pet'] as Map<String, dynamic>);

  /// Today's pat (+5 XP). Once per person per day.
  Future<void> pat() async => state = AsyncData(_parse(await _api.post('/pet/pat')));

  Future<void> rename(String name) => _update({'name': name});

  Future<void> recolor(String color) => _update({'color': color});

  Future<void> wear(String? outfit) => _update({'outfit': outfit});

  Future<void> _update(Map<String, dynamic> body) async =>
      state = AsyncData(_parse(await _api.patch('/pet', body: body)));

  /// The other person patted or dressed it up.
  void applyServer(Map<String, dynamic> pet) => state = AsyncData(PetInfo.fromJson(pet));
}
