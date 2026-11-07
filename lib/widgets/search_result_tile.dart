import 'package:flutter/material.dart';

import '../models/track_metadata.dart';

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

  static const Color _surfaceCard = Color(0xFFFFFFFF);
  static const Color _surfaceSubtle = Color(0xFFF2F4F7);
  static const Color _primaryBlue = Color(0xFF1677B8);
  static const Color _textDark = Color(0xFF15181E);
  static const Color _textMuted = Color(0xFF68717C);
  static const Color _amberDot = Color(0xFFD97706);

  @override
  Widget build(BuildContext context) {
    final hasDuplicate =
        duplicateFolder != null && duplicateFolder!.trim().isNotEmpty;
    final hairline = Colors.black.withValues(alpha: 0.07);

    return Material(
      color: _surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: hairline, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Cover Art 52x52 (Micro-radius 6px + Subtle Hairline)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: track.coverUrl.isNotEmpty
                    ? Image.network(
                        track.coverUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverPlaceholder(),
                      )
                    : _buildCoverPlaceholder(),
              ),
              const SizedBox(width: 12),

              // Title, Artist • Album, and Modern Dot Indicator
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${track.artist} • ${track.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12.5,
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
                              color: _amberDot,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Sudah ada di $duplicateFolder',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _amberDot,
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

              // Right column: Duration + subtle 18px icon
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.formattedDuration,
                    style: const TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: _primaryBlue,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      width: 52,
      height: 52,
      color: _surfaceSubtle,
      alignment: Alignment.center,
      child: const Icon(
        Icons.music_note_rounded,
        color: _textMuted,
        size: 19,
      ),
    );
  }
}
