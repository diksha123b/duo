import 'package:duo/core/api.dart';
import 'package:duo/core/models.dart';
import 'package:duo/core/push/push_controller.dart';
import 'package:duo/core/push/push_platform.dart';
import 'package:duo/features/auth/auth_controller.dart';
import 'package:duo/features/home/push_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlatform implements PushPlatform {
  String? endpoint;
  @override
  bool get supported => true;
  @override
  String get permission => endpoint == null ? 'default' : 'granted';
  @override
  Future<String?> subscribe(String publicKey) async {
    endpoint = 'https://push.example/abc';
    return '{"endpoint":"$endpoint","keys":{"p256dh":"p","auth":"a"}}';
  }

  @override
  Future<String?> currentEndpoint() async => endpoint;
  @override
  Future<String?> unsubscribe() async => endpoint;
}

class _FakeApi implements ApiClient {
  final posts = <String, Object?>{};
  @override
  Future<Map<String, dynamic>> get(String path) async => {'key': 'BPublicKey'};
  @override
  Future<Map<String, dynamic>> post(String path, {Object? body, Map<String, String>? headers}) async {
    posts[path] = body;
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOut extends AuthController {
  @override
  Future<Me?> build() async => null;
}

void main() {
  testWidgets('turning on notifications registers this browser and hides the banner', (tester) async {
    final api = _FakeApi();
    final platform = _FakePlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_SignedOut.new),
          apiProvider.overrideWithValue(api),
          pushPlatformProvider.overrideWithValue(platform),
        ],
        child: const MaterialApp(home: Scaffold(body: PushBanner())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('turn on'), findsOneWidget);

    await tester.tap(find.text('turn on'));
    await tester.pumpAndSettle();
    expect(api.posts['/push/subscribe'], {
      'endpoint': 'https://push.example/abc',
      'keys': {'p256dh': 'p', 'auth': 'a'},
    });
    expect(find.text('turn on'), findsNothing);
  });
}
