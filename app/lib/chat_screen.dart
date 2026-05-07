import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'connection_service.dart';
import 'database.dart';
import 'photo_viewer.dart';
import 'settings_screen.dart';
import 'theme_provider.dart';
import 'whiteboard_screen.dart';

class ChatScreen extends StatefulWidget {
  final ConnectionService connectionService;
  final List<SharedMediaFile>? pendingSharedFiles;
  final VoidCallback? onSharedContentConsumed;

  const ChatScreen({
    super.key,
    required this.connectionService,
    this.pendingSharedFiles,
    this.onSharedContentConsumed,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _db = AppDatabase.instance;
  final _imagePicker = ImagePicker();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  List<Message> _messages = [];
  String? _partnerName;
  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _dbSub;
  StreamSubscription? _nameSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = widget.connectionService.currentStatus;

    _statusSub = widget.connectionService.status.listen((s) {
      if (mounted) setState(() => _status = s);
    });

    _msgSub = widget.connectionService.messages.listen(_handleIncomingMessage);

    _nameSub = _db.watchPartnerName().listen((name) {
      if (mounted) setState(() => _partnerName = name);
    });
    _db.getSetting('partner_self_name').then((name) {
      if (_partnerName == null && name != null && mounted) {
        setState(() => _partnerName = name);
      }
    });

    _dbSub = _db.watchMessages().listen((msgs) {
      if (mounted) {
        setState(() => _messages = msgs);
        _scrollToBottom();
      }
    });

    // Process any pending shared content
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPendingShares();
    });
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pendingSharedFiles != oldWidget.pendingSharedFiles) {
      _processPendingShares();
    }
  }

  void _processPendingShares() {
    if (widget.pendingSharedFiles != null && widget.pendingSharedFiles!.isNotEmpty) {
      for (final file in widget.pendingSharedFiles!) {
        if (file.type == SharedMediaType.image) {
          _sendSharedImage(file.path);
        } else {
          // text, url, or other — treat as shared content
          _sendSharedContent(file.path);
        }
      }
      widget.onSharedContentConsumed?.call();
    }
  }

  void _sendSharedContent(String text) {
    final now = DateTime.now();

    // Check if it looks like a URL
    final urlRegex = RegExp(r'https?://\S+', caseSensitive: false);
    final match = urlRegex.firstMatch(text);

    if (match != null) {
      final url = match.group(0)!;
      final title = text != url ? text.replaceAll(url, '').trim() : '';

      // Store as a share message
      _db.insertMessage(
        title.isNotEmpty ? title : url,
        true, now,
        type: 'share',
        shareUrl: url,
        shareTitle: title.isNotEmpty ? title : null,
      );

      // Send over WebSocket
      widget.connectionService.send({
        'type': 'share',
        'url': url,
        'title': title.isNotEmpty ? title : '',
        'timestamp': now.millisecondsSinceEpoch,
      });
    } else {
      // Plain text — send as normal text message
      _db.insertMessage(text, true, now);
      widget.connectionService.send({
        'type': 'text',
        'content': text,
        'timestamp': now.millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _sendSharedImage(String imagePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(dir.path, 'nm_photos'));
    if (!photoDir.existsSync()) photoDir.createSync(recursive: true);

    final filename = 'shared_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = p.join(photoDir.path, filename);
    await File(imagePath).copy(savedPath);

    final now = DateTime.now();
    _db.insertMessage('', true, now, type: 'photo', mediaPath: savedPath);

    final bytes = await File(savedPath).readAsBytes();
    widget.connectionService.send({
      'type': 'photo',
      'filename': filename,
      'data': base64Encode(bytes),
      'timestamp': now.millisecondsSinceEpoch,
    });
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> msg) async {
    if (msg['type'] == 'text') {
      _db.insertMessage(
        msg['content'] as String,
        false,
        DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int),
      );
    } else if (msg['type'] == 'photo') {
      final photoData = msg['data'] as String?;
      final filename = msg['filename'] as String? ?? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int);

      if (photoData != null) {
        final dir = await getApplicationDocumentsDirectory();
        final photoDir = Directory(p.join(dir.path, 'nm_photos'));
        if (!photoDir.existsSync()) photoDir.createSync(recursive: true);

        final filePath = p.join(photoDir.path, filename);
        final bytes = base64Decode(photoData);
        await File(filePath).writeAsBytes(bytes);

        _db.insertMessage('', false, timestamp, type: 'photo', mediaPath: filePath);
      }
    } else if (msg['type'] == 'share') {
      final url = msg['url'] as String? ?? '';
      final title = msg['title'] as String? ?? '';
      final timestamp = DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int);

      _db.insertMessage(
        title.isNotEmpty ? title : url,
        false, timestamp,
        type: 'share',
        shareUrl: url,
        shareTitle: title.isNotEmpty ? title : null,
      );
    } else if (msg['type'] == 'nickname_update') {
      final partnerSelfName = msg['self'] as String?;
      if (partnerSelfName != null && partnerSelfName.isNotEmpty) {
        _db.setSetting('partner_self_name', partnerSelfName);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    _db.insertMessage(text, true, now);
    widget.connectionService.send({
      'type': 'text',
      'content': text,
      'timestamp': now.millisecondsSinceEpoch,
    });
    _textController.clear();
  }

  Future<void> _pickAndSendPhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(dir.path, 'nm_photos'));
    if (!photoDir.existsSync()) photoDir.createSync(recursive: true);

    final filename = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = p.join(photoDir.path, filename);
    await File(picked.path).copy(savedPath);

    final now = DateTime.now();
    _db.insertMessage('', true, now, type: 'photo', mediaPath: savedPath);

    final bytes = await File(savedPath).readAsBytes();
    widget.connectionService.send({
      'type': 'photo',
      'filename': filename,
      'data': base64Encode(bytes),
      'timestamp': now.millisecondsSinceEpoch,
    });
  }

  void _showPhotoOptions() {
    final c = context.read<ThemeProvider>().colors;

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: Icon(Icons.camera_alt, color: c.accent),
                title: Text('Take Photo', style: TextStyle(color: c.textPrimary)),
                onTap: () { Navigator.pop(ctx); _pickAndSendPhoto(ImageSource.camera); },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: c.accent),
                title: Text('Choose from Gallery', style: TextStyle(color: c.textPrimary)),
                onTap: () { Navigator.pop(ctx); _pickAndSendPhoto(ImageSource.gallery); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgSub?.cancel();
    _statusSub?.cancel();
    _dbSub?.cancel();
    _nameSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    final prev = _messages[index - 1].timestamp;
    final curr = _messages[index].timestamp;
    return prev.year != curr.year || prev.month != curr.month || prev.day != curr.day;
  }

  Widget _buildStatusBar(AppColors c) {
    final Color color;
    final String text;
    final IconData icon;
    switch (_status) {
      case ConnectionStatus.disconnected:
        color = c.statusDisconnected; text = 'Disconnected'; icon = Icons.cloud_off;
      case ConnectionStatus.connecting:
        color = c.statusConnecting; text = 'Connecting...'; icon = Icons.sync;
      case ConnectionStatus.connected:
        color = c.statusConnected; text = 'Waiting for partner'; icon = Icons.cloud_queue;
      case ConnectionStatus.partnerOnline:
        color = c.statusOnline; text = 'Online'; icon = Icons.cloud_done;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: color.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface, elevation: 0, centerTitle: false,
        title: Row(children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(
            color: _status == ConnectionStatus.partnerOnline ? c.statusOnline : c.textMuted,
            shape: BoxShape.circle,
          )),
          const SizedBox(width: 10),
          Text(_partnerName ?? 'NM', style: TextStyle(
            color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.5,
          )),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.draw_outlined, color: c.textMuted),
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => WhiteboardScreen(connectionService: widget.connectionService))),
            tooltip: 'Whiteboard',
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: c.textMuted),
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => SettingsScreen(connectionService: widget.connectionService))),
          ),
        ],
      ),
      body: Column(children: [
        if (_status != ConnectionStatus.partnerOnline) _buildStatusBar(c),
        Expanded(
          child: _messages.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: c.textMuted.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('No messages yet', style: TextStyle(color: c.textMuted, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Say something!', style: TextStyle(color: c.textMuted.withValues(alpha: 0.5), fontSize: 12)),
                  ],
                ))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final showDate = _shouldShowDateHeader(index);
                    final isLastInGroup = index == _messages.length - 1 || _messages[index + 1].isMe != msg.isMe;
                    return Column(children: [
                      if (showDate)
                        Padding(padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(_formatDateHeader(msg.timestamp),
                            style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5))),
                      if (msg.type == 'photo')
                        _PhotoBubble(mediaPath: msg.mediaPath, isMe: msg.isMe, time: _formatTime(msg.timestamp), showTail: isLastInGroup, colors: c)
                      else if (msg.type == 'share')
                        _ShareBubble(url: msg.shareUrl, title: msg.shareTitle, content: msg.content, isMe: msg.isMe, time: _formatTime(msg.timestamp), showTail: isLastInGroup, colors: c)
                      else
                        _MessageBubble(content: msg.content, isMe: msg.isMe, time: _formatTime(msg.timestamp), showTail: isLastInGroup, colors: c),
                    ]);
                  },
                ),
        ),
        _buildInputBar(c),
      ]),
    );
  }

  Widget _buildInputBar(AppColors c) {
    return Container(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.divider, width: 0.5))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(
          onPressed: _showPhotoOptions,
          icon: Icon(Icons.camera_alt_outlined, color: c.textMuted, size: 22),
          padding: const EdgeInsets.all(8), constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
        Expanded(child: Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(color: c.inputBackground, borderRadius: BorderRadius.circular(22)),
          child: TextField(
            controller: _textController,
            style: TextStyle(color: c.textPrimary, fontSize: 15),
            maxLines: null, textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Message', hintStyle: TextStyle(color: c.textMuted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: InputBorder.none,
            ),
            onSubmitted: (_) => _sendMessage(),
          ),
        )),
        const SizedBox(width: 6),
        Container(margin: const EdgeInsets.only(bottom: 2), child: IconButton(
          onPressed: _sendMessage,
          icon: const Icon(Icons.arrow_upward, size: 20),
          style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white, fixedSize: const Size(40, 40), shape: const CircleBorder()),
        )),
      ]),
    );
  }
}

