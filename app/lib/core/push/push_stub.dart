import 'push_platform.dart';

/// Not a browser: push isn't available (native push would need Firebase).
PushPlatform createPushPlatform() => _NoPush();

class _NoPush implements PushPlatform {
  @override
  bool get supported => false;
  @override
  String get permission => 'denied';
  @override
  Future<String?> subscribe(String publicKey) async => null;
  @override
  Future<String?> currentEndpoint() async => null;
  @override
  Future<String?> unsubscribe() async => null;
}
