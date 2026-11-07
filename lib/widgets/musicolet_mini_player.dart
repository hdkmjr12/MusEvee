import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/local_music_provider.dart';
import 'pressable_scale.dart';

class MusicoletMiniPlayer extends StatelessWidget {
  final VoidCallback onTapOpenNowPlaying;

  const MusicoletMiniPlayer({
    super.key,
    required this.onTapOpenNowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalMusicProvider>(
      builder: (context, localProvider, _) {
        final song = localProvider.currentSong;
        if (song == null) {
          return const SizedBox.shrink();
        }

        return Material(
          color: const Color(0xFF14171E),
          child: InkWell(
            onTap: onTapOpenNowPlaying,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.09),
                    width: 0.7,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thin Musicolet top progress hairline (isolated to 200ms ValueNotifier)
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
                        minHeight: 2.0,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      );
                    },
                  ),
                  SizedBox(
                    height: 50,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      child: Row(
                        children: [
                          // 38x38 Cover Art
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: _buildMiniCover(song.coverFilePath),
                          ),
                          const SizedBox(width: 10),

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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 1.5),
                                Text(
                                  '${song.artist} • ${song.folderName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF98A2B3),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Transport Controls
                          PressableScale(
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Sebelumnya',
                              onPressed: localProvider.playPrevious,
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white70,
                                size: 22,
                              ),
                            ),
                          ),
                          PressableScale(
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip:
                                  localProvider.isPlaying ? 'Jeda' : 'Putar',
                              onPressed: localProvider.togglePlayPause,
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  localProvider.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  key: ValueKey<bool>(localProvider.isPlaying),
                                  color: Colors.white,
                                  size: 27,
                                ),
                              ),
                            ),
                          ),
                          PressableScale(
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Berikutnya',
                              onPressed: localProvider.playNext,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white70,
                                size: 22,
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

  Widget _buildMiniCover(String? path) {
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        width: 38,
        height: 38,
        cacheWidth: 144,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 38,
      height: 38,
      color: const Color(0xFF22252D),
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: Color(0xFF98A2B3),
        size: 18,
      ),
    );
  }
}
