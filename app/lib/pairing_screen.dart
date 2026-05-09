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
  final _passphraseController = TextEditingController();
  String? _generatedCode;
  String? _statusMessage;
  bool _isConnecting = false;
  bool _isError = false;
  bool _passphraseVisible = false;
  late final TextEditingController _serverController;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController();
    _loadServerUrl();
    _loadSavedPassphrase();
  }

  Future<void> _loadServerUrl() async {
    final url = await widget.connectionService.getServerUrl();
    _serverController.text = url;
  }

  Future<void> _loadSavedPassphrase() async {
    final passphrase = widget.connectionService.crypto.passphrase;
    if (passphrase != null) {
      _passphraseController.text = passphrase;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _serverController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  void _generateCode() {
    setState(() {
      _generatedCode = ConnectionService.generateRoomCode();
      _statusMessage = null;
      _isError = false;
    });
  }

  Future<void> _connectWithCode(String code) async {
    if (code.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Enter a room code';
        _isError = true;
      });
      return;
    }

    final passphrase = _passphraseController.text.trim();
    if (passphrase.isEmpty) {
      setState(() {
        _statusMessage = 'Enter a shared passphrase for encryption';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = null;
      _isError = false;
    });

    // Configure encryption with the passphrase
    await widget.connectionService.crypto.configure(passphrase);

    await widget.connectionService.setServerUrl(_serverController.text.trim());
    await widget.connectionService.connect(code.trim().toUpperCase());

    // Wait for connection with periodic status updates
    // Render free-tier cold starts can take 30-50s
    const maxWait = 90;
    for (var i = 0; i < maxWait; i++) {
      await Future.delayed(const Duration(seconds: 1));

      final s = widget.connectionService.currentStatus;
      if (s == ConnectionStatus.connected || s == ConnectionStatus.partnerOnline) {
        if (mounted) widget.onPaired();
        return;
      }

      if (mounted) {
        final remaining = maxWait - i;
        String msg;
        if (remaining > 60) {
          msg = 'Waking up server... this may take a moment';
        } else if (remaining > 30) {
          msg = 'Server is starting up... ${remaining}s';
        } else {
          msg = 'Still connecting... ${remaining}s';
        }
        setState(() {
          _statusMessage = msg;
          _isError = false;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Connection timed out. Check your server URL and internet connection.';
        _isError = true;
      });
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
              const SizedBox(height: 48),

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
                  hintText: 'wss://your-server.com',
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
              const SizedBox(height: 20),

              // Shared Passphrase (E2E encryption)
              Text(
                'SHARED SECRET',
                style: TextStyle(
                  fontSize: 11,
                  color: c.textMuted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passphraseController,
                obscureText: !_passphraseVisible,
                style: TextStyle(color: c.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'A secret only you two know',
                  hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: c.inputBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passphraseVisible ? Icons.visibility_off : Icons.visibility,
                      color: c.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _passphraseVisible = !_passphraseVisible),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 12, color: c.accent.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'End-to-end encrypted. Both must use the same secret.',
                      style: TextStyle(color: c.accent.withValues(alpha: 0.7), fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

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

              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isError ? c.statusDisconnected : c.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],

              const SizedBox(height: 48),
              Text(
                'Share the room code with your partner.\nBoth of you connect with the same code & secret.',
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