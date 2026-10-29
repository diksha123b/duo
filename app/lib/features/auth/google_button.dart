import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config.dart';
import 'auth_controller.dart';
import 'google_button_stub.dart' if (dart.library.js_interop) 'google_button_web.dart' as platform;

/// Google sign-in for both targets. Android calls `authenticate()`; web must
/// use Google's own rendered button, which reports through the same
/// `authenticationEvents` stream. Either way the ID token goes to our API.
class GoogleButton extends ConsumerStatefulWidget {
  const GoogleButton({super.key, required this.onError});

  final void Function(Object error) onError;

  @override
  ConsumerState<GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends ConsumerState<GoogleButton> {
  static Future<void>? _init;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init ??= GoogleSignIn.instance.initialize(
      clientId: platform.isWeb ? AppConfig.googleWebClientId : null,
      serverClientId: platform.isWeb ? null : AppConfig.googleWebClientId,
    );
    _init!.then((_) {
      if (!mounted) return;
      _sub = GoogleSignIn.instance.authenticationEvents.listen(_onEvent, onError: widget.onError);
      setState(() => _ready = true);
    }, onError: widget.onError);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;
    final idToken = event.user.authentication.idToken;
    if (idToken == null) return widget.onError('Google did not return an ID token');
    try {
      await ref.read(authProvider.notifier).signInWithGoogle(idToken);
    } catch (e) {
      widget.onError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox(height: 52, child: Center(child: CircularProgressIndicator()));
    if (platform.isWeb) return platform.renderWebButton();
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
      label: const Text('Continue with Google'),
      onPressed: () async {
        try {
          await GoogleSignIn.instance.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code != GoogleSignInExceptionCode.canceled) widget.onError(e.description ?? 'Google sign-in failed');
        }
      },
    );
  }
}