// ── Text message bubble ──
class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isMe;
  final String time;
  final bool showTail;
  final AppColors colors;

  const _MessageBubble({required this.content, required this.isMe, required this.time, required this.showTail, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: showTail ? 8 : 2, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isMe ? colors.meBubble : colors.themBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe || !showTail ? 18 : 4),
              bottomRight: Radius.circular(!isMe || !showTail ? 18 : 4),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(content, style: TextStyle(color: isMe ? colors.meText : colors.themText, fontSize: 15, height: 1.35)),
            const SizedBox(height: 3),
            Text(time, style: TextStyle(color: (isMe ? colors.meText : colors.themText).withValues(alpha: 0.45), fontSize: 10)),
          ]),
        ),
      ),
    );
  }
}

// ── Photo bubble ──
class _PhotoBubble extends StatelessWidget {
  final String? mediaPath;
  final bool isMe;
  final String time;
  final bool showTail;
  final AppColors colors;

  const _PhotoBubble({required this.mediaPath, required this.isMe, required this.time, required this.showTail, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: showTail ? 8 : 2, left: isMe ? 80 : 0, right: isMe ? 0 : 80),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () {
            if (mediaPath != null && File(mediaPath!).existsSync()) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(filePath: mediaPath!)));
            }
          },
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: isMe ? colors.meBubble : colors.themBubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe || !showTail ? 18 : 4),
                bottomRight: Radius.circular(!isMe || !showTail ? 18 : 4),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe || !showTail ? 14 : 2),
                  bottomRight: Radius.circular(!isMe || !showTail ? 14 : 2),
                ),
                child: mediaPath != null && File(mediaPath!).existsSync()
                    ? Hero(tag: mediaPath!, child: Image.file(File(mediaPath!), width: 240, fit: BoxFit.cover))
                    : Container(width: 240, height: 160, color: colors.surfaceLight,
                        child: Icon(Icons.broken_image, color: colors.textMuted, size: 32)),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(time, style: TextStyle(color: (isMe ? colors.meText : colors.themText).withValues(alpha: 0.45), fontSize: 10))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Share/link card bubble ──
