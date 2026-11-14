import 'package:flutter/material.dart';

import '../models/track_metadata.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

class SearchResultTile extends StatelessWidget {
  final TrackMetadata track;
  final String? duplicateFolder;
  final VoidCallback onTap;
  final VoidCallback? onQuickQueue;

  const SearchResultTile({
    super.key,
    required this.track,
    required this.duplicateFolder,
    required this.onTap,
    this.onQuickQueue,
  });

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final hasDuplicate =
        duplicateFolder != null && duplicateFolder!.trim().isNotEmpty;

    return MographSpringTap(
      pressedScale: 0.985,
      child: Material(
        color: palette.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.hairline, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Cover Art 50x50
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: palette.surfaceSubtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: palette.hairline, width: 0.8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: track.coverUrl.isNotEmpty
                      ? Image.network(
                          track.coverUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildCoverPlaceholder(palette),
                        )
                      : _buildCoverPlaceholder(palette),
                ),
                const SizedBox(width: 12),

                // Title, Artist • Album, and Duplicate Dot Indicator
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      '${track.artist} • ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                      ),
                    ),
                    if (hasDuplicate) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: MusEveePalette.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              AppStrings.batchAlreadyInFolder(duplicateFolder!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MusEveePalette.amber,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Right column: Duration + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.formattedDuration,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildCoverPlaceholder(MusEveePalette palette) {
    return Container(
      width: 50,
      height: 50,
      color: palette.surfaceSubtle,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: palette.textMuted,
        size: 19,
      ),
    );
  }
}
