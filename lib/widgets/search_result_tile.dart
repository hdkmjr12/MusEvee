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

  static const Color _surfaceCard = Color(0xFF17191E);
  static const Color _surfaceSubtle = Color(0xFF22252D);
  static const Color _primaryAccent = Color(0xFF3898EC);
  static const Color _textPrimary = Color(0xFFF2F4F7);
  static const Color _textMuted = Color(0xFF98A2B3);
  static const Color _amberDot = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final hasDuplicate =
        duplicateFolder != null && duplicateFolder!.trim().isNotEmpty;
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Material(
      color: _surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hairline, width: 0.8),
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
                  color: _surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: hairline, width: 0.8),
                ),
                clipBehavior: Clip.antiAlias,
                child: track.coverUrl.isNotEmpty
                    ? Image.network(
                        track.coverUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCoverPlaceholder(),
                      )
                    : _buildCoverPlaceholder(),
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
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
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

              // Right column: Duration + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.formattedDuration,
                    style: const TextStyle(
                      color: _textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: _primaryAccent,
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
      width: 50,
      height: 50,
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
