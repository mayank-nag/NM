import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionService {
  static const _roomKey = 'room_id';
  static const _serverUrlKey = 'server_url';
  static const _defaultServer = 'wss://nm-okym.onrender.com';

  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  bool _disposed = false;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<ConnectionStatus> get status => _statusController.stream;

  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  ConnectionStatus get currentStatus => _currentStatus;

  String? _roomId;
  String? get roomId => _roomId;

  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectDelay = 30; // seconds

  static String generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<String?> getSavedRoomId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roomKey);
  }

  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? _defaultServer;
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  Future<void> connect(String roomId) async {
    if (_disposed) return;

    // Cancel any pending reconnect
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();

    // Close existing channel cleanly
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _roomId = roomId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomKey, roomId);

    final serverUrl = await getServerUrl();
    _updateStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse('$serverUrl?room=$roomId');
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection with a timeout (Render cold starts can take ~30s)
      await _channel!.ready.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw TimeoutException('Connection timed out waiting for server');
        },
      );

      _reconnectAttempt = 0; // Reset on successful connection
      _updateStatus(ConnectionStatus.connected);

      // Start keep-alive pings to prevent Render from sleeping
      _startPingTimer();

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            if (msg['type'] == 'partner_connected') {
              _updateStatus(ConnectionStatus.partnerOnline);
            } else if (msg['type'] == 'partner_disconnected') {
              _updateStatus(ConnectionStatus.connected);
            } else if (msg['type'] == 'pong') {
              // Keep-alive response, ignore
            } else {
              _messageController.add(msg);
            }
          } catch (_) {}
        },
        onError: (error) {
          _pingTimer?.cancel();
          _updateStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        onDone: () {
          _pingTimer?.cancel();
          _updateStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _pingTimer?.cancel();
      _updateStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  /// Send periodic pings to keep the WebSocket alive
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      }
    });
  }

  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  Future<void> unpair() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roomKey);
    _roomId = null;
    disconnect();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _updateStatus(ConnectionStatus.disconnected);
  }

  void _updateStatus(ConnectionStatus s) {
    _currentStatus = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _roomId == null) return;
    _reconnectTimer?.cancel();

    // Exponential backoff: 1s, 2s, 4s, 8s, ... capped at _maxReconnectDelay
    final delay = min(
      pow(2, _reconnectAttempt).toInt(),
      _maxReconnectDelay,
    );
    _reconnectAttempt++;

    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (_roomId != null && !_disposed) {
        connect(_roomId!);
      }
    });
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _messageController.close();
    _statusController.close();
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  partnerOnline,
}