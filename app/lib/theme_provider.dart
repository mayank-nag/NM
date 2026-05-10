import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeKey = 'selected_theme';

/// All available theme packs
enum AppThemePack {
  defaultDark('Default', 'Clean minimal dark'),
  midnight('Midnight', 'Deep black with neon accents'),
  paper('Paper', 'Warm off-white, handwritten feel'),
  forest('Forest', 'Muted greens and earthy tones'),
  retro('Retro', 'Pixel-style, 8-bit color palette'),
  pastel('Pastel', 'Soft pinks and lilacs');

  final String label;
  final String description;
  const AppThemePack(this.label, this.description);
}

class ThemeProvider extends ChangeNotifier {
  AppThemePack _current = AppThemePack.defaultDark;
  AppThemePack get current => _current;

  /// Optional connection service for syncing theme to partner.
  /// Set after construction since Provider creates this before connection is ready.
  dynamic /* ConnectionService */ _connectionService;
  void attachConnectionService(dynamic cs) => _connectionService = cs;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_themeKey);
    if (name != null) {
      _current = AppThemePack.values.firstWhere(
        (t) => t.name == name,
        orElse: () => AppThemePack.defaultDark,
      );
      notifyListeners();
    }
  }

  /// Set theme locally and broadcast to partner.
  Future<void> setTheme(AppThemePack theme) async {
    _current = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);

    // Broadcast to partner
    if (_connectionService != null) {
      try {
        _connectionService.send({
          'type': 'theme_update',
          'theme': theme.name,
        });
      } catch (_) {}
    }
  }

  /// Apply theme from partner sync (no re-broadcast to prevent echo loop).
  Future<void> setThemeFromSync(String themeName) async {
    final theme = AppThemePack.values.firstWhere(
      (t) => t.name == themeName,
      orElse: () => AppThemePack.defaultDark,
    );
    if (theme == _current) return; // no change
    _current = theme;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);
  }

  ThemeData get themeData => _buildTheme(_current);
  AppColors get colors => _buildColors(_current);
}

/// Custom color tokens for non-ThemeData usage (bubbles, status, etc.)
class AppColors {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color meBubble;
  final Color themBubble;
  final Color meText;
  final Color themText;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;
  final Color inputBackground;
  final Color statusOnline;
  final Color statusConnected;
  final Color statusConnecting;
  final Color statusDisconnected;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.meBubble,
    required this.themBubble,
    required this.meText,
    required this.themText,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
    required this.inputBackground,
    this.statusOnline = const Color(0xFF4D96FF),
    this.statusConnected = const Color(0xFF6BCB77),
    this.statusConnecting = const Color(0xFFFFD93D),
    this.statusDisconnected = const Color(0xFFFF6B6B),
  });
}

