import 'dart:js_interop';

import 'push_platform.dart';

@JS('duoPush.supported')
external bool _supported();
@JS('duoPush.permission')
external String _permission();
@JS('duoPush.subscribe')
external JSPromise<JSString> _subscribe(String publicKey);
@JS('duoPush.current')
external JSPromise<JSString> _current();
@JS('duoPush.unsubscribe')
external JSPromise<JSString> _unsubscribe();

/// Uses the bridge in web/duo_push.js.
PushPlatform createPushPlatform() => _WebPush();

String? _nonEmpty(String s) => s.isEmpty ? null : s;

class _WebPush implements PushPlatform {
  @override
  bool get supported {
    try {
      return _supported();
    } catch (_) {
      return false;
    }
  }

  @override
  String get permission => supported ? _permission() : 'denied';

  @override
  Future<String?> subscribe(String publicKey) async => _nonEmpty((await _subscribe(publicKey).toDart).toDart);

  @override
  Future<String?> currentEndpoint() async => supported ? _nonEmpty((await _current().toDart).toDart) : null;

  @override
  Future<String?> unsubscribe() async => supported ? _nonEmpty((await _unsubscribe().toDart).toDart) : null;
}