class _ShareBubble extends StatelessWidget {
  final String? url;
  final String? title;
  final String content;
  final bool isMe;
  final String time;
  final bool showTail;
  final AppColors colors;

  const _ShareBubble({
    required this.url, required this.title, required this.content,
    required this.isMe, required this.time, required this.showTail, required this.colors,
  });

  String get _displayDomain {
    if (url == null || url!.isEmpty) return '';
    try {
      return Uri.parse(url!).host.replaceFirst('www.', '');
    } catch (_) {
      return url!;
    }
  }

  IconData get _domainIcon {
    final domain = _displayDomain.toLowerCase();
    if (domain.contains('youtube') || domain.contains('youtu.be')) return Icons.play_circle_fill;
    if (domain.contains('instagram')) return Icons.camera_alt;
    if (domain.contains('tiktok')) return Icons.music_note;
    if (domain.contains('twitter') || domain.contains('x.com')) return Icons.alternate_email;
    if (domain.contains('reddit')) return Icons.forum;
    if (domain.contains('spotify')) return Icons.headphones;
    return Icons.link;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 2, bottom: showTail ? 8 : 2, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: isMe ? colors.meBubble : colors.themBubble,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMe || !showTail ? 18 : 4),
              bottomRight: Radius.circular(!isMe || !showTail ? 18 : 4),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Link card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isMe ? Colors.black : colors.surfaceLight).withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18), topRight: Radius.circular(18),
                ),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_domainIcon, color: colors.accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title != null && title!.isNotEmpty)
                    Text(title!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: isMe ? colors.meText : colors.themText, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(_displayDomain, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: (isMe ? colors.meText : colors.themText).withValues(alpha: 0.5), fontSize: 11)),
                ])),
              ]),
            ),
            // URL text + time
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (url != null)
                  Text(url!, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: (isMe ? colors.meText : colors.accent), fontSize: 13, decoration: TextDecoration.underline)),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(color: (isMe ? colors.meText : colors.themText).withValues(alpha: 0.45), fontSize: 10)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
