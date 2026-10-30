import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import 'token_store.dart';

/// Every failure the UI sees: a stable [code] from the API (or NETWORK /
/// UNKNOWN locally) plus a message that's safe to show.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

final apiProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStoreProvider)));

class ApiClient {
  ApiClient(this.tokens, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: AppConfig.apiUrl)) {
    _dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 15);
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _attachToken, onError: _refreshOn401));
  }

  final TokenStore tokens;
  final Dio _dio;
  Completer<bool>? _refreshing;

  /// Called when the session can't be refreshed, so the app can sign out.
  void Function()? onSessionExpired;

  Future<Map<String, dynamic>> get(String path) => _send(() => _dio.get(path));

  Future<Map<String, dynamic>> post(String path, {Object? body, Map<String, String>? headers}) => _send(
    () => _dio.post(
      path,
      data: body ?? {},
      options: Options(headers: headers),
    ),
  );

  Future<Map<String, dynamic>> patch(String path, {Object? body}) => _send(() => _dio.patch(path, data: body));

  Future<void> delete(String path) => _send(() => _dio.delete(path));

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : <String, dynamic>{};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  void _attachToken(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokens.accessToken;
    if (token != null && !options.path.startsWith('/auth/')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // Access tokens are short-lived. On a 401, refresh once (shared by every
  // request that failed at the same time) and replay the original request.
  Future<void> _refreshOn401(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final isRetry = opts.extra['retried'] == true;
    if (err.response?.statusCode != 401 || opts.path.startsWith('/auth/') || isRetry) {
      return handler.next(err);
    }
    if (!await refreshSession()) return handler.next(err);

    opts.extra['retried'] = true;
    opts.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    try {
      handler.resolve(await _dio.fetch(opts));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share one request.
  Future<bool> refreshSession() async {
    if (_refreshing != null) return _refreshing!.future;
    final completer = _refreshing = Completer<bool>();
    try {
      final refresh = await tokens.readRefreshToken();
      if (refresh == null) {
        completer.complete(false);
      } else {
        final res = await _dio.post('/auth/refresh', data: {'refreshToken': refresh});
        await tokens.save(res.data['tokens'] as Map<String, dynamic>);
        completer.complete(true);
      }
    } on DioException catch (e) {
      // Only a definite rejection ends the session; a network blip shouldn't.
      if (e.response?.statusCode == 401) {
        await tokens.clear();
        onSessionExpired?.call();
      }
      completer.complete(false);
    } finally {
      _refreshing = null;
    }
    return completer.future;
  }

  static ApiException _toApiException(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(err['code'] as String, err['message'] as String, statusCode: e.response?.statusCode);
    }
    return switch (e.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => const ApiException(
        'NETWORK',
        "Can't reach Duo. Check your connection and try again.",
      ),
      _ => ApiException('UNKNOWN', 'Something went wrong (${e.response?.statusCode ?? e.type.name})'),
    };
  }
}
