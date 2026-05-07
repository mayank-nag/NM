import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'connection_service.dart';
import 'theme_provider.dart';

class WhiteboardScreen extends StatefulWidget {
  final ConnectionService connectionService;

  const WhiteboardScreen({super.key, required this.connectionService});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  Color _selectedColor = Colors.white;
  double _strokeWidth = 3.0;
  StreamSubscription? _msgSub;

  static const List<Color> _palette = [
    Colors.white,
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFF9B59B6),
    Color(0xFFFF8C42),
    Color(0xFFE91E63),
  ];

  static const List<double> _widths = [2.0, 3.0, 5.0, 8.0];

  @override
  void initState() {
    super.initState();
    _msgSub = widget.connectionService.messages.listen(_handleMessage);
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'whiteboard_stroke') {
      final points = (msg['points'] as List)
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
      final color = Color(int.parse((msg['color'] as String).replaceFirst('#', '0xFF')));
      final width = (msg['width'] as num).toDouble();

      if (mounted) {
        setState(() {
          _strokes.add(_Stroke(points: points, color: color, width: width));
        });
      }
    } else if (msg['type'] == 'whiteboard_clear') {
      if (mounted) {
        setState(() => _strokes.clear());
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = _Stroke(
        points: [details.localPosition],
        color: _selectedColor,
        width: _strokeWidth,
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke!.points.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke == null) return;

    final stroke = _currentStroke!;
    setState(() {
      _strokes.add(stroke);
      _currentStroke = null;
    });

    // Send stroke to partner
    widget.connectionService.send({
      'type': 'whiteboard_stroke',
      'points': stroke.points.map((p) => [p.dx, p.dy]).toList(),
      'color': '#${stroke.color.toARGB32().toRadixString(16).substring(2)}',
      'width': stroke.width,
    });
  }

  void _clearCanvas() {
    setState(() => _strokes.clear());
    widget.connectionService.send({'type': 'whiteboard_clear'});
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
      // Note: undo is local only — partner still sees the stroke
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Whiteboard', style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: Icon(Icons.undo, color: _strokes.isEmpty ? c.textMuted.withValues(alpha: 0.3) : c.textSecondary),
            onPressed: _strokes.isEmpty ? null : _undo,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: c.statusDisconnected),
            onPressed: _strokes.isEmpty ? null : () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear canvas?'),
                  content: const Text('This will clear the canvas for both of you.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: c.textMuted))),
                    TextButton(onPressed: () { Navigator.pop(ctx); _clearCanvas(); }, child: Text('Clear', style: TextStyle(color: c.statusDisconnected))),
                  ],
                ),
              );
            },
            tooltip: 'Clear all',
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas
          Expanded(
            child: Container(
              color: const Color(0xFF111111),
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(
                  painter: _WhiteboardPainter(
                    strokes: _strokes,
                    currentStroke: _currentStroke,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),

          // Toolbar
          Container(
            padding: EdgeInsets.only(
              left: 12, right: 12, top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 10,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                // Color palette
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _palette.map((color) {
                        final isSelected = _selectedColor == color;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? c.accent : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(color: c.accent.withValues(alpha: 0.3), blurRadius: 6)]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Stroke width selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _widths.map((w) {
                      final isSelected = _strokeWidth == w;
                      return GestureDetector(
                        onTap: () => setState(() => _strokeWidth = w),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? c.accent.withValues(alpha: 0.2) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            width: w + 2,
                            height: w + 2,
                            decoration: BoxDecoration(
                              color: isSelected ? c.accent : c.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;

  _Stroke({required this.points, required this.color, required this.width});
}

class _WhiteboardPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final _Stroke? currentStroke;

  _WhiteboardPainter({required this.strokes, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, _Stroke stroke) {
    if (stroke.points.length < 2) {
      // Single point — draw a dot
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.fill;
      canvas.drawCircle(stroke.points.first, stroke.width / 2, paint);
      return;
    }

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

    for (int i = 1; i < stroke.points.length; i++) {
      final p0 = stroke.points[i - 1];
      final p1 = stroke.points[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(stroke.points.last.dx, stroke.points.last.dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) => true;
}
