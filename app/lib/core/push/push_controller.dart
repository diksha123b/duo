import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../api.dart';
import 'push_platform.dart';
import 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart';

final pushPlatformProvider = Provider<PushPlatform>((ref) => createPushPlatform());

class PushState {
  const PushState({required this.available, required this.permission, required this.subscribed});

  /// The browser supports push and the server has it turned on.
  final bool available;
  final String permission;
  final bool subscribed;

  bool get blocked => permission == 'denied';
}

final pushProvider = AsyncNotifierProvider<PushController, PushState>(PushController.new);

/// "Your turn!" notifications for this browser.
class PushController extends AsyncNotifier<PushState> {
  PushPlatform get _platform => ref.read(pushPlatformProvider);
  ApiClient get _api => ref.read(apiProvider);
  String? _key;

  @override
  Future<PushState> build() async {
    ref.watch(authProvider.select((a) => a.value?.id));
    if (!_platform.supported) return const PushState(available: false, permission: 'denied', subscribed: false);
    _key = (await _api.get('/push/key'))['key'] as String?;
    return PushState(
      available: _key != null,
      permission: _platform.permission,
      subscribed: _key != null && await _platform.currentEndpoint() != null,
    );
  }

  /// Asks the browser for permission (call from a tap) and registers this device.
  Future<bool> enable() async {
    final key = _key;
    if (key == null) return false;
    final json = await _platform.subscribe(key);
    if (json == null) {
      state = AsyncData(PushState(available: true, permission: _platform.permission, subscribed: false));
      return false;
    }
    final sub = jsonDecode(json) as Map<String, dynamic>;
    await _api.post('/push/subscribe', body: {'endpoint': sub['endpoint'], 'keys': sub['keys']});
    state = const AsyncData(PushState(available: true, permission: 'granted', subscribed: true));
    return true;
  }

  Future<void> disable() async {
    await forget(_api, _platform);
    state = AsyncData(PushState(available: _key != null, permission: _platform.permission, subscribed: false));
  }

  /// Stops pushes to this browser. Used on sign-out so a shared computer
  /// doesn't get the next person's notifications.
  static Future<void> forget(ApiClient api, PushPlatform platform) async {
    final endpoint = await platform.unsubscribe();
    if (endpoint == null) return;
    try {
      await api.post('/push/unsubscribe', body: {'endpoint': endpoint});
    } on ApiException {
      // The browser is unsubscribed either way; the server cleans up dead ones.
    }
  }
}
