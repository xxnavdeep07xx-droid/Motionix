import 'dart:io';

import 'package:flutter/material.dart';

import 'brand.dart';

/// Filmstrip of proxy thumbnails with a live playhead — the scrubbing aid
/// that makes a phone feel like a real NLE.
class Filmstrip extends StatelessWidget {
  const Filmstrip({super.key, required this.thumbs, required this.playhead});

  final List<String> thumbs;
  final double playhead;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(builder: (context, constraints) {
          return Stack(
            children: [
              Row(
                children: thumbs
                    .map((p) => Expanded(
                          child: Image.file(
                            File(p),
                            fit: BoxFit.cover,
                            height: 54,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => Container(
                              color: Brand.surfaceHi,
                              height: 54,
                            ),
                          ),
                        ))
                    .toList(),
              ),
              // Playhead.
              Positioned(
                left: (playhead.clamp(0.0, 1.0)) *
                    (constraints.maxWidth - 2),
                child: Container(
                  width: 2,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 4),
                    ],
                  ),
                ),
              ),
              // Ignore pointer so taps pass through to nothing destructive.
              Positioned.fill(child: IgnorePointer(child: Container())),
            ],
          );
        }),
      ),
    );
  }
}
