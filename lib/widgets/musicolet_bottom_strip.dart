import 'package:flutter/material.dart';

import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';

/// MusEvee Phase 1 redesigned 6-tab bottom navigation strip:
/// 0: Queue (`assets/icons/add-to-playlist.png`)
/// 1: Now Playing (plain filled play triangle `Icons.play_arrow_rounded` — no permanent circle)
/// 2: Folders (`assets/icons/folder.png`)
/// 3: Playlists (`assets/icons/music-album.png`)
/// 4: Downloader (`assets/icons/downloading.png` + active download badge)
/// 5: Settings (`assets/icons/settings.png`)
///
/// A single `44px` filled circle (`palette.nowPlayingPrimary`) sits BEHIND whichever tab
/// is currently active and slides horizontally (`280ms`, `Curves.easeOutCubic`) to the
/// newly selected tab, rendering the active glyph in `palette.nowPlayingOnPrimary`.
class MusicoletBottomStrip extends StatelessWidget {
  static const int queueTabIndex = 0;
  static const int nowPlayingTabIndex = 1;
  static const int foldersTabIndex = 2;
  static const int playlistsTabIndex = 3;
  static const int downloaderTabIndex = 4;
  static const int settingsTabIndex = 5;

  static const Duration indicatorSlideDuration = Duration(
    milliseconds: MusEveePalette.navSlideDurationMs,
  );
  static const Curve indicatorSlideCurve = Curves.easeOutCubic;

  static const List<String?> tabIconAssetPaths = <String?>[
    'assets/icons/add-to-playlist.png', // 0: Queue
    null, // 1: Now Playing (plain play triangle `Icons.play_arrow_rounded`)
    'assets/icons/folder.png', // 2: Folders
    'assets/icons/music-album.png', // 3: Playlists
    'assets/icons/downloading.png', // 4: Downloader
    'assets/icons/settings.png', // 5: Settings
  ];

  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final int activeDownloadBadgeCount;

  const MusicoletBottomStrip({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    this.activeDownloadBadgeCount = 0,
  });

  /// Computes the horizontal left offset of the moving active-tab circle (`~44px`)
  /// inside a bottom strip of [stripWidth] across [tabCount] equal columns.
  static double computeIndicatorLeft({
    required double stripWidth,
    required int selectedIndex,
    int tabCount = 6,
    double circleSize = MusEveePalette.navActivePlayCircleSize,
  }) {
    final safeCount = tabCount > 0 ? tabCount : 6;
    final clampedSelected = selectedIndex.clamp(0, safeCount - 1);
    final slotWidth = stripWidth / safeCount;
    return (clampedSelected * slotWidth) + ((slotWidth - circleSize) * 0.5);
  }

  /// Resolves the deterministic visual state for a navigation tab (testable without UI).
  /// Every active tab receives the moving `circleBackgroundColor` (`palette.nowPlayingPrimary`)
  /// behind its glyph and renders its glyph in `palette.nowPlayingOnPrimary`.
  static ({
    String? assetPath,
    IconData? iconData,
    bool isCircularPlayBadge,
    bool isActive,
    Color iconColor,
    Color? circleBackgroundColor,
  }) resolveTabVisualState({
    required int tabIndex,
    required int selectedIndex,
    required MusEveePalette palette,
  }) {
    final clampedIndex = tabIndex.clamp(0, tabIconAssetPaths.length - 1);
    final clampedSelected =
        selectedIndex.clamp(0, tabIconAssetPaths.length - 1);
    final isActive = clampedIndex == clampedSelected;

    return (
      assetPath: tabIconAssetPaths[clampedIndex],
      iconData:
          clampedIndex == nowPlayingTabIndex ? Icons.play_arrow_rounded : null,
      isCircularPlayBadge: isActive,
      isActive: isActive,
      iconColor: isActive
          ? palette.nowPlayingOnPrimary
          : palette.nowPlayingInactiveIcon,
      circleBackgroundColor: isActive ? palette.nowPlayingPrimary : null,
    );
  }

