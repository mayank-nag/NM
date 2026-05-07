import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

class PhotoViewer extends StatelessWidget {
  final String filePath;

  const PhotoViewer({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Hero(
              tag: filePath,
              child: Image.file(
                File(filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: c.textMuted),
                    const SizedBox(height: 12),
                    Text('Photo not found', style: TextStyle(color: c.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
