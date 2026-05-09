import 'dart:async';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'connection_service.dart';
import 'pairing_screen.dart';
import 'chat_screen.dart';
import 'theme_provider.dart';
import 'whiteboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  final _navigatorKey = GlobalKey<NavigatorState>();
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
    _setupWidgetDeepLink();
  }

  Future<void> _checkPairing() async {
    // Load saved encryption passphrase
    await _connectionService.crypto.loadSaved();

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

  /// Handle taps on the home screen widget → open whiteboard directly.
  void _setupWidgetDeepLink() {
    // Check if app was launched via widget tap
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) {
      if (uri != null) _handleWidgetUri(uri);
    });

    // Listen for widget taps while app is running
    HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) _handleWidgetUri(uri);
    });
  }

  void _handleWidgetUri(Uri uri) {
    if (uri.host == 'whiteboard' && _isPaired) {
      // Navigate to whiteboard — wait a frame for navigator to be ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => WhiteboardScreen(connectionService: _connectionService),
          ),
        );
      });
    }
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
      navigatorKey: _navigatorKey,
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
