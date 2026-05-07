import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'connection_service.dart';
import 'pairing_screen.dart';
import 'chat_screen.dart';
import 'theme_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const NMApp(),
    ),
  );
}

class NMApp extends StatefulWidget {
  const NMApp({super.key});

  @override
  State<NMApp> createState() => _NMAppState();
}

class _NMAppState extends State<NMApp> {
  final _connectionService = ConnectionService();
  bool _loading = true;
  bool _isPaired = false;

  // Shared content pending delivery to chat screen
  List<SharedMediaFile>? _pendingSharedFiles;

  StreamSubscription? _sharedMediaSub;

  @override
  void initState() {
    super.initState();
    _checkPairing();
    _setupShareListeners();
  }

  Future<void> _checkPairing() async {
    final savedRoom = await _connectionService.getSavedRoomId();
    if (savedRoom != null) {
      _isPaired = true;
      _connectionService.connect(savedRoom);
    }
    setState(() => _loading = false);
  }

  void _setupShareListeners() {
    // Handle shared content when app is already running
    _sharedMediaSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        setState(() => _pendingSharedFiles = files);
      }
    });

    // Handle shared content when app was closed and opened via share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        setState(() => _pendingSharedFiles = files);
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  @override
  void dispose() {
    _sharedMediaSub?.cancel();
    _connectionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'NM',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.themeData,
      home: _loading
          ? Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  color: themeProvider.colors.textMuted,
                ),
              ),
            )
          : _isPaired
              ? ChatScreen(
                  connectionService: _connectionService,
                  pendingSharedFiles: _pendingSharedFiles,
                  onSharedContentConsumed: () {
                    setState(() => _pendingSharedFiles = null);
                  },
                )
              : PairingScreen(
                  connectionService: _connectionService,
                  onPaired: () {
                    setState(() => _isPaired = true);
                  },
                ),
    );
  }
}
