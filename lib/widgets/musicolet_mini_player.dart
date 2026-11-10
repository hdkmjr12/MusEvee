import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/local_music_provider.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

/// Phase 1 skin pass on the Mini Player (shown above the bottom strip on all
/// tabs except Now Playing). Preserves 100% of existing behavior and controls.
class MusicoletMiniPlayer extends StatelessWidget {
  final VoidCallback onTapOpenNowPlaying;

  const MusicoletMiniPlayer({
    super.key,
    required this.onTapOpenNowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Consumer<LocalMusicProvider>(
      builder: (context, localProvider, _) {
        final song = localProvider.currentSong;
        if (song == null) {
          return const SizedBox.shrink();
        }

        return Material(
          color: palette.bottomBar,
          child: InkWell(
            onTap: onTapOpenNowPlaying,
            child: Container(
              decoration: BoxDecoration(
                color: palette.bottomBar,
                border: Border(
                  top: BorderSide(
                    color: palette.hairline,
                    width: 0.7,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thin top progress hairline (isolated to 200ms ValueNotifier)
                  ValueListenableBuilder<PlaybackProgress>(
                    valueListenable: localProvider.progressNotifier,
                    builder: (context, prog, _) {
                      final total = prog.durationMs > 0
                          ? prog.durationMs
                          : (localProvider.durationMs > 0
                              ? localProvider.durationMs
                              : 1);
                      final progress = (prog.positionMs / total).clamp(0.0, 1.0);
                      return LinearProgressIndicator(
                        value: progress,
                        minHeight: 1.8,
                        backgroundColor: palette.seekbarInactive,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          palette.nowPlayingPrimary,
                        ),
                      );
                    },
                  ),
                  SizedBox(
                    height: 54,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 6),
                      child: Row(
                        children: [
                          // 38x38 Circular/Rounded Cover Art with thin hairline border
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: palette.discRingBorder,
                                width: 1.0,
                              ),
                            ),
                            child: ClipOval(
                              child: _buildMiniCover(song.coverFilePath, palette),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title & Artist
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.nowPlayingPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.nowPlayingSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Transport Controls: Prev, Solid Circle Play/Pause, Next
                          PressableScale(
                            child: IconButton(
                              constraints: const BoxConstraints(
                                minWidth: MusEveePalette.minTouchTargetSize,
                                minHeight: MusEveePalette.minTouchTargetSize,
                              ),
                              tooltip: AppStrings.tr(
                                'Sebelumnya',
                                'Previous',
                                context,
                              ),
                              onPressed: localProvider.playPrevious,
                              icon: Transform.scale(
                                scaleX: -1,
                                child: Image.asset(
                                  'assets/icons/play.png',
                                  width: 15,
                                  height: 15,
                                  color: palette.nowPlayingPrimary,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                            ),
                          ),
                          PressableScale(
                            child: IconButton(
                              constraints: const BoxConstraints(
                                minWidth: MusEveePalette.minTouchTargetSize,
                                minHeight: MusEveePalette.minTouchTargetSize,
                              ),
                              tooltip: localProvider.isPlaying
                                  ? AppStrings.tr('Jeda', 'Pause', context)
                                  : AppStrings.tr('Putar', 'Play', context),
                              onPressed: localProvider.togglePlayPause,
                              icon: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: palette.nowPlayingPrimary,
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  localProvider.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 19,
                                  color: palette.nowPlayingOnPrimary,
                                ),
                              ),
                            ),
                          ),
                          PressableScale(
                            child: IconButton(
                              constraints: const BoxConstraints(
                                minWidth: MusEveePalette.minTouchTargetSize,
                                minHeight: MusEveePalette.minTouchTargetSize,
                              ),
                              tooltip: AppStrings.tr(
                                'Berikutnya',
                                'Next',
                                context,
                              ),
                              onPressed: localProvider.playNext,
                              icon: Image.asset(
                                'assets/icons/play.png',
                                width: 15,
                                height: 15,
                                color: palette.nowPlayingPrimary,
                                colorBlendMode: BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniCover(String? path, MusEveePalette palette) {
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        width: 38,
        height: 38,
        cacheWidth: 144,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _placeholder(palette),
      );
    }
    return _placeholder(palette);
  }

  Widget _placeholder(MusEveePalette palette) {
    return Container(
      width: 38,
      height: 38,
      color: palette.surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: palette.nowPlayingSecondary,
        size: 17,
      ),
    );
  }
}
