import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config.dart';
import '../features/auth/auth_controller.dart';
import '../features/game/game_controller.dart';
import '../features/history/history_controller.dart';
import '../features/pairing/pair_controller.dart';
import 'api.dart';
import 'models.dart';
import 'token_store.dart';

class RealtimeState {
  const RealtimeState({this.connected = false, this.partnerPresence = Presence.offline});

  final bool connected;
  final Presence partnerPresence;

  RealtimeState copyWith({bool? connected, Presence? partnerPresence}) => RealtimeState(
        connected: connected ?? this.connected,
        partnerPresence: partnerPresence ?? this.partnerPresence,
      );
}

final realtimeProvider = NotifierProvider<RealtimeController, RealtimeState>(RealtimeController.new);

/// One socket per signed-in user. Pushes presence, partner-submitted and
/// reveal events into the other providers. On every (re)connect the server
/// sends a full "sync", so nothing missed while offline is lost.
class RealtimeController extends Notifier<RealtimeState> {
  io.Socket? _socket;

  @override
  RealtimeState build() {
    final userId = ref.watch(authProvider.select((a) => a.value?.id));
    ref.onDispose(_disconnect);
    if (userId != null) _connect();
    return const RealtimeState();
  }

  void _connect() {
    final tokens = ref.read(tokenStoreProvider);
    final socket = _socket = io.io(
      AppConfig.apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelayMax(10000)
          // A function, so every reconnect sends the current access token.
          .setAuthFn((cb) => cb({'token': tokens.accessToken ?? ''}))
          .build(),
    );

    socket
      ..onConnect((_) => state = state.copyWith(connected: true))
      ..onDisconnect((_) => state = state.copyWith(connected: false))
      ..onConnectError((err) async {
        state = state.copyWith(connected: false);
        // Auth rejections aren't retried by the client, so refresh and reconnect.
        if ('$err'.contains('UNAUTHORIZED') && await ref.read(apiProvider).refreshSession()) {
          socket.connect();
        }
      })
      ..on('sync', (data) {
        final map = data as Map;
        final presence = map['partnerPresence'] as Map?;
        if (presence != null) state = state.copyWith(partnerPresence: _presence(presence['state']));
        final game = map['game'];
        if (game != null) _game.applyServer(Map<String, dynamic>.from(game as Map));
      })
      ..on('presence', (data) => state = state.copyWith(partnerPresence: _presence((data as Map)['state'])))
      ..on('game:partner_submitted', (data) => _game.markPartnerSubmitted((data as Map)['gameId'] as String))
      ..on('game:revealed', (data) {
        _game.applyServer(Map<String, dynamic>.from((data as Map)['game'] as Map));
        // Completing today's game moves the streak and adds a history entry.
        ref.invalidate(pairProvider);
        ref.invalidate(historyProvider);
      })
      ..on('pair:changed', (_) async {
        await ref.read(authProvider.notifier).reload();
        ref.invalidate(pairProvider);
      })
      ..connect();
  }

  TodayGameController get _game => ref.read(todayGameProvider.notifier);

  void setPlaying(bool playing) => _socket?.emit('presence:set', {'state': playing ? 'playing' : 'online'});

  void _disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  static Presence _presence(Object? s) => switch (s) {
        'playing' => Presence.playing,
        'online' => Presence.online,
        _ => Presence.offline,
      };
}
