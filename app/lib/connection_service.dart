import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConnectionService {
  static const _roomKey = 'room_id';
  static const _serverUrlKey = 'server_url';
  static const _defaultServer = 'ws://10.0.2.2:3000'; // Android emulator localhost

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

  /// Generate a random 6-character room code
  static String generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Load saved room ID from SharedPreferences
  Future<String?> getSavedRoomId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roomKey);
  }

  /// Get the server URL
  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? _defaultServer;
  }

  /// Save server URL
  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  /// Connect to the relay server with a room code
  Future<void> connect(String roomId) async {
    if (_disposed) return;

    _roomId = roomId;

    // Save room ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomKey, roomId);

    final serverUrl = await getServerUrl();
    _updateStatus(ConnectionStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$serverUrl?room=$roomId'),
      );

      await _channel!.ready;
      _updateStatus(ConnectionStatus.connected);

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;

            if (msg['type'] == 'partner_connected') {
              _updateStatus(ConnectionStatus.partnerOnline);
            } else if (msg['type'] == 'partner_disconnected') {
              _updateStatus(ConnectionStatus.connected); // we're still connected
            } else {
              _messageController.add(msg);
            }
          } catch (_) {}
        },
        onError: (error) {
          _updateStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
        onDone: () {
          _updateStatus(ConnectionStatus.disconnected);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _updateStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  /// Send a message to the relay server
  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  /// Disconnect and clear pairing
  Future<void> unpair() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roomKey);
    _roomId = null;
    disconnect();
  }

  /// Disconnect without clearing pairing
  void disconnect() {
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

  Timer? _reconnectTimer;

  void _scheduleReconnect() {
    if (_disposed || _roomId == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_roomId != null && !_disposed) {
        connect(_roomId!);
      }
    });
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
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
