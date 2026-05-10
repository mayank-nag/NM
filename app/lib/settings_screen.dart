import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'connection_service.dart';
import 'database.dart';
import 'theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  final ConnectionService connectionService;

  const SettingsScreen({super.key, required this.connectionService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = AppDatabase.instance;
  final _myNameController = TextEditingController();
  final _partnerNameController = TextEditingController();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  StreamSubscription? _statusSub;
  bool _loading = true;
  String _currentStatusPreset = '';

  static const List<Map<String, dynamic>> _statusPresets = [
    {'label': 'Online', 'value': '', 'icon': Icons.circle, 'color': 0xFF6BCB77},
    {'label': 'Busy Studying', 'value': 'Busy Studying 📚', 'icon': Icons.menu_book, 'color': 0xFFFFD93D},
    {'label': 'At Work', 'value': 'At Work 💼', 'icon': Icons.work_outline, 'color': 0xFF4D96FF},
    {'label': 'Out of Net', 'value': 'Out of Net 📵', 'icon': Icons.signal_wifi_off, 'color': 0xFFFF6B6B},
    {'label': 'Sleeping', 'value': 'Sleeping 😴', 'icon': Icons.bedtime, 'color': 0xFF9B59B6},
    {'label': 'Do Not Disturb', 'value': 'Do Not Disturb 🔇', 'icon': Icons.do_not_disturb, 'color': 0xFFE04040},
    {'label': 'At Gym', 'value': 'At Gym 💪', 'icon': Icons.fitness_center, 'color': 0xFFFF8C42},
    {'label': 'Chilling', 'value': 'Chilling 😎', 'icon': Icons.weekend, 'color': 0xFF6BCB77},
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.connectionService.currentStatus;
    _statusSub = widget.connectionService.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });
    _loadNames();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final saved = await _db.getSetting('my_custom_status') ?? '';
    if (mounted) setState(() => _currentStatusPreset = saved);
  }

  Future<void> _setStatus(String value) async {
    setState(() => _currentStatusPreset = value);
    await _db.setSetting('my_custom_status', value);
    widget.connectionService.send({'type': 'status_update', 'status': value});
  }

  Future<void> _loadNames() async {
    final myName = await _db.getMyName();
    final partnerName = await _db.getPartnerName();
    _myNameController.text = myName ?? '';
    _partnerNameController.text = partnerName ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAndSync() async {
    final myName = _myNameController.text.trim();
    final partnerName = _partnerNameController.text.trim();

    if (myName.isNotEmpty) {
      await _db.setMyName(myName);
    }
    if (partnerName.isNotEmpty) {
      await _db.setPartnerName(partnerName);
    }

    widget.connectionService.send({
      'type': 'nickname_update',
      'self': myName,
      'other': partnerName,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicknames saved'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _myNameController.dispose();
    _partnerNameController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title, AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10, top: 24),
      child: Text(
        title,
        style: TextStyle(
          color: c.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard(AppColors c, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildNicknameField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    required AppColors c,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  style: TextStyle(color: c.textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5)),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, AppColors c, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? c.textMuted,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final c = themeProvider.colors;

    final Color statusColor;
    final String statusText;

    switch (_status) {
      case ConnectionStatus.disconnected:
        statusColor = c.statusDisconnected;
        statusText = 'Disconnected';
      case ConnectionStatus.connecting:
        statusColor = c.statusConnecting;
        statusText = 'Connecting';
      case ConnectionStatus.connected:
        statusColor = c.statusConnected;
        statusText = 'Waiting for partner';
      case ConnectionStatus.partnerOnline:
        statusColor = c.statusOnline;
        statusText = 'Online';
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _saveAndSync,
            child: Text('Save', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.textMuted))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // ── Nicknames ──
                _buildSectionHeader('NICKNAMES', c),
                _buildCard(c, children: [
                  _buildNicknameField(
                    label: 'Your name',
                    hint: 'What should they call you?',
                    controller: _myNameController,
                    icon: Icons.person_outline,
                    c: c,
                  ),
                  Divider(color: c.divider, height: 1, indent: 50),
                  _buildNicknameField(
                    label: 'Partner\'s name',
                    hint: 'What do you call them?',
                    controller: _partnerNameController,
                    icon: Icons.favorite_outline,
                    c: c,
                  ),
                ]),

                // ── Status ──
                _buildSectionHeader('YOUR STATUS', c),
                _buildCard(c, children: [
                  ..._statusPresets.map((preset) {
                    final isSelected = _currentStatusPreset == preset['value'];
                    final iconColor = Color(preset['color'] as int);
                    return InkWell(
                      onTap: () => _setStatus(preset['value'] as String),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(children: [
                          Icon(preset['icon'] as IconData, size: 20, color: iconColor),
                          const SizedBox(width: 14),
                          Expanded(child: Text(
                            preset['label'] as String,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          )),
                          if (isSelected)
                            Icon(Icons.check_circle, color: c.accent, size: 20),
                        ]),
                      ),
                    );
                  }),
                ]),

                // ── Theme ──
                _buildSectionHeader('THEME', c),
                _buildCard(c, children: [
                  ...AppThemePack.values.map((theme) {
                    final isSelected = themeProvider.current == theme;
                    final previewColors = _buildColors(theme);
                    return InkWell(
                      onTap: () => themeProvider.setTheme(theme),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // Color preview dots
                            Row(
                              children: [
                                _colorDot(previewColors.background),
                                _colorDot(previewColors.meBubble),
                                _colorDot(previewColors.accent),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    theme.label,
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                  Text(
                                    theme.description,
                                    style: TextStyle(color: c.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: c.accent, size: 20),
                          ],
                        ),
                      ),
                    );
                  }),
                ]),

                // ── Connection ──
                _buildSectionHeader('CONNECTION', c),
                _buildCard(c, children: [
                  _buildInfoRow('Status', statusText, c, valueColor: statusColor),
                  Divider(color: c.divider, height: 1, indent: 16),
                  _buildInfoRow('Room', widget.connectionService.roomId ?? '—', c),
                ]),

                // ── Danger zone ──
                _buildSectionHeader('DANGER ZONE', c),
                _buildCard(c, children: [
                  InkWell(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Unpair?'),
                          content: const Text(
                            'This will disconnect and remove the pairing. You\'ll need to pair again.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text('Cancel', style: TextStyle(color: c.textMuted)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Unpair', style: TextStyle(color: c.statusDisconnected)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        await widget.connectionService.unpair();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.link_off, size: 20, color: c.statusDisconnected),
                          const SizedBox(width: 14),
                          Text(
                            'Unpair & disconnect',
                            style: TextStyle(color: c.statusDisconnected, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _colorDot(Color color) {
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(right: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
    );
  }
}

// Expose the color builder for preview dots in the theme picker
AppColors _buildColors(AppThemePack pack) {
  // Re-use the same function from theme_provider — import it
  // Since it's a top-level function in theme_provider.dart, we can't import it directly
  // So we access it through a temporary ThemeProvider-like lookup
  // Actually, let's just access the preview colors via known values
  switch (pack) {
    case AppThemePack.defaultDark:
      return const AppColors(
        background: Color(0xFF0D0D0D), surface: Color(0xFF1A1A1A), surfaceLight: Color(0xFF2A2A2A),
        meBubble: Color(0xFF4D96FF), themBubble: Color(0xFF1E1E1E), meText: Colors.white,
        themText: Color(0xFFE5E5E5), accent: Color(0xFF4D96FF), textPrimary: Colors.white,
        textSecondary: Color(0xFFB0B0B0), textMuted: Color(0xFF666666), divider: Color(0xFF2A2A2A),
        inputBackground: Color(0xFF252525),
      );
    case AppThemePack.midnight:
      return const AppColors(
        background: Color(0xFF050510), surface: Color(0xFF0A0A1A), surfaceLight: Color(0xFF15152A),
        meBubble: Color(0xFF6C2BD9), themBubble: Color(0xFF0F0F22), meText: Colors.white,
        themText: Color(0xFFD0D0F0), accent: Color(0xFF00F0FF), textPrimary: Color(0xFFE0E0FF),
        textSecondary: Color(0xFF8080C0), textMuted: Color(0xFF404080), divider: Color(0xFF1A1A35),
        inputBackground: Color(0xFF0D0D20),
      );
    case AppThemePack.paper:
      return const AppColors(
        background: Color(0xFFF5F0E8), surface: Color(0xFFEDE8DF), surfaceLight: Color(0xFFE0D9CE),
        meBubble: Color(0xFF5B8A72), themBubble: Color(0xFFE0D9CE), meText: Colors.white,
        themText: Color(0xFF3A3530), accent: Color(0xFF5B8A72), textPrimary: Color(0xFF2A2520),
        textSecondary: Color(0xFF7A756E), textMuted: Color(0xFFAAA59E), divider: Color(0xFFD8D2C8),
        inputBackground: Color(0xFFEDE8DF),
      );
    case AppThemePack.forest:
      return const AppColors(
        background: Color(0xFF0F1A14), surface: Color(0xFF152620), surfaceLight: Color(0xFF1E3328),
        meBubble: Color(0xFF2D6B4F), themBubble: Color(0xFF152620), meText: Color(0xFFE8F5E0),
        themText: Color(0xFFCCDDC4), accent: Color(0xFF6BBF7A), textPrimary: Color(0xFFD4E8CC),
        textSecondary: Color(0xFF88AA80), textMuted: Color(0xFF506048), divider: Color(0xFF1E3328),
        inputBackground: Color(0xFF152620),
      );
    case AppThemePack.retro:
      return const AppColors(
        background: Color(0xFF1A1B2E), surface: Color(0xFF222340), surfaceLight: Color(0xFF2E3050),
        meBubble: Color(0xFFE04040), themBubble: Color(0xFF2A2B48), meText: Color(0xFFFFF8E0),
        themText: Color(0xFFD0D0E0), accent: Color(0xFFFFD700), textPrimary: Color(0xFFF0E8D0),
        textSecondary: Color(0xFFA0A0C0), textMuted: Color(0xFF606080), divider: Color(0xFF2E3050),
        inputBackground: Color(0xFF222340),
      );
    case AppThemePack.pastel:
      return const AppColors(
        background: Color(0xFFFAF0F5), surface: Color(0xFFF2E6ED), surfaceLight: Color(0xFFEADAE5),
        meBubble: Color(0xFFB88DAF), themBubble: Color(0xFFF2E6ED), meText: Colors.white,
        themText: Color(0xFF5A4055), accent: Color(0xFFB88DAF), textPrimary: Color(0xFF3A2535),
        textSecondary: Color(0xFF8A7085), textMuted: Color(0xFFBBA5B5), divider: Color(0xFFE8D5E2),
        inputBackground: Color(0xFFF2E6ED),
      );
  }
}
