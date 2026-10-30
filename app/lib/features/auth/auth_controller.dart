import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/push/push_controller.dart';
import '../../core/token_store.dart';

final authProvider = AsyncNotifierProvider<AuthController, Me?>(AuthController.new);

/// The signed-in user, or null when signed out. Screens call the methods
/// below and catch [ApiException] to show inline errors; the provider's own
/// error state is reserved for "couldn't restore the session" on startup.
class AuthController extends AsyncNotifier<Me?> {
  ApiClient get _api => ref.read(apiProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  @override
  Future<Me?> build() async {
    _api.onSessionExpired = () => state = const AsyncData(null);
    if (await _tokens.readRefreshToken() == null) return null;
    if (!await _api.refreshSession()) {
      // A 401 cleared the token (signed out); anything else was the network.
      if (await _tokens.readRefreshToken() == null) return null;
      throw const ApiException('NETWORK', "Can't reach Duo. Check your connection and try again.");
    }
    return _fetchMe();
  }

  Future<Me> _fetchMe() async => Me.fromJson((await _api.get('/me'))['user'] as Map<String, dynamic>);

  Future<void> _signedIn(Map<String, dynamic> res) async {
    await _tokens.save(res['tokens'] as Map<String, dynamic>);
    state = AsyncData(Me.fromJson(res['user'] as Map<String, dynamic>));
  }

  Future<String> _deviceTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> register({required String email, required String password, required String displayName}) async {
    final res = await _api.post(
      '/auth/register',
      body: {'email': email, 'password': password, 'displayName': displayName, 'timezone': await _deviceTimezone()},
    );
    await _signedIn(res);
  }

  Future<void> login({required String email, required String password}) async {
    await _signedIn(await _api.post('/auth/login', body: {'email': email, 'password': password}));
  }

  Future<void> signInWithGoogle(String idToken) async {
    await _signedIn(await _api.post('/auth/google', body: {'idToken': idToken, 'timezone': await _deviceTimezone()}));
  }

  Future<void> logout() async {
    // Stop "your turn" pushes to this browser before the session goes away.
    try {
      await PushController.forget(_api, ref.read(pushPlatformProvider));
    } catch (_) {}
    final refresh = await _tokens.readRefreshToken();
    if (refresh != null) {
      try {
        await _api.post('/auth/logout', body: {'refreshToken': refresh});
      } on ApiException {
        // Signing out locally still works if the server can't be reached.
      }
    }
    await _tokens.clear();
    state = const AsyncData(null);
  }

  Future<void> updateProfile({List<String>? interests, String? displayName}) async {
    final res = await _api.patch('/me/profile', body: {'interests': ?interests, 'displayName': ?displayName});
    state = AsyncData(Me.fromJson(res['user'] as Map<String, dynamic>));
  }

  /// Re-reads the user, e.g. after pairing changes `pairId`.
  Future<void> reload() async {
    state = AsyncData(await _fetchMe());
  }
}