AppColors _buildColors(AppThemePack pack) {
  switch (pack) {
    case AppThemePack.defaultDark:
      return const AppColors(
        background: Color(0xFF0D0D0D),
        surface: Color(0xFF1A1A1A),
        surfaceLight: Color(0xFF2A2A2A),
        meBubble: Color(0xFF4D96FF),
        themBubble: Color(0xFF1E1E1E),
        meText: Colors.white,
        themText: Color(0xFFE5E5E5),
        accent: Color(0xFF4D96FF),
        textPrimary: Colors.white,
        textSecondary: Color(0xFFB0B0B0),
        textMuted: Color(0xFF666666),
        divider: Color(0xFF2A2A2A),
        inputBackground: Color(0xFF252525),
      );

    case AppThemePack.midnight:
      return const AppColors(
        background: Color(0xFF050510),
        surface: Color(0xFF0A0A1A),
        surfaceLight: Color(0xFF15152A),
        meBubble: Color(0xFF6C2BD9),
        themBubble: Color(0xFF0F0F22),
        meText: Colors.white,
        themText: Color(0xFFD0D0F0),
        accent: Color(0xFF00F0FF),
        textPrimary: Color(0xFFE0E0FF),
        textSecondary: Color(0xFF8080C0),
        textMuted: Color(0xFF404080),
        divider: Color(0xFF1A1A35),
        inputBackground: Color(0xFF0D0D20),
        statusOnline: Color(0xFF00F0FF),
      );

    case AppThemePack.paper:
      return const AppColors(
        background: Color(0xFFF5F0E8),
        surface: Color(0xFFEDE8DF),
        surfaceLight: Color(0xFFE0D9CE),
        meBubble: Color(0xFF5B8A72),
        themBubble: Color(0xFFE0D9CE),
        meText: Colors.white,
        themText: Color(0xFF3A3530),
        accent: Color(0xFF5B8A72),
        textPrimary: Color(0xFF2A2520),
        textSecondary: Color(0xFF7A756E),
        textMuted: Color(0xFFAAA59E),
        divider: Color(0xFFD8D2C8),
        inputBackground: Color(0xFFEDE8DF),
        statusOnline: Color(0xFF5B8A72),
        statusConnected: Color(0xFF5B8A72),
      );

    case AppThemePack.forest:
      return const AppColors(
        background: Color(0xFF0F1A14),
        surface: Color(0xFF152620),
        surfaceLight: Color(0xFF1E3328),
        meBubble: Color(0xFF2D6B4F),
        themBubble: Color(0xFF152620),
        meText: Color(0xFFE8F5E0),
        themText: Color(0xFFCCDDC4),
        accent: Color(0xFF6BBF7A),
        textPrimary: Color(0xFFD4E8CC),
        textSecondary: Color(0xFF88AA80),
        textMuted: Color(0xFF506048),
        divider: Color(0xFF1E3328),
        inputBackground: Color(0xFF152620),
        statusOnline: Color(0xFF6BBF7A),
        statusConnected: Color(0xFF6BBF7A),
      );

    case AppThemePack.retro:
      return const AppColors(
        background: Color(0xFF1A1B2E),
        surface: Color(0xFF222340),
        surfaceLight: Color(0xFF2E3050),
        meBubble: Color(0xFFE04040),
        themBubble: Color(0xFF2A2B48),
        meText: Color(0xFFFFF8E0),
        themText: Color(0xFFD0D0E0),
        accent: Color(0xFFFFD700),
        textPrimary: Color(0xFFF0E8D0),
        textSecondary: Color(0xFFA0A0C0),
        textMuted: Color(0xFF606080),
        divider: Color(0xFF2E3050),
        inputBackground: Color(0xFF222340),
        statusOnline: Color(0xFFFFD700),
        statusConnected: Color(0xFF40E040),
      );

    case AppThemePack.pastel:
      return const AppColors(
        background: Color(0xFFFAF0F5),
        surface: Color(0xFFF2E6ED),
        surfaceLight: Color(0xFFEADAE5),
        meBubble: Color(0xFFB88DAF),
        themBubble: Color(0xFFF2E6ED),
        meText: Colors.white,
        themText: Color(0xFF5A4055),
        accent: Color(0xFFB88DAF),
        textPrimary: Color(0xFF3A2535),
        textSecondary: Color(0xFF8A7085),
        textMuted: Color(0xFFBBA5B5),
        divider: Color(0xFFE8D5E2),
        inputBackground: Color(0xFFF2E6ED),
        statusOnline: Color(0xFFB88DAF),
        statusConnected: Color(0xFF8DAF8E),
      );
  }
}

ThemeData _buildTheme(AppThemePack pack) {
  final c = _buildColors(pack);
  final isDark = pack != AppThemePack.paper && pack != AppThemePack.pastel;

  return ThemeData(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.background,
    fontFamily: pack == AppThemePack.retro ? 'monospace' : null,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accent,
      onSecondary: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      error: c.statusDisconnected,
      onError: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      elevation: 0,
      iconTheme: IconThemeData(color: c.textSecondary),
      titleTextStyle: TextStyle(
        color: c.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontFamily: pack == AppThemePack.retro ? 'monospace' : null,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      titleTextStyle: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: c.textSecondary, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceLight,
      contentTextStyle: TextStyle(color: c.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
