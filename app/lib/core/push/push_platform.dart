/// Browser push, behind a small interface so non-web builds compile.
abstract class PushPlatform {
  bool get supported;

  /// 'granted', 'denied' or 'default' (not asked yet).
  String get permission;

  /// Asks permission and subscribes. Returns the subscription JSON, or null if refused.
  Future<String?> subscribe(String publicKey);

  /// This browser's subscription endpoint, if subscribed.
  Future<String?> currentEndpoint();

  /// Unsubscribes; returns the old endpoint, if any.
  Future<String?> unsubscribe();
}
