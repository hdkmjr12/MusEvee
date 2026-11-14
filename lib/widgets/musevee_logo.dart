import 'package:flutter/material.dart';

import '../theme/musevee_palette.dart';

/// Logo resmi MusEvee berlatar 100% transparan (`assets/musevee_logo.png`),
/// identik dengan ikon launcher Android di `mipmap-*/ic_launcher.png`.
class MusEveeLogo extends StatelessWidget {
  final double size;

  const MusEveeLogo({
    super.key,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final targetCache = (size * 3.5).round().clamp(64, 512);
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/musevee_logo.png',
        width: size,
        height: size,
        cacheWidth: targetCache,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        isAntiAlias: true,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.music_note_rounded,
            size: size * 0.85,
            color: palette.nowPlayingPrimary,
          );
        },
      ),
    );
  }
}
