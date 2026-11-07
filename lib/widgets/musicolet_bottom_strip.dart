import 'package:flutter/material.dart';

/// Musicolet's signature dense bottom icon strip with a crisp white bottom
/// indicator line beneath the active tab:
/// 0: Queue (`=♪`)
/// 1: Now Playing (`▶` in circle)
/// 2: Folders (`📁`)
/// 3: Albums (`💿`)
/// 4: Artists (`👤`)
/// 5: Downloader (`⬇` Cloud Download)
/// 6: Download Queue & History (`📋`)
/// 7: Search Lokal (`🔍`)
class MusicoletBottomStrip extends StatelessWidget {
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
      tooltip: 'Albums (Koleksi Album)',
      icon: Icons.album_outlined,
      activeIcon: Icons.album_rounded,
    ),
    (
      tooltip: 'Artists (Daftar Artis)',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
    (
      tooltip: 'Downloader (Cari & Unduh Lagu)',
      icon: Icons.cloud_download_outlined,
      activeIcon: Icons.cloud_download_rounded,
    ),
    (
      tooltip: 'Download Queue & History',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
    ),
    (
      tooltip: 'Search Lokal (Cari di Memori)',
      icon: Icons.search_rounded,
      activeIcon: Icons.search_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
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
          child: Row(
            children: List.generate(_tabs.length, (idx) {
              final tab = _tabs[idx];
              final isSelected = idx == selectedIndex;
              final showBadge = idx == 6 && activeDownloadBadgeCount > 0;

              Widget iconWidget = Icon(
                isSelected ? tab.activeIcon : tab.icon,
                size: 21,
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.48),
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
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(child: iconWidget),
                        // Musicolet signature white bottom indicator bar
                        Positioned(
                          left: 6,
                          right: 6,
                          bottom: 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 2.5,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
