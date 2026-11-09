import 'package:flutter/material.dart';

/// Musicolet's signature dense bottom icon strip with a smooth sliding white
/// bottom pill indicator (`Curves.easeOutCubic`, `240ms`) across 6 main tabs:
/// 0: Queue (`=♪`)
/// 1: Now Playing (`▶` in circle)
/// 2: Folders (`📁`)
/// 3: Playlists (`♫` — Albums & Artists merged into user playlists)
/// 4: Downloader (`⬇` Cloud Download + Queue/History sheet trigger)
/// 5: Search Lokal (`🔍`)
class MusicoletBottomStrip extends StatelessWidget {
  static const int downloaderTabIndex = 4;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final int activeDownloadBadgeCount;

  const MusicoletBottomStrip({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.activeDownloadBadgeCount = 0,
  });

  static const List<({String tooltip, IconData icon, IconData activeIcon})>
      _tabs = [
    (
      tooltip: 'Queue (Antrean Putar)',
      icon: Icons.queue_music_rounded,
      activeIcon: Icons.queue_music_rounded,
    ),
    (
      tooltip: 'Now Playing (Pemutar & Lirik)',
      icon: Icons.play_circle_outline_rounded,
      activeIcon: Icons.play_circle_filled_rounded,
    ),
    (
      tooltip: 'Folders (Folder Lokal)',
      icon: Icons.folder_outlined,
      activeIcon: Icons.folder_rounded,
    ),
    (
      tooltip: 'Playlists (Daftar Putar)',
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
    ),
    (
      tooltip: 'Downloader (Cari & Unduh Lagu)',
      icon: Icons.cloud_download_outlined,
      activeIcon: Icons.cloud_download_rounded,
    ),
    (
      tooltip: 'Search Lokal (Cari di Memori)',
      icon: Icons.search_rounded,
      activeIcon: Icons.search_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final safeIndex = selectedIndex.clamp(0, _tabs.length - 1);

    return Material(
      color: const Color(0xFF0A0C10),
      child: SafeArea(
        top: false,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.7,
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabCount = _tabs.length;
              final tabWidth = constraints.maxWidth / tabCount;
              const pillInset = 10.0;
              final pillWidth = (tabWidth - (pillInset * 2)).clamp(16.0, 72.0);
              final pillLeft =
                  (tabWidth * safeIndex) + ((tabWidth - pillWidth) * 0.5);

              return Stack(
                children: [
                  Row(
                    children: List.generate(tabCount, (idx) {
                      final tab = _tabs[idx];
                      final isSelected = idx == safeIndex;
                      final showBadge = idx == downloaderTabIndex &&
                          activeDownloadBadgeCount > 0;

                      Widget iconWidget = RepaintBoundary(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0.0,
                            end: isSelected ? 1.0 : 0.0,
                          ),
                          duration: const Duration(milliseconds: 360),
                          curve: isSelected
                              ? Curves.easeOutBack
                              : Curves.easeOutCubic,
                          builder: (context, t, child) {
                            // `Curves.easeOutBack` overshoots > 1.0 (~1.12), so we amplify
                            // the overshoot into a Mograph pop (1.0 -> 1.18 -> 1.08) + vertical lift (-2px)
                            final overshoot = (t - 1.0).clamp(0.0, 0.35);
                            final clamped = t.clamp(0.0, 1.0);
                            final scale =
                                1.0 + (clamped * 0.08) + (overshoot * 0.85);
                            final liftY = -2.0 * clamped - (overshoot * 3.5);

                            return Transform.translate(
                              offset: Offset(0.0, liftY),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            isSelected ? tab.activeIcon : tab.icon,
                            size: 21,
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.48),
                          ),
                        ),
                      );

                      if (showBadge) {
                        iconWidget = Badge(
                          backgroundColor: const Color(0xFF3898EC),
                          textColor: Colors.white,
                          label: Text(
                            '$activeDownloadBadgeCount',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: iconWidget,
                        );
                      }

                      return Expanded(
                        child: Tooltip(
                          message: tab.tooltip,
                          child: InkWell(
                            onTap: () => onTabSelected(idx),
                            child: Center(child: iconWidget),
                          ),
                        ),
                      );
                    }),
                  ),

                  // Musicolet signature sliding white bottom pill indicator
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    left: pillLeft,
                    bottom: 0,
                    width: pillWidth,
                    height: 2.5,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2.5),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.28),
                              blurRadius: 6,
                              offset: const Offset(0, -1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
