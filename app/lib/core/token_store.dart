import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore(const FlutterSecureStorage()));

/// The access token lives only in memory; the refresh token is persisted in
/// secure storage (Keystore on Android, encrypted storage on web).
class TokenStore {
  TokenStore(this._storage);

  static const _refreshKey = 'duo.refreshToken';
  final FlutterSecureStorage _storage;
  String? accessToken;

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> save(Map<String, dynamic> tokens) async {
    accessToken = tokens['accessToken'] as String;
    await _storage.write(key: _refreshKey, value: tokens['refreshToken'] as String);
  }

  Future<void> clear() async {
    accessToken = null;
    await _storage.delete(key: _refreshKey);
  }
}
