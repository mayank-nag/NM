import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'connection_service.dart';
import 'theme_provider.dart';

class PairingScreen extends StatefulWidget {
  final ConnectionService connectionService;
  final VoidCallback onPaired;

  const PairingScreen({
    super.key,
    required this.connectionService,
    required this.onPaired,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeController = TextEditingController();
  String? _generatedCode;
  String? _error;
  bool _isConnecting = false;
  late final TextEditingController _serverController;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final url = await widget.connectionService.getServerUrl();
    _serverController.text = url;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  void _generateCode() {
    setState(() {
      _generatedCode = ConnectionService.generateRoomCode();
      _error = null;
    });
  }

  Future<void> _connectWithCode(String code) async {
    if (code.trim().isEmpty) {
      setState(() => _error = 'Enter a room code');
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    await widget.connectionService.setServerUrl(_serverController.text.trim());

    final sub = widget.connectionService.status.listen((status) {
      if (status == ConnectionStatus.connected ||
          status == ConnectionStatus.partnerOnline) {
        widget.onPaired();
      } else if (status == ConnectionStatus.disconnected && _isConnecting) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _error = 'Could not connect. Check your server URL and try again.';
          });
        }
      }
    });

    await widget.connectionService.connect(code.trim().toUpperCase());

    await Future.delayed(const Duration(seconds: 5));
    if (_isConnecting && mounted) {
      sub.cancel();
      if (widget.connectionService.currentStatus == ConnectionStatus.connected ||
          widget.connectionService.currentStatus == ConnectionStatus.partnerOnline) {
        widget.onPaired();
      } else {
        setState(() {
          _isConnecting = false;
          _error = 'Connection timed out. Check your server URL.';
        });
      }
    } else {
      sub.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Text(
                'NM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: c.textPrimary,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Private Messenger',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: c.textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 64),

              // Server URL
              Text(
                'SERVER',
                style: TextStyle(
                  fontSize: 11,
                  color: c.textMuted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serverController,
                style: TextStyle(color: c.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'ws://your-server:3000',
                  hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: c.inputBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 32),

              // Option 1: Generate code
              Text(
                'CREATE A ROOM',
                style: TextStyle(
                  fontSize: 11,
                  color: c.textMuted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isConnecting ? null : _generateCode,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.divider),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Generate Room Code',
                  style: TextStyle(color: c.textPrimary, fontSize: 15),
                ),
              ),

              if (_generatedCode != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.divider),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _generatedCode!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _generatedCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Code copied!'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            icon: Icon(Icons.copy, size: 16, color: c.textMuted),
                            label: Text('Copy', style: TextStyle(color: c.textMuted)),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _isConnecting
                                ? null
                                : () => _connectWithCode(_generatedCode!),
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: c.divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(color: c.textMuted)),
                  ),
                  Expanded(child: Divider(color: c.divider)),
                ],
              ),

              const SizedBox(height: 40),

              // Option 2: Enter code
              Text(
                'JOIN A ROOM',
                style: TextStyle(
                  fontSize: 11,
                  color: c.textMuted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 8,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'ENTER CODE',
                  hintStyle: TextStyle(
                    color: c.textMuted.withValues(alpha: 0.5),
                    fontSize: 20,
                    letterSpacing: 6,
                  ),
                  filled: true,
                  fillColor: c.inputBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isConnecting
                    ? null
                    : () => _connectWithCode(_codeController.text),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      )
                    : const Text(
                        'Join Room',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.statusDisconnected, fontSize: 13),
                ),
              ],

              const SizedBox(height: 48),
              Text(
                'Share the room code with your partner.\nBoth of you connect with the same code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