  static List<String> get _tabTooltips => <String>[
        AppStrings.tabQueueTooltip,
        AppStrings.tabNowPlayingTooltip,
        AppStrings.tabFoldersTooltip,
        AppStrings.tabPlaylistsTooltip,
        AppStrings.tabDownloaderTooltip,
        AppStrings.tabSettingsTooltip,
      ];

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final tooltips = _tabTooltips;
    final tabCount = tooltips.length;
    final safeIndex = selectedIndex.clamp(0, tabCount - 1);

    return Material(
      color: palette.bottomBar,
      child: SafeArea(
        top: false,
        child: Container(
          height: MusEveePalette.navStripHeight,
          decoration: BoxDecoration(
            color: palette.bottomBar,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18),
            ),
            border: Border(
              top: BorderSide(
                color: palette.hairline,
                width: 0.7,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.discShadow.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const circleSize = MusEveePalette.navActivePlayCircleSize;
              final indicatorLeft = computeIndicatorLeft(
                stripWidth: constraints.maxWidth,
                selectedIndex: safeIndex,
                tabCount: tabCount,
                circleSize: circleSize,
              );
              const indicatorTop =
                  (MusEveePalette.navStripHeight - circleSize) * 0.5;

              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // ONE moving active-tab circle behind whichever tab is selected
                  AnimatedPositioned(
                    key: const ValueKey<String>(
                      'nav_moving_active_circle_positioned',
                    ),
                    duration: indicatorSlideDuration,
                    curve: indicatorSlideCurve,
                    left: indicatorLeft,
                    top: indicatorTop,
                    width: circleSize,
                    height: circleSize,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey<String>(
                          'nav_moving_active_circle',
                        ),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.nowPlayingPrimary,
                        ),
                      ),
                    ),
                  ),

                  // 6 tab touch targets (>= 48px) with glyphs on top
                  Row(
                    children: List.generate(tabCount, (idx) {
                      final isSelected = idx == safeIndex;
                      final showBadge = idx == downloaderTabIndex &&
                          activeDownloadBadgeCount > 0;

                      Widget iconWidget = RepaintBoundary(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: isSelected ? 1.0 : 0.0,
                            end: isSelected ? 1.0 : 0.0,
                          ),
                          duration: indicatorSlideDuration,
                          curve: indicatorSlideCurve,
                          builder: (context, t, _) {
                            final tintColor = Color.lerp(
                                  palette.nowPlayingInactiveIcon,
                                  palette.nowPlayingOnPrimary,
                                  t,
                                ) ??
                                palette.nowPlayingInactiveIcon;

                            if (idx == nowPlayingTabIndex) {
                              // Plain play triangle only (no permanent circle, no outline)
                              return Icon(
                                Icons.play_arrow_rounded,
                                key: ValueKey<String>(
                                  isSelected
                                      ? 'nav_now_playing_active'
                                      : 'nav_now_playing_inactive',
                                ),
                                size: 25,
                                color: tintColor,
                              );
                            }

                            final assetPath = tabIconAssetPaths[idx]!;
                            return Image.asset(
                              assetPath,
                              width: MusEveePalette.navIconSize,
                              height: MusEveePalette.navIconSize,
                              fit: BoxFit.contain,
                              color: tintColor,
                              colorBlendMode: BlendMode.srcIn,
                            );
                          },
                        ),
                      );

                      if (showBadge) {
                        final badgeBg = isSelected
                            ? palette.nowPlayingOnPrimary
                            : palette.nowPlayingPrimary;
                        final badgeFg = isSelected
                            ? palette.nowPlayingPrimary
                            : palette.nowPlayingOnPrimary;
                        iconWidget = Badge(
                          backgroundColor: badgeBg,
                          textColor: badgeFg,
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
                          message: tooltips[idx],
                          child: InkWell(
                            key: ValueKey<String>('nav_tab_button_$idx'),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onTabSelected(idx),
                            child: SizedBox(
                              height: MusEveePalette.navStripHeight,
                              child: Center(child: iconWidget),
                            ),
                          ),
                        ),
                      );
                    }),
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
