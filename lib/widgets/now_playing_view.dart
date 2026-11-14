import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/local_song.dart';
import '../providers/downloader_provider.dart';
import '../providers/local_music_provider.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'local_library_views.dart';
import 'pressable_scale.dart';
import 'tag_editor_sheet.dart';

/// Full-width rectangular slider track so the thin seekbar aligns 1:1 with the
/// elapsed and total duration labels positioned directly below its left and
/// right ends.
class _FullWidthSeekbarTrackShape extends RectangularSliderTrackShape {
  const _FullWidthSeekbarTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.5;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

/// Geometry and text of a single wrapped row within a lyric line.
@immutable
class LyricRowMetrics {
  final int rowIndex;
  final String text;
  final double width;
  final double height;
  final double localTop;

  const LyricRowMetrics({
    required this.rowIndex,
    required this.text,
    required this.width,
    required this.height,
    required this.localTop,
  });

  LyricRowMetrics copyWithWidthClamped(double maxWidth) {
    return LyricRowMetrics(
      rowIndex: rowIndex,
      text: text,
      width: width.clamp(0.0, maxWidth),
      height: height,
      localTop: localTop,
    );
  }
}

/// Pre-computed, cached final active typography and wrapped row layout for a
/// single lyric line so that its font size, weight, wrap count, and slot height
/// NEVER change before, during, or after a slide-up transition, and every
/// wrapped row can be positioned and centered individually.
@immutable
class CachedLyricLineMetrics {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final double lineHeight;
  final double letterSpacing;
  final int wrappedLineCount;
  final double slotHeight;
  final double columnWidth;
  final double measuredLineWidth;
  final List<LyricRowMetrics> rows;

  const CachedLyricLineMetrics({
    required this.text,
    required this.fontSize,
    required this.fontWeight,
    required this.lineHeight,
    required this.letterSpacing,
    required this.wrappedLineCount,
    required this.slotHeight,
    required this.columnWidth,
    this.measuredLineWidth = 0.0,
    this.rows = const <LyricRowMetrics>[],
  });

  CachedLyricLineMetrics copyWithContainerWidth(double nextContainerWidth) {
    final clampedRows = rows
        .map((r) => r.copyWithWidthClamped(nextContainerWidth))
        .toList(growable: false);
    double maxW = 0.0;
    for (final r in clampedRows) {
      if (r.width > maxW) {
        maxW = r.width;
      }
    }
    return CachedLyricLineMetrics(
      text: text,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      wrappedLineCount: wrappedLineCount,
      slotHeight: slotHeight,
      columnWidth: nextContainerWidth,
      measuredLineWidth: maxW.clamp(0.0, nextContainerWidth),
      rows: clampedRows,
    );
  }
}

/// Per-line hysteresis and `Curves.easeOutCubic` row-glide animation state
/// tracked across `Home ↔ Lyrics` morph frames (`180 ms`) and settled Panel 0
/// active-line transitions (`300 ms`).
class _LineMorphRowState {
  String rawText;
  int committedWrapCount;
  bool isActiveRole;
  double fontSize;
  double fromSlotHeight;
  double toSlotHeight;
  List<double> fromRowTops;
  List<double> toRowTops;
  Duration? glideStartTimeStamp;
  int glideDurationMs;
  double glideProgress;
  bool isGliding;

  _LineMorphRowState({
    required this.rawText,
    required this.committedWrapCount,
    required this.isActiveRole,
    required this.fontSize,
    required this.fromSlotHeight,
    required this.toSlotHeight,
    required this.fromRowTops,
    required this.toRowTops,
    this.glideDurationMs = NowPlayingView.lyricRowGlideDurationMs,
    this.glideProgress = 1.0,
    this.isGliding = false,
  });

  double get easedProgress => isGliding
      ? Curves.easeOutCubic.transform(glideProgress.clamp(0.0, 1.0))
      : 1.0;

  double get currentSlotHeight =>
      fromSlotHeight + (toSlotHeight - fromSlotHeight) * easedProgress;

  List<double> get currentRowTops {
    final e = easedProgress;
    return List<double>.generate(3, (r) {
      final from = r < fromRowTops.length ? fromRowTops[r] : 0.0;
      final to = r < toRowTops.length ? toRowTops[r] : 0.0;
      return from + (to - from) * e;
    }, growable: false);
  }
}

@immutable
class _ResolvedLineRowLayout {
  final CachedLyricLineMetrics metrics;
  final double animatedSlotHeight;
  final List<double> animatedRowTops;
  final bool isGliding;

  const _ResolvedLineRowLayout({
    required this.metrics,
    required this.animatedSlotHeight,
    required this.animatedRowTops,
    required this.isGliding,
  });
}

/// Snapshot of a single lyric line's vertical geometry, typography size,
/// active-color blend (`0.0 = secondary`, `1.0 = primary`), and opacity used
/// to compose `~400ms` line-change animations with `p ∈ [0.0, 1.0]`, retarget
/// mid-animation without snapping, and hand over seamlessly when `p` settles
/// to `0.0` or `1.0`.
@immutable
class _LyricLineAnimSnapshot {
  final double top;
  final double slotHeight;
  final double fontSize;
  final double colorBlend;
  final double opacity;

  const _LyricLineAnimSnapshot({
    required this.top,
    required this.slotHeight,
    required this.fontSize,
    required this.colorBlend,
    required this.opacity,
  });
}

/// Custom [ScrollController] that resolves its [initialScrollOffset] dynamically
/// at attach time so that when the settled Lyrics Stage (`p == 0.0`) mounts, its
/// viewport is already aligned to the centered active/focused line on frame 0
/// with zero handover jump.
class _DynamicInitialScrollController extends ScrollController {
  double Function()? initialOffsetResolver;

  _DynamicInitialScrollController() : super(keepScrollOffset: false);

  @override
  double get initialScrollOffset => initialOffsetResolver?.call() ?? 0.0;
}

/// Continuous disc geometry (`centerX`, `centerY`, `diameter`, `left`, `top`)
/// interpolated across the middle-zone progress `p ∈ [0.0, 2.0]`
/// (`0.0 = Lyrics`, `1.0 = Home`, `2.0 = Full Disc`).
@immutable
class DiscKeyframeGeometry {
  final double centerX;
  final double centerY;
  final double diameter;
  final double left;
  final double top;

  const DiscKeyframeGeometry({
    required this.centerX,
    required this.centerY,
    required this.diameter,
    required this.left,
    required this.top,
  });

  double get radius => diameter / 2.0;
}

enum _MiddleDragAxis {
  undecided,
  horizontal,
  vertical,
}

class NowPlayingView extends StatefulWidget {
  final VoidCallback onNavigateToDownloader;
  final VoidCallback onNavigateToFolders;
  final Future<void> Function(LocalSong song) onMoveLocalSongFolder;
  final bool isVisible;

  const NowPlayingView({
    super.key,
    required this.onNavigateToDownloader,
    required this.onNavigateToFolders,
    required this.onMoveLocalSongFolder,
    this.isVisible = true,
  });

  // ===========================================================================
  // PHASE 1.5 PAGER & DISGUISED LYRICS STAGE CONSTANTS / HELPERS
  // ===========================================================================

  /// Spatial panel order (left -> right): [0] Lyrics, [1] Home, [2] Full Disc.
  static const int lyricsPanelIndex = 0;
  static const int homePanelIndex = 1;
  static const int fullDiscPanelIndex = 2;
  static const int pagerPanelCount = 3;

  /// Opacity steps by line distance `|lineIndex - activeIndex|` on Panel 0 (Lyrics).
  static const double lyricsPanelOpacityDistance0 =
      MusEveePalette.lyricsPanelOpacityDistance0;
  static const double lyricsPanelOpacityDistance1 =
      MusEveePalette.lyricsPanelOpacityDistance1;
  static const double lyricsPanelOpacityDistance2 =
      MusEveePalette.lyricsPanelOpacityDistance2;
  static const double lyricsPanelOpacityDistance3Plus =
      MusEveePalette.lyricsPanelOpacityDistance3Plus;

  /// Resolves the opacity for a line in Panel 0 based on its distance from the active line.
  static double lyricPanelOpacityForDistance(int distance) {
    final d = distance.abs();
    if (d == 0) return lyricsPanelOpacityDistance0;
    if (d == 1) return lyricsPanelOpacityDistance1;
    if (d == 2) return lyricsPanelOpacityDistance2;
    return lyricsPanelOpacityDistance3Plus;
  }

  /// Resolves the 3 dot colors (`[0] Lyrics`, `[1] Home`, `[2] Full Disc`) for [activePageIndex].
  static List<Color> resolvePagerDotColors({
    required int activePageIndex,
    required MusEveePalette palette,
  }) {
    final clamped = activePageIndex.clamp(0, pagerPanelCount - 1);
    return List<Color>.generate(
      pagerPanelCount,
      (i) => i == clamped
          ? palette.nowPlayingPrimary
          : palette.nowPlayingInactiveIcon,
    );
  }

  /// Computes the single shared disc's position and diameter at any continuous
  /// panel progress `p ∈ [0.0, 2.0]` (`0.0 = Lyrics`, `1.0 = Home`, `2.0 = Full Disc`):
  /// - `p = 0.0` (`Lyrics`): fully off-screen to the right (`centerX > screenWidth + radius`).
  /// - `p = 1.0` (`Home`): fixed framing for ALL songs — diameter `0.95 * screenWidth`,
  ///   left edge at `0.60 * screenWidth` (center hole just outside the right frame).
  /// - `p = 2.0` (`Full Disc`): centered horizontally (`centerX = screenWidth / 2.0`),
  ///   fully visible (`diameter = min(0.95 * screenWidth, max(120.0, zoneHeight - 8.0))`).
  static DiscKeyframeGeometry computeDiscGeometryForProgress({
    required double progress,
    required double screenWidth,
    required double zoneHeight,
  }) {
    final p = progress.clamp(0.0, 2.0);

    // Keyframe p = 1.0 (Home): fixed constant for ALL songs
    final d1 = screenWidth * MusEveePalette.discDiameterFactor;
    final left1 = screenWidth * MusEveePalette.discLeftEdgeFactor;
    final cx1 = left1 + d1 / 2.0;

    // Keyframe p = 0.0 (Lyrics): fully off-screen to the right (center beyond right edge by > radius)
    final d0 = d1;
    final r0 = d0 / 2.0;
    final cx0 = screenWidth + r0 + 24.0;

    // Keyframe p = 2.0 (Full Disc): horizontally centered, clamped to zoneHeight
    final d2 = math.min(
      screenWidth * MusEveePalette.discDiameterFactor,
      math.max(120.0, zoneHeight - 8.0),
    );
    final cx2 = screenWidth / 2.0;

    final double centerX;
    final double diameter;
    if (p <= 1.0) {
      final t = p.clamp(0.0, 1.0);
      centerX = cx0 + (cx1 - cx0) * t;
      diameter = d0 + (d1 - d0) * t;
    } else {
      final t = (p - 1.0).clamp(0.0, 1.0);
      centerX = cx1 + (cx2 - cx1) * t;
      diameter = d1 + (d2 - d1) * t;
    }

    final centerY = zoneHeight / 2.0;
    final left = centerX - diameter / 2.0;
    final top = centerY - diameter / 2.0;

    return DiscKeyframeGeometry(
      centerX: centerX,
      centerY: centerY,
      diameter: diameter,
      left: left,
      top: top,
    );
  }

  /// Computes the fixed Home (`p = 1.0`) lyric column width for ALL songs
  /// (`max(110.0, screenWidth * discLeftEdgeFactor - leftPad - columnGap)`).
  static double computeStandardHomeColumnWidth(
    double screenWidth, {
    double leftPad = 26.0,
    double columnGap = 14.0,
    double? devicePixelRatio,
  }) {
    final discLeft = screenWidth * MusEveePalette.discLeftEdgeFactor;
    final rawWidth = math.max(110.0, discLeft - leftPad - columnGap);
    return devicePixelRatio != null
        ? snapToPhysicalPixel(rawWidth, devicePixelRatio)
        : rawWidth;
  }

  /// Returns the active-line offset for Full Lyrics (Panel 0 & Sheet),
  /// clamped to `[-4.0, 2.0]` so presets below `11.5 pt` remain locked at the
  /// `11.5 pt` baseline (`18.0 pt` floor) on Full Lyrics.
  static double computeStageActiveFontPrefOffset(double lyricsFontSizePt) {
    return (lyricsFontSizePt - 15.5).clamp(-4.0, 2.0);
  }

  /// Returns how many `1.0 pt` steps [lyricsFontSizePt] sits below `11.5 pt`
  /// (`0.0` for `>= 11.5 pt`; `1.0 / 2.0 / 3.0` for `10.5 / 9.5 / 8.5 pt`).
  static double _belowMinPresetSteps(double lyricsFontSizePt) {
    return (11.5 - lyricsFontSizePt).clamp(0.0, 3.0);
  }

  /// Returns the Home-column active-line preferred offset (`-4.0 .. +2.0` for
  /// `>= 11.5 pt`, stepping down `-1.5` per preset below `11.5 pt`).
  static double computeHomeActiveFontPrefOffset(double lyricsFontSizePt) {
    return computeStageActiveFontPrefOffset(lyricsFontSizePt) -
        1.5 * _belowMinPresetSteps(lyricsFontSizePt);
  }

  /// Returns the Home-column active-line minimum floor (`18.0` for `>= 11.5 pt`,
  /// stepping down `16.5 / 15.0 / 13.5` for `10.5 / 9.5 / 8.5 pt`).
  static double computeHomeActiveMinFontSize(double lyricsFontSizePt) {
    return MusEveePalette.lyricActiveMinFontSize -
        1.5 * _belowMinPresetSteps(lyricsFontSizePt);
  }

  /// Secondary (non-active) lyric font size across the `Home ↔ Lyrics` morph (`t = 1.0 - p`):
  /// interpolates from [homeFontSize] (`13.5` by default at `t = 0.0`, Home) to
  /// `lyricPanelSecondaryFontSize` (`14.5` at `t = 1.0`, Lyrics Stage).
  static double computeMorphSecondaryFontSize(
    double t, {
    double homeFontSize = MusEveePalette.lyricSecondaryFontSize,
  }) {
    final clampedT = t.clamp(0.0, 1.0);
    if (clampedT <= 1e-4) return homeFontSize;
    if (clampedT >= 1.0 - 1e-4) {
      return MusEveePalette.lyricPanelSecondaryFontSize;
    }
    return homeFontSize +
        (MusEveePalette.lyricPanelSecondaryFontSize - homeFontSize) * clampedT;
  }

  /// Horizontal translation `dx` of the Home 3-line lyrics column for `p ∈ [1.0, 2.0]`
  /// (`Home -> Full Disc` segment):
  /// - `p <= 1.0`: `0.0` (for `p ∈ [0.0, 1.0]`, the single Fluid Lyrics Morph scene is used instead)
  /// - `p -> 2.0`: glides left (`-0.32 * screenWidth`) as the disc moves to the center
  static double computeHomeLyricsDxForProgress({
    required double progress,
    required double screenWidth,
    required double columnWidth,
    double leftPad = 26.0,
  }) {
    final p = progress.clamp(0.0, 2.0);
    if (p <= 1.0) {
      return 0.0;
    } else {
      final v = p - 1.0;
      return -screenWidth * 0.32 * v;
    }
  }

  /// Opacity of the Home 3-line lyrics column for `p ∈ [1.0, 2.0]`
  /// (`Home -> Full Disc` segment):
  /// `1.0` at `p = 1.0`, fading to `0.0` as `p -> 2.0`.
  static double computeHomeLyricsOpacityForProgress(double progress) {
    final p = progress.clamp(0.0, 2.0);
    if (p <= 1.0) {
      return 1.0;
    } else {
      final v = p - 1.0;
      return (1.0 - v * 1.25).clamp(0.0, 1.0);
    }
  }

  // ===========================================================================
  // PHASE 1.7 & 1.8 FLUID ROW-LEVEL LYRICS MORPH (`p ∈ [0.0, 1.0]`, `t = 1.0 - p`),
  // WRAP HYSTERESIS (`±8 px`), ROW-GLIDE (`180 ms`), & INTRO RULE
  // ===========================================================================

  /// Vertical spacing between adjacent lyric line slots in both Home (`p = 1.0`)
  /// and the Lyrics Stage (`p = 0.0`), ensuring pixel-for-pixel vertical handover.
  static const double lyricSlotVerticalGap = 20.0;

  /// Minimum logical-pixel margin past the exact break-even width required
  /// before a lyric line may change its wrapped row count during morph.
  static const double wrapHysteresisMarginPx = 8.0;

  /// Duration (`180 ms`) for the `Curves.easeOutCubic` row-glide animation when
  /// a line's wrapped row count changes mid-morph.
  static const int lyricRowGlideDurationMs = 180;

  /// Rounds [logicalPx] to the physical device pixel grid (`(logicalPx * dpr).round() / dpr`).
  static double snapToPhysicalPixel(
    double logicalPx,
    double devicePixelRatio,
  ) {
    if (devicePixelRatio <= 0.0 || !logicalPx.isFinite) return logicalPx;
    return (logicalPx * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }

  /// Resolves the active synced lyric index using the strict rule:
  /// `active = the last line whose start time <= current position; if none qualifies, -1`.
  static int resolveActiveSyncedLyricIndex(
    List<SyncedLyricEntry> entries,
    int positionMs,
  ) {
    if (entries.isEmpty) return -1;
    int activeIdx = -1;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].timeMs <= positionMs) {
        activeIdx = i;
      } else {
        break;
      }
    }
    return activeIdx;
  }

  /// Left edge of the single morphing lyric container for `t = 1.0 - p ∈ [0.0, 1.0]`:
  /// interpolates from [homeLeftPad] (`26.0` at `t = 0.0`, Home) to [stageSidePad]
  /// (`32.0` at `t = 1.0`, Lyrics Stage).
  static double computeMorphContainerLeft({
    required double t,
    double homeLeftPad = 26.0,
    double stageSidePad = 32.0,
    double? devicePixelRatio,
  }) {
    final clampedT = t.clamp(0.0, 1.0);
    final startLeft = devicePixelRatio != null
        ? snapToPhysicalPixel(homeLeftPad, devicePixelRatio)
        : homeLeftPad;
    final endLeft = devicePixelRatio != null
        ? snapToPhysicalPixel(stageSidePad, devicePixelRatio)
        : stageSidePad;
    if (clampedT <= 1e-4) return startLeft;
    if (clampedT >= 1.0 - 1e-4) return endLeft;
    return startLeft + (endLeft - startLeft) * clampedT;
  }

  /// Width of the single morphing lyric container for `t = 1.0 - p ∈ [0.0, 1.0]`:
  /// interpolates from [homeColumnWidth] (at `t = 0.0`, Home — including Wide Lyrics
  /// width when active) to `max(140.0, screenWidth - 2 * stageSidePad)` (at `t = 1.0`, Lyrics Stage).
  static double computeMorphContainerWidth({
    required double t,
    required double homeColumnWidth,
    required double screenWidth,
    double stageSidePad = 32.0,
    double? devicePixelRatio,
  }) {
    final clampedT = t.clamp(0.0, 1.0);
    final rawStageWidth = math.max(140.0, screenWidth - stageSidePad * 2.0);
    final startWidth = devicePixelRatio != null
        ? snapToPhysicalPixel(homeColumnWidth, devicePixelRatio)
        : homeColumnWidth;
    final endWidth = devicePixelRatio != null
        ? snapToPhysicalPixel(rawStageWidth, devicePixelRatio)
        : rawStageWidth;
    if (clampedT <= 1e-4) return startWidth;
    if (clampedT >= 1.0 - 1e-4) return endWidth;
    return startWidth + (endWidth - startWidth) * clampedT;
  }

  /// Smoothstep centering blend (`0.0 -> 1.0`) applied over the second half of
  /// the travel (`t` from `0.45 -> 1.0`) so rows first expand and unwrap while
  /// still left-anchored, then settle to center as they reach the Lyrics Stage.
  static double computeMorphCenteringBlend(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    if (clampedT <= 0.45) return 0.0;
    if (clampedT >= 1.0) return 1.0;
    final u = ((clampedT - 0.45) / 0.55).clamp(0.0, 1.0);
    return u * u * (3.0 - 2.0 * u);
  }

  /// Per-row horizontal offset `rowOffsetX(t)` within the morphing container:
  /// interpolates from left-anchored (`0.0` at `t = 0.0`) to individually
  /// centered (`(containerWidth - rowWidth) / 2.0` at `t = 1.0`).
  static double computeMorphRowOffsetX({
    required double t,
    required double containerWidth,
    required double rowWidth,
    double? devicePixelRatio,
  }) {
    final blend = computeMorphCenteringBlend(t);
    if (blend <= 0.0) return 0.0;
    final clampedRowW = rowWidth.clamp(0.0, containerWidth);
    final rawCentered = math.max(0.0, (containerWidth - clampedRowW) / 2.0);
    final targetCentered = devicePixelRatio != null
        ? snapToPhysicalPixel(rawCentered, devicePixelRatio)
        : rawCentered;
    if (blend >= 1.0) return targetCentered;
    return targetCentered * blend;
  }

  /// Forwarding alias for row/line horizontal offset calculation.
  static double computeMorphLineOffsetX({
    required double t,
    required double containerWidth,
    required double lineMeasuredWidth,
    double? devicePixelRatio,
  }) {
    return computeMorphRowOffsetX(
      t: t,
      containerWidth: containerWidth,
      rowWidth: lineMeasuredWidth,
      devicePixelRatio: devicePixelRatio,
    );
  }

  /// Smoothstep fade-in factor (`0.0 -> 1.0`) for lines beyond the core three
  /// (`distance >= 2`) and the top/bottom 8% stage edge fades over `t ∈ [0.65, 1.0]`.
  static double computeMorphExtraLinesFadeFactor(double t) {
    final clampedT = t.clamp(0.0, 1.0);
    if (clampedT <= 0.65) return 0.0;
    if (clampedT >= 1.0) return 1.0;
    final u = ((clampedT - 0.65) / 0.35).clamp(0.0, 1.0);
    return u * u * (3.0 - 2.0 * u);
  }

  /// Measures a lyric line at [containerWidth] and role [fontSize] (`Poppins Regular w400`),
  /// splitting it into individual wrapped [LyricRowMetrics] (`rows`) so every row can be
  /// positioned and centered individually, and `slotHeight == sum of row heights`.
  static CachedLyricLineMetrics measureLyricLineAtWidth(
    String rawText, {
    required double containerWidth,
    required double fontSize,
    required bool isActiveRole,
    double? layoutWidthOverride,
    double? devicePixelRatio,
    TextScaler textScaler = TextScaler.noScaling,
    int? maxLinesOverride,
  }) {
    final cleaned = rawText.trim();
    final isEmptySecondary = !isActiveRole && cleaned.isEmpty;
    final displayText = isActiveRole
        ? (cleaned.isEmpty ? '♪' : cleaned)
        : (isEmptySecondary ? 'Ag' : cleaned);
    const lineHeight = MusEveePalette.lyricLineHeight;
    final letterSpacing = isActiveRole ? -0.2 : 0.0;
    final maxLines = maxLinesOverride ?? (isActiveRole ? 3 : 2);
    const fontWeight = FontWeight.w400;
    final effectiveLayoutWidth =
        math.max(1.0, layoutWidthOverride ?? containerWidth);

    final textStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: lineHeight,
      letterSpacing: letterSpacing,
    );
    final strutStyle = StrutStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: lineHeight,
      forceStrutHeight: true,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: displayText,
        style: textStyle,
      ),
      strutStyle: strutStyle,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: effectiveLayoutWidth);

    final metrics = painter.computeLineMetrics();
    final wrappedCount = math.max(1, metrics.length).clamp(1, maxLines);
    final singleRowHeight = fontSize * lineHeight;
    final rawSlotHeight = singleRowHeight * wrappedCount;
    final slotHeight = devicePixelRatio != null
        ? snapToPhysicalPixel(rawSlotHeight, devicePixelRatio)
        : rawSlotHeight;

    final List<LyricRowMetrics> rows = <LyricRowMetrics>[];
    double maxLineW = 0.0;

    if (isEmptySecondary) {
      rows.add(
        LyricRowMetrics(
          rowIndex: 0,
          text: '',
          width: 0.0,
          height: slotHeight,
          localTop: 0.0,
        ),
      );
    } else if (wrappedCount == 1) {
      final rowW = (metrics.isNotEmpty ? metrics[0].width : 0.0)
          .clamp(0.0, containerWidth);
      maxLineW = rowW;
      rows.add(
        LyricRowMetrics(
          rowIndex: 0,
          text: displayText,
          width: rowW,
          height: slotHeight,
          localTop: 0.0,
        ),
      );
    } else {
      int rowStart = 0;
      for (int r = 0; r < wrappedCount; r++) {
        while (rowStart < displayText.length &&
            (displayText.codeUnitAt(rowStart) == 0x20 ||
                displayText.codeUnitAt(rowStart) == 0x0A ||
                displayText.codeUnitAt(rowStart) == 0x0D)) {
          rowStart++;
        }

        TextRange range = painter.getLineBoundary(
          TextPosition(offset: rowStart.clamp(0, displayText.length)),
        );
        if (range.end <= rowStart && r < metrics.length) {
          final pos = painter.getPositionForOffset(
            Offset(0.1, metrics[r].baseline),
          );
          range = painter.getLineBoundary(pos);
        }
        final rowEnd = (r == wrappedCount - 1 && range.end <= rowStart)
            ? displayText.length
            : range.end.clamp(rowStart, displayText.length);
        String rowText = rowStart < displayText.length
            ? displayText.substring(rowStart, rowEnd).trim()
            : '';
        rowStart = rowEnd;
        if (r == wrappedCount - 1 &&
            rowStart < displayText.length &&
            displayText.substring(rowStart).trim().isNotEmpty &&
            rowText.isNotEmpty) {
          rowText = '$rowText…';
        }

        double rowW = 0.0;
        if (rowText.isNotEmpty) {
          final rowPainter = TextPainter(
            text: TextSpan(text: rowText, style: textStyle),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
            maxLines: 1,
          )..layout(maxWidth: math.max(effectiveLayoutWidth, containerWidth));
          rowW = rowPainter.width.clamp(0.0, containerWidth);
          rowPainter.dispose();
        }
        if (rowW > maxLineW) {
          maxLineW = rowW;
        }

        final localTop = r * singleRowHeight;
        final rowH = (r == wrappedCount - 1)
            ? math.max(1.0, slotHeight - localTop)
            : singleRowHeight;
        rows.add(
          LyricRowMetrics(
            rowIndex: r,
            text: rowText,
            width: rowW,
            height: rowH,
            localTop: localTop,
          ),
        );
      }
    }

    painter.dispose();
    final measuredLineWidth = maxLineW.clamp(0.0, containerWidth);

    return CachedLyricLineMetrics(
      text: isActiveRole ? displayText : cleaned,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      wrappedLineCount: wrappedCount,
      slotHeight: slotHeight,
      columnWidth: containerWidth,
      measuredLineWidth: measuredLineWidth,
      rows: rows,
    );
  }

  /// Measures a lyric line at [containerWidth] with a `±8.0` logical-pixel
  /// hysteresis band around any wrap break-even threshold:
  /// - A line may only decrease its wrap count (unwrap) when [containerWidth]
  ///   passes the break-even width by at least `+hysteresisMarginPx` (`8.0 px`).
  /// - When reversing, it may only increase its wrap count (re-wrap) after
  ///   passing the break-even width by at least `-hysteresisMarginPx` (`8.0 px`)
  ///   in the other direction.
  static CachedLyricLineMetrics measureLyricLineWithHysteresis(
    String rawText, {
    required double containerWidth,
    required double fontSize,
    required bool isActiveRole,
    int? previousWrapCount,
    double hysteresisMarginPx = wrapHysteresisMarginPx,
    double? devicePixelRatio,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final rawMetrics = measureLyricLineAtWidth(
      rawText,
      containerWidth: containerWidth,
      fontSize: fontSize,
      isActiveRole: isActiveRole,
      devicePixelRatio: devicePixelRatio,
      textScaler: textScaler,
    );

    if (previousWrapCount == null ||
        hysteresisMarginPx <= 0.0 ||
        rawMetrics.wrappedLineCount == previousWrapCount) {
      return rawMetrics;
    }

    if (rawMetrics.wrappedLineCount < previousWrapCount) {
      // Container widened: check whether containerWidth - margin has ALSO unwrapped
      final narrowerWidth = math.max(1.0, containerWidth - hysteresisMarginPx);
      final checkAtMinusMargin = measureLyricLineAtWidth(
        rawText,
        containerWidth: containerWidth,
        layoutWidthOverride: narrowerWidth,
        fontSize: fontSize,
        isActiveRole: isActiveRole,
        devicePixelRatio: devicePixelRatio,
        textScaler: textScaler,
      );
      if (checkAtMinusMargin.wrappedLineCount < previousWrapCount) {
        // Passed break-even by >= hysteresisMarginPx
        if (checkAtMinusMargin.wrappedLineCount ==
            rawMetrics.wrappedLineCount) {
          return rawMetrics;
        }
        return checkAtMinusMargin;
      }
      // Still within the +8px hysteresis band: hold previousWrapCount
      return checkAtMinusMargin;
    } else {
      // Container narrowed: check whether containerWidth + margin has ALSO re-wrapped
      final widerWidth = containerWidth + hysteresisMarginPx;
      final checkAtPlusMargin = measureLyricLineAtWidth(
        rawText,
        containerWidth: containerWidth,
        layoutWidthOverride: widerWidth,
        fontSize: fontSize,
        isActiveRole: isActiveRole,
        devicePixelRatio: devicePixelRatio,
        textScaler: textScaler,
      );
      if (checkAtPlusMargin.wrappedLineCount > previousWrapCount) {
        // Passed break-even in reverse direction by >= hysteresisMarginPx
        if (checkAtPlusMargin.wrappedLineCount == rawMetrics.wrappedLineCount) {
          return rawMetrics;
        }
        return checkAtPlusMargin;
      }
      // Still within the -8px hysteresis band: hold previousWrapCount
      return checkAtPlusMargin;
    }
  }

  // ===========================================================================
  // PURE HELPERS FOR "WIDE LYRICS" THRESHOLD & FONT STEPPING (TESTED WITHOUT UI)
  // ===========================================================================

  /// Returns `true` if [codeUnit] is a CJK ideograph, Hiragana, Katakana, or
  /// full-width glyph that occupies ~1.0 em horizontally.
  static bool _isWideGlyph(int codeUnit) {
    return (codeUnit >= 0x3000 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) ||
        (codeUnit >= 0xFF00 && codeUnit <= 0xFFEF);
  }

  /// Estimates the visual pixel width of [text] at [fontSize] (bold weight).
  static double estimateTextVisualWidth(
    String text, {
    required double fontSize,
  }) {
    if (text.isEmpty) return 0.0;
    double width = 0.0;
    for (int i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      if (cu == 0x20) {
        width += fontSize * 0.29;
      } else if (_isWideGlyph(cu)) {
        width += fontSize * 1.0;
      } else {
        width += fontSize * 0.55;
      }
    }
    return width;
  }

  /// Deterministically estimates how many wrapped lines [text] occupies inside
  /// [maxWidth] at [fontSize].
  static int estimateWrappedLineCount(
    String text, {
    required double maxWidth,
    required double fontSize,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 1;
    final effectiveMaxWidth = math.max(maxWidth, fontSize * 2.0);
    final paragraphs = trimmed.split('\n');
    int totalLines = 0;

    for (final para in paragraphs) {
      final p = para.trim();
      if (p.isEmpty) {
        totalLines += 1;
        continue;
      }
      final words = p.split(RegExp(r'\s+'));
      int paraLines = 1;
      double currentLineWidth = 0.0;
      final spaceWidth = fontSize * 0.29;

      for (final word in words) {
        final wordWidth = estimateTextVisualWidth(word, fontSize: fontSize);
        if (currentLineWidth == 0.0) {
          if (wordWidth <= effectiveMaxWidth) {
            currentLineWidth = wordWidth;
          } else {
            final extraLines = (wordWidth / effectiveMaxWidth).ceil();
            paraLines += extraLines - 1;
            currentLineWidth = wordWidth % effectiveMaxWidth;
            if (currentLineWidth == 0.0) {
              currentLineWidth = effectiveMaxWidth;
            }
          }
        } else if (currentLineWidth + spaceWidth + wordWidth <=
            effectiveMaxWidth) {
          currentLineWidth += spaceWidth + wordWidth;
        } else {
          paraLines += 1;
          if (wordWidth <= effectiveMaxWidth) {
            currentLineWidth = wordWidth;
          } else {
            final extraLines = (wordWidth / effectiveMaxWidth).ceil();
            paraLines += extraLines - 1;
            currentLineWidth = wordWidth % effectiveMaxWidth;
            if (currentLineWidth == 0.0) {
              currentLineWidth = effectiveMaxWidth;
            }
          }
        }
      }
      totalLines += paraLines;
    }

    return math.max(1, totalLines);
  }

  /// Steps the active lyric line font size down (`22 → 20 → 18`) if it does not
  /// fit within 3 lines at [maxWidth]. Never returns less than [minFontSize]
  /// (`18.0` by default).
  static double computeActiveLyricFontSize(
    String activeLine, {
    required double maxWidth,
    double preferredOffset = 0.0,
    double minFontSize = MusEveePalette.lyricActiveMinFontSize,
  }) {
    const candidates = <double>[
      MusEveePalette.lyricActiveMaxFontSize,
      MusEveePalette.lyricActiveMidFontSize,
      MusEveePalette.lyricActiveMinFontSize,
    ];
    for (final base in candidates) {
      final candidateSize = math.max(
        minFontSize,
        base + preferredOffset,
      );
      final lines = estimateWrappedLineCount(
        activeLine,
        maxWidth: maxWidth,
        fontSize: candidateSize,
      );
      if (lines <= 3) {
        return candidateSize;
      }
    }
    return minFontSize;
  }

  /// Measures a single lyric line's FINAL active typography (`fontSize` after
  /// `22 -> 20 -> 18` stepping, `FontWeight.w400`, `height: 1.32`, `maxLines: 3`)
  /// using Flutter's [TextPainter] at [columnWidth] so its exact wrap count,
  /// row breakdown, and slot height are known before any transition starts.
  static CachedLyricLineMetrics measureActiveLyricLine(
    String rawText, {
    required double columnWidth,
    double preferredOffset = 0.0,
    double minFontSize = MusEveePalette.lyricActiveMinFontSize,
    double? devicePixelRatio,
    TextScaler textScaler = TextScaler.noScaling,
    int maxLines = 3,
  }) {
    final cleaned = rawText.trim().isEmpty ? '♪' : rawText.trim();
    const candidates = <double>[
      MusEveePalette.lyricActiveMaxFontSize,
      MusEveePalette.lyricActiveMidFontSize,
      MusEveePalette.lyricActiveMinFontSize,
    ];
    const lineHeight = MusEveePalette.lyricLineHeight;
    const letterSpacing = -0.2;
    const fontWeight = FontWeight.w400;

    double chosenSize = minFontSize;

    for (final base in candidates) {
      final candidateSize = math.max(
        minFontSize,
        base + preferredOffset,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: cleaned,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: candidateSize,
            fontWeight: fontWeight,
            height: lineHeight,
            letterSpacing: letterSpacing,
          ),
        ),
        strutStyle: StrutStyle(
          fontFamily: 'Poppins',
          fontSize: candidateSize,
          fontWeight: fontWeight,
          height: lineHeight,
          forceStrutHeight: true,
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: columnWidth);

      final lineMetrics = painter.computeLineMetrics();
      final rawLineCount = math.max(1, lineMetrics.length);
      chosenSize = candidateSize;
      painter.dispose();
      if (rawLineCount <= maxLines) {
        break;
      }
    }

    return measureLyricLineAtWidth(
      cleaned,
      containerWidth: columnWidth,
      fontSize: chosenSize,
      isActiveRole: true,
      devicePixelRatio: devicePixelRatio,
      textScaler: textScaler,
      maxLinesOverride: maxLines,
    );
  }

  /// Measures the resting secondary slot height (`previous` / `next` line at
  /// [fontSize], `FontWeight.w400`, `maxLines: 2`). Always returns
  /// at least a single-line height (`>= 22.0 px`) even when [rawText] is empty
  /// so an empty previous/next slot NEVER collapses.
  static CachedLyricLineMetrics measureSecondaryLyricSlot(
    String rawText, {
    required double columnWidth,
    double fontSize = MusEveePalette.lyricSecondaryFontSize,
    double? devicePixelRatio,
    TextScaler textScaler = TextScaler.noScaling,
    int maxLines = 2,
  }) {
    return measureLyricLineAtWidth(
      rawText,
      containerWidth: columnWidth,
      fontSize: fontSize,
      isActiveRole: false,
      devicePixelRatio: devicePixelRatio,
      textScaler: textScaler,
      maxLinesOverride: maxLines,
    );
  }

  /// Derives the Panel 0 (Lyrics Stage) secondary (`14.5 pt`) metrics for a
  /// lyric line by locking its wrapped row breakdown (`rows` and
  /// `wrappedLineCount`) to [activeMetrics]. This guarantees that a line in the
  /// Lyrics Stage never reflows between `1 -> 2 -> 1` rows before, during, or
  /// after being played.
  static CachedLyricLineMetrics measureSecondaryLyricFromActiveMetrics(
    CachedLyricLineMetrics activeMetrics, {
    required double containerWidth,
    double fontSize = MusEveePalette.lyricPanelSecondaryFontSize,
    double? devicePixelRatio,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final cleaned = activeMetrics.text.trim();
    final isEmptySecondary = cleaned.isEmpty;
    const lineHeight = MusEveePalette.lyricLineHeight;
    const letterSpacing = 0.0;
    const fontWeight = FontWeight.w400;
    final effectiveLayoutWidth = math.max(1.0, containerWidth);

    final textStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: lineHeight,
      letterSpacing: letterSpacing,
    );

    final sourceRows = activeMetrics.rows;
    final wrappedCount = math.max(1, sourceRows.length);
    final singleRowHeight = fontSize * lineHeight;
    final rawSlotHeight = singleRowHeight * wrappedCount;
    final slotHeight = devicePixelRatio != null
        ? snapToPhysicalPixel(rawSlotHeight, devicePixelRatio)
        : rawSlotHeight;

    final List<LyricRowMetrics> rows = <LyricRowMetrics>[];
    double maxLineW = 0.0;

    if (isEmptySecondary || sourceRows.isEmpty) {
      rows.add(
        LyricRowMetrics(
          rowIndex: 0,
          text: '',
          width: 0.0,
          height: slotHeight,
          localTop: 0.0,
        ),
      );
    } else {
      for (int r = 0; r < wrappedCount; r++) {
        final rowText = sourceRows[r].text;
        double rowW = 0.0;
        if (rowText.isNotEmpty) {
          final rowPainter = TextPainter(
            text: TextSpan(text: rowText, style: textStyle),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
            maxLines: 1,
          )..layout(
              maxWidth: math.max(effectiveLayoutWidth, containerWidth) * 2.0,
            );
          rowW = rowPainter.width.clamp(0.0, containerWidth);
          rowPainter.dispose();
        }
        if (rowW > maxLineW) {
          maxLineW = rowW;
        }
        final localTop = r * singleRowHeight;
        final rowH = (r == wrappedCount - 1)
            ? math.max(1.0, slotHeight - localTop)
            : singleRowHeight;
        rows.add(
          LyricRowMetrics(
            rowIndex: r,
            text: rowText,
            width: rowW,
            height: rowH,
            localTop: localTop,
          ),
        );
      }
    }

    return CachedLyricLineMetrics(
      text: cleaned,
      fontSize: fontSize,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      letterSpacing: letterSpacing,
      wrappedLineCount: wrappedCount,
      slotHeight: slotHeight,
      columnWidth: containerWidth,
      measuredLineWidth: maxLineW.clamp(0.0, containerWidth),
      rows: rows,
    );
  }

  /// Smoothly interpolates row widths, row heights, local tops, font size, and
  /// letter spacing between [secondaryMetrics] and [activeMetrics] when both
  /// share the same canonical wrapped row count on the Lyrics Stage (`Panel 0`).
  static CachedLyricLineMetrics lerpPanel0RowMetrics({
    required CachedLyricLineMetrics secondaryMetrics,
    required CachedLyricLineMetrics activeMetrics,
    required double fontSize,
    required double slotHeight,
    required double colorBlend,
    required double containerWidth,
  }) {
    if (secondaryMetrics.rows.length != activeMetrics.rows.length ||
        secondaryMetrics.rows.isEmpty) {
      return colorBlend >= 0.5 ? activeMetrics : secondaryMetrics;
    }
    final fontSpan = activeMetrics.fontSize - secondaryMetrics.fontSize;
    final tRole = fontSpan.abs() > 1e-4
        ? ((fontSize - secondaryMetrics.fontSize) / fontSpan).clamp(0.0, 1.0)
        : colorBlend.clamp(0.0, 1.0);
    final letterSpacing = secondaryMetrics.letterSpacing +
        (activeMetrics.letterSpacing - secondaryMetrics.letterSpacing) * tRole;
    final wrappedCount = activeMetrics.rows.length;
    final singleRowHeight = slotHeight / math.max(1, wrappedCount);

    final List<LyricRowMetrics> rows = <LyricRowMetrics>[];
    double maxW = 0.0;
    for (int r = 0; r < wrappedCount; r++) {
      final secRow = secondaryMetrics.rows[r];
      final actRow = activeMetrics.rows[r];
      final rowW = (secRow.width + (actRow.width - secRow.width) * tRole)
          .clamp(0.0, containerWidth);
      if (rowW > maxW) {
        maxW = rowW;
      }
      final localTop = r * singleRowHeight;
      final rowH = (r == wrappedCount - 1)
          ? math.max(1.0, slotHeight - localTop)
          : singleRowHeight;
      rows.add(
        LyricRowMetrics(
          rowIndex: r,
          text: actRow.text,
          width: rowW,
          height: rowH,
          localTop: localTop,
        ),
      );
    }

    return CachedLyricLineMetrics(
      text: activeMetrics.text,
      fontSize: fontSize,
      fontWeight: activeMetrics.fontWeight,
      lineHeight: activeMetrics.lineHeight,
      letterSpacing: letterSpacing,
      wrappedLineCount: wrappedCount,
      slotHeight: slotHeight,
      columnWidth: containerWidth,
      measuredLineWidth: maxW.clamp(0.0, containerWidth),
      rows: rows,
    );
  }

  @override
  State<NowPlayingView> createState() => NowPlayingViewState();
}

class NowPlayingViewState extends State<NowPlayingView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _twoPi = math.pi * 2.0;
  static const double _maxAngularSpeedRadPerSec =
      _twoPi / MusEveePalette.discRotationPeriodSeconds;
  static const Duration _lyricSlideDuration = Duration(
    milliseconds: MusEveePalette.lyricSlideDurationMs,
  );
  static const Curve _lyricSlideCurve = Curves.easeOutCubic;

  final ValueNotifier<double> _discAngleRad = ValueNotifier<double>(0.0);
  Ticker? _discTicker;
  Duration? _lastTickElapsed;
  double _angularSpeedFactor = 0.0;
  bool _isAppResumed = true;
  bool _latestIsPlaying = false;
  bool _latestHasSong = false;
  LocalMusicProvider? _observedLocalProvider;

  late final AnimationController _lyricSlideController;
  late final Animation<double> _lyricSlideProgress;
  String? _lastTrackedLyricSongPath;
  int _lastObservedActiveLyricIndex = -999;
  bool _suppressNextLyricSlideFromSeek = false;
  String _outgoingTopLyricText = '';
  int _outgoingTopLyricIndex = -1;
  int _slideAnimatedLyricIndex = -999;
  int _slideFromCenterIdx = -999;
  bool _slideInterpolateRoleSize = false;
  bool _slideStartedInSettledPanel0 = false;
  final Map<int, double> _slideResidualTop = <int, double>{};
  final Map<int, double> _slideResidualSlotH = <int, double>{};
  final Map<int, double> _slideResidualFontSize = <int, double>{};
  final Map<int, double> _slideResidualColorBlend = <int, double>{};
  final Map<int, double> _slideResidualOpacity = <int, double>{};
  final Map<int, _LyricLineAnimSnapshot> _lastRenderedLineSnapshots =
      <int, _LyricLineAnimSnapshot>{};

  // Per-song cached typography & wrapped slot metrics per lyric line index
  String? _cachedMetricsSongPath;
  String _cachedMetricsTextSignature = '';
  double _cachedMetricsColumnWidth = -1.0;
  double _cachedMetricsFontOffset = -999.0;
  double _cachedMetricsMinFontSize = -999.0;
  double _cachedMetricsSecondaryFontSize = -999.0;
  int _cachedMetricsEntryCount = -1;
  final Map<int, CachedLyricLineMetrics> _cachedActiveLineMetrics =
      <int, CachedLyricLineMetrics>{};
  final Map<int, CachedLyricLineMetrics> _cachedSecondaryLineMetrics =
      <int, CachedLyricLineMetrics>{};
  CachedLyricLineMetrics? _cachedEmptySecondarySlotMetrics;

  String? _requestedOnDemandLyricsPath;
  double? _dragSeekMs;
  int _frozenLyricIndex = 0;

  // Phase 1.6: Progress-driven 3-Panel Middle Scene (p ∈ [0.0, 2.0]: 0 = Lyrics, 1 = Home, 2 = Full Disc)
  late final AnimationController _panelProgressController;
  int _currentPagerIndex = NowPlayingView.homePanelIndex;
  int _dragStartSettledIndex = NowPlayingView.homePanelIndex;
  Offset? _pointerDownLocalPos;
  double? _lastHorizontalDragX;
  _MiddleDragAxis _lockedDragAxis = _MiddleDragAxis.undecided;

  // Panel 0 (Disguised Full Lyrics Stage) scroll, Stage Mode (Rest vs Explore), & manual-scroll pause state
  final _DynamicInitialScrollController _lyricsPanelScrollController =
      _DynamicInitialScrollController();
  bool _isLyricsPanelUserScrollPaused = false;
  bool _isLyricsPanelExploreMode = false;
  late final AnimationController _lyricsStageReturnController;
  late final AnimationController _panel0TravelController;
  Timer? _lyricsPanelResumeTimer;
  String? _lastLyricsPanelScrolledSongPath;
  int _lastLyricsPanelScrolledLineIndex = -999;
  double _lastLyricsPanelZoneHeight = 0.0;
  bool _isPanel0Traveling = false;
  double _panel0TravelFromScrollOffset = 0.0;
  double _panel0TravelToScrollOffset = 0.0;
  final Map<int, double> _panel0TravelExtraDyByLine = <int, double>{};
  final Map<int, double> _lastPanel0RenderedDocTops = <int, double>{};
  double? _panel0SlideAnchorOffset;
  double? _panel0SlideTargetAnchorOffset;
  bool _panel0SlideWasTapSeek = false;
  double? _lastPanel0RenderedAnchorOffset;
  double? _returnGlideStartScrollOffset;
  double? _returnGlideTargetScrollOffset;
  bool _isLyricsPanelPointerDown = false;
  bool _pendingPanel0TapSeek = false;

  // Per-song cached line metrics for Panel 0 (centered full width)
  String? _cachedPanel0SongPath;
  String _cachedPanel0TextSignature = '';
  double _cachedPanel0ColumnWidth = -1.0;
  double _cachedPanel0HomeColumnWidth = -1.0;
  double _cachedPanel0FontOffset = -999.0;
  int _cachedPanel0EntryCount = -1;
  final Map<int, CachedLyricLineMetrics> _cachedPanel0ActiveMetrics =
      <int, CachedLyricLineMetrics>{};
  final Map<int, CachedLyricLineMetrics> _cachedPanel0SecondaryMetrics =
      <int, CachedLyricLineMetrics>{};

  // Phase 1.8: Per-line wrap hysteresis & easeOutCubic row-glide state
  Ticker? _rowGlideTicker;
  final ValueNotifier<int> _rowGlideTickVersion = ValueNotifier<int>(0);
  String? _morphRowStateSongPath;
  int _morphRowStateCenterIdx = -2;
  String? _lastPanel0ResolvedSongPath;
  int _lastPanel0ResolvedEffectiveIdx = -999;
  double? _frozenStageScrollOffsetAtDragStart;
  final Map<int, _LineMorphRowState> _lineMorphRowStates =
      <int, _LineMorphRowState>{};
  final Map<int, _LineMorphRowState> _lastRenderedLineMorphStates =
      <int, _LineMorphRowState>{};

  @visibleForTesting
  bool debugRenderMorphAtSettledEndpoints = false;

  @visibleForTesting
  bool get isRowGlideAnimating =>
      _lineMorphRowStates.values.any((s) => s.isGliding);

  @visibleForTesting
  bool get isPanel0TravelAnimating =>
      (_isPanel0Traveling && _panel0TravelController.isAnimating) ||
      isPanel0SlideAnimating;

  @visibleForTesting
  bool get isPanel0ScrollTravelControllerAnimating =>
      _isPanel0Traveling && _panel0TravelController.isAnimating;

  @visibleForTesting
  bool get isPanel0SlideAnimating =>
      _slideInterpolateRoleSize && _lyricSlideController.value < 1.0;

  @visibleForTesting
  bool isLineRowGliding(int lineIndex) =>
      _lastRenderedLineMorphStates[lineIndex]?.isGliding ?? false;

  @visibleForTesting
  int? debugCommittedWrapCountForLine(int lineIndex) =>
      _lastRenderedLineMorphStates[lineIndex]?.committedWrapCount;

  @visibleForTesting
  double? debugAnimatedSlotHeightForLine(int lineIndex) =>
      _lastRenderedLineMorphStates[lineIndex]?.currentSlotHeight;

  @visibleForTesting
  List<double>? debugAnimatedRowTopsForLine(int lineIndex) =>
      _lastRenderedLineMorphStates[lineIndex]?.currentRowTops;

  @visibleForTesting
  double? debugLiveFontSizeForLine(int lineIndex) =>
      _lastRenderedLineSnapshots[lineIndex]?.fontSize;

  @visibleForTesting
  double? debugLiveTopForLine(int lineIndex) =>
      _lastRenderedLineSnapshots[lineIndex]?.top;

  @visibleForTesting
  double? debugLiveSlotHeightForLine(int lineIndex) =>
      _lastRenderedLineSnapshots[lineIndex]?.slotHeight;

  @visibleForTesting
  double get currentDiscAngleRad => _discAngleRad.value;

  @visibleForTesting
  bool get isDiscTickerActive => _discTicker?.isActive ?? false;

  @visibleForTesting
  bool get isLyricSlideAnimating => _lyricSlideController.isAnimating;

  @visibleForTesting
  int get currentPagerIndex => _currentPagerIndex;

  @visibleForTesting
  double get currentPanelProgress => _panelProgressController.value;

  @visibleForTesting
  void debugSetPanelProgress(
    double progress, {
    bool resetRowGlideAtEndpoints = true,
  }) {
    _panelProgressController.stop();
    final clamped = progress.clamp(0.0, 2.0);
    if (_panelProgressController.value <= 1e-4 &&
        _lyricsPanelScrollController.hasClients) {
      if (!_isLyricsPanelUserScrollPaused &&
          (_lyricSlideController.isAnimating || _isPanel0Traveling)) {
        _frozenStageScrollOffsetAtDragStart = null;
      } else {
        final centerExtraDy =
            (_isPanel0Traveling && _panel0TravelController.isAnimating)
                ? (1.0 -
                        Curves.easeOutCubic
                            .transform(_panel0TravelController.value)) *
                    (_panel0TravelExtraDyByLine[
                            _lastLyricsPanelScrolledLineIndex] ??
                        0.0)
                : 0.0;
        _frozenStageScrollOffsetAtDragStart =
            _lyricsPanelScrollController.offset - centerExtraDy;
      }
    }
    if ((clamped - 1.0).abs() <= 1e-4 ||
        clamped >= 2.0 - 1e-4 ||
        (clamped <= 1e-4 &&
            _slideInterpolateRoleSize &&
            _lyricSlideController.isAnimating)) {
      _frozenStageScrollOffsetAtDragStart = null;
    }
    if (clamped > 1e-4) {
      _lastPanel0ResolvedEffectiveIdx = -999;
      _lyricsPanelResumeTimer?.cancel();
      _isLyricsPanelUserScrollPaused = false;
      _isLyricsPanelExploreMode = false;
      _isPanel0Traveling = false;
      _panel0TravelExtraDyByLine.clear();
      _lastPanel0RenderedDocTops.clear();
      _panel0SlideAnchorOffset = null;
      _panel0SlideTargetAnchorOffset = null;
      _panel0SlideWasTapSeek = false;
      _lastPanel0RenderedAnchorOffset = null;
      _slideStartedInSettledPanel0 = false;
      if (_panel0TravelController.isAnimating) {
        _panel0TravelController.stop();
      }
      _isLyricsPanelPointerDown = false;
      _pendingPanel0TapSeek = false;
      if (_lyricsStageReturnController.isAnimating ||
          _lyricsStageReturnController.value != 0.0) {
        _lyricsStageReturnController.stop();
        _lyricsStageReturnController.value = 0.0;
      }
      _returnGlideStartScrollOffset = null;
      _returnGlideTargetScrollOffset = null;
    }
    if (resetRowGlideAtEndpoints &&
        (clamped <= 1e-4 || (clamped - 1.0).abs() <= 1e-4)) {
      _isPanel0Traveling = false;
      _panel0TravelExtraDyByLine.clear();
      if (_panel0TravelController.isAnimating) {
        _panel0TravelController.stop();
      }
      _lineMorphRowStates.clear();
      _lastRenderedLineMorphStates.clear();
      _stopRowGlideTicker();
    }
    _panelProgressController.value = clamped;
  }

  @visibleForTesting
  bool get isLyricsPanelAutoScrollPaused => _isLyricsPanelUserScrollPaused;

  @visibleForTesting
  bool get isLyricsPanelInExploreMode =>
      _isLyricsPanelExploreMode && !_lyricsStageReturnController.isAnimating;

  @visibleForTesting
  bool get isLyricsPanelReturningToRest =>
      _lyricsStageReturnController.isAnimating;

  @visibleForTesting
  double get lyricsPanelExploreBlend {
    if (_lyricsStageReturnController.isAnimating) {
      final returnProgress =
          Curves.easeOutCubic.transform(_lyricsStageReturnController.value);
      return (1.0 - returnProgress).clamp(0.0, 1.0);
    }
    return _isLyricsPanelExploreMode ? 1.0 : 0.0;
  }

  @visibleForTesting
  ScrollController get lyricsPanelScrollController =>
      _lyricsPanelScrollController;

  @visibleForTesting
  Future<void> animateToPagerPanel(int pageIndex) async {
    final target = pageIndex.clamp(0, NowPlayingView.pagerPanelCount - 1);
    _dragStartSettledIndex = target;
    await _panelProgressController.animateTo(
      target.toDouble(),
      duration: const Duration(
        milliseconds: MusEveePalette.pagerSettleDurationMs,
      ),
      curve: Curves.easeOutCubic,
    );
  }

  @visibleForTesting
  CachedLyricLineMetrics? debugActiveMetricsForIndex(int index) =>
      _cachedActiveLineMetrics[index];

  @visibleForTesting
  CachedLyricLineMetrics? debugSecondaryMetricsForIndex(int index) =>
      _cachedSecondaryLineMetrics[index];

  @visibleForTesting
  CachedLyricLineMetrics? debugPanel0ActiveMetricsForIndex(int index) =>
      _cachedPanel0ActiveMetrics[index];

  @visibleForTesting
  CachedLyricLineMetrics? debugPanel0SecondaryMetricsForIndex(int index) =>
      _cachedPanel0SecondaryMetrics[index];

  static String _computeEntriesTextSignature(List<SyncedLyricEntry> entries) {
    if (entries.isEmpty) return '';
    int hash = 17;
    for (int i = 0; i < entries.length; i++) {
      hash = 0x1fffffff & (hash * 31 + entries[i].text.hashCode);
    }
    return 'n:${entries.length}|h:$hash';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _discTicker = createTicker(_onDiscTick);
    _rowGlideTicker = createTicker(_onRowGlideTick);
    _panelProgressController = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 2.0,
      value: NowPlayingView.homePanelIndex.toDouble(),
    )..addListener(_onPanelProgressChanged);
    _lyricSlideController = AnimationController(
      vsync: this,
      duration: _lyricSlideDuration,
      value: 1.0,
    )..addListener(_onLyricSlideControllerTick);
    _lyricSlideProgress = CurvedAnimation(
      parent: _lyricSlideController,
      curve: _lyricSlideCurve,
    );
    _lyricsStageReturnController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: MusEveePalette.lyricsAutoScrollDurationMs,
      ),
      value: 0.0,
    )
      ..addListener(_onLyricsStageReturnTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _isLyricsPanelExploreMode = false;
            _lyricsStageReturnController.value = 0.0;
            _returnGlideStartScrollOffset = null;
            _returnGlideTargetScrollOffset = null;
          });
        }
      });
    _panel0TravelController = AnimationController(
      vsync: this,
      duration: _lyricSlideDuration,
      value: 1.0,
    )..addListener(_onPanel0TravelTick);
  }

  void _onLyricSlideControllerTick() {
    if (!mounted) return;
    if (_lyricSlideController.value >= 1.0 &&
        _panel0SlideAnchorOffset != null) {
      final startAnchor = _panel0SlideAnchorOffset!;
      final targetAnchor = _panel0SlideTargetAnchorOffset ?? startAnchor;
      final wasTapSeek = _panel0SlideWasTapSeek;
      _panel0SlideAnchorOffset = null;
      _panel0SlideTargetAnchorOffset = null;
      _panel0SlideWasTapSeek = false;
      if (_panelProgressController.value <= 1e-4 &&
          _lyricsPanelScrollController.hasClients) {
        final pos = _lyricsPanelScrollController.position;
        final rawDesired = (!wasTapSeek &&
                _isLyricsPanelExploreMode &&
                _isLyricsPanelUserScrollPaused)
            ? (pos.pixels + (targetAnchor - startAnchor))
            : targetAnchor;
        final clampedTarget = rawDesired
            .clamp(
              pos.minScrollExtent,
              math.max(pos.minScrollExtent, pos.maxScrollExtent),
            )
            .toDouble();
        if ((pos.pixels - clampedTarget).abs() > 1e-4) {
          _lyricsPanelScrollController.jumpTo(clampedTarget);
        }
      }
    }
  }

  void _onPanel0TravelTick() {
    if (!mounted || !_isPanel0Traveling) return;
    final eased = Curves.easeOutCubic.transform(_panel0TravelController.value);
    if (_lyricsPanelScrollController.hasClients) {
      final pos = _lyricsPanelScrollController.position;
      final rawOff = _panel0TravelFromScrollOffset +
          (_panel0TravelToScrollOffset - _panel0TravelFromScrollOffset) * eased;
      final clampedOff = rawOff
          .clamp(
            pos.minScrollExtent,
            math.max(pos.minScrollExtent, pos.maxScrollExtent),
          )
          .toDouble();
      if ((pos.pixels - clampedOff).abs() > 1e-4) {
        _lyricsPanelScrollController.jumpTo(clampedOff);
      }
    }
    if (_panel0TravelController.value >= 1.0) {
      _isPanel0Traveling = false;
      _panel0TravelExtraDyByLine.clear();
    }
  }

  void _onLyricsStageReturnTick() {
    if (!mounted || !_lyricsStageReturnController.isAnimating) return;
    final startOff = _returnGlideStartScrollOffset;
    final targetOff = _returnGlideTargetScrollOffset;
    if (startOff == null ||
        targetOff == null ||
        !_lyricsPanelScrollController.hasClients) {
      return;
    }
    final eased =
        Curves.easeOutCubic.transform(_lyricsStageReturnController.value);
    final pos = _lyricsPanelScrollController.position;
    final rawOff = startOff + (targetOff - startOff) * eased;
    final clampedOff = rawOff
        .clamp(
          pos.minScrollExtent,
          math.max(pos.minScrollExtent, pos.maxScrollExtent),
        )
        .toDouble();
    if ((pos.pixels - clampedOff).abs() > 1e-4) {
      _lyricsPanelScrollController.jumpTo(clampedOff);
    }
  }

  void _onRowGlideTick(Duration _) {
    final frameStamp = SchedulerBinding.instance.currentFrameTimeStamp;
    bool anyStillGliding = false;
    bool changed = false;

    for (final state in _lineMorphRowStates.values) {
      if (!state.isGliding) continue;
      final start = state.glideStartTimeStamp;
      if (start == null) {
        state.glideStartTimeStamp = frameStamp;
        anyStillGliding = true;
        continue;
      }
      final elapsedMs = (frameStamp - start).inMicroseconds / 1000.0;
      if (elapsedMs <= 0.0) {
        anyStillGliding = true;
        continue;
      }
      final durationMs = state.glideDurationMs > 0
          ? state.glideDurationMs
          : NowPlayingView.lyricRowGlideDurationMs;
      final nextProgress = (elapsedMs / durationMs).clamp(0.0, 1.0);
      if ((nextProgress - state.glideProgress).abs() > 1e-5) {
        state.glideProgress = nextProgress;
        changed = true;
      }
      if (nextProgress >= 1.0) {
        state.isGliding = false;
        state.fromSlotHeight = state.toSlotHeight;
        state.fromRowTops = List<double>.from(state.toRowTops);
        changed = true;
      } else {
        anyStillGliding = true;
      }
    }

    if (changed) {
      _rowGlideTickVersion.value++;
    }
    if (!anyStillGliding) {
      _stopRowGlideTicker();
    }
  }

  void _stopRowGlideTicker() {
    if (_rowGlideTicker?.isActive == true) {
      _rowGlideTicker!.stop();
    }
  }

  static List<double> _canonicalRowTopsForMetrics(CachedLyricLineMetrics m) {
    final rows = m.rows;
    if (rows.isEmpty) return const <double>[0.0, 0.0, 0.0];
    return List<double>.generate(3, (r) {
      final clampedIdx = math.min(r, rows.length - 1);
      return rows[clampedIdx].localTop;
    }, growable: false);
  }

  _ResolvedLineRowLayout _resolveLineMorphMetricsAndGlide({
    required String songPath,
    required int centerIdx,
    required int lineIndex,
    required String rawText,
    required double containerWidth,
    required double fontSize,
    required bool isActiveRole,
    required double hysteresisMarginPx,
    required double devicePixelRatio,
    CachedLyricLineMetrics? lockedMetricsOverride,
    bool allowTriggerGlide = true,
    bool recordAsRenderedState = true,
    bool animateRoleChange = false,
    bool allowFontScaleGlide = false,
    int roleChangeGlideDurationMs = MusEveePalette.lyricsAutoScrollDurationMs,
  }) {
    if (_morphRowStateSongPath != songPath) {
      _morphRowStateSongPath = songPath;
      _morphRowStateCenterIdx = centerIdx;
      _lineMorphRowStates.clear();
      _lastRenderedLineMorphStates.clear();
      _stopRowGlideTicker();
    } else if (_morphRowStateCenterIdx != centerIdx) {
      _morphRowStateCenterIdx = centerIdx;
      if (!animateRoleChange) {
        _lineMorphRowStates.clear();
        _lastRenderedLineMorphStates.clear();
        _stopRowGlideTicker();
      }
    }

    final stateKey = recordAsRenderedState ? lineIndex : (-1 - lineIndex);
    final existing = _lineMorphRowStates[stateKey];
    final textChanged = existing != null && existing.rawText != rawText;
    final roleOrFontChanged = existing == null ||
        textChanged ||
        existing.isActiveRole != isActiveRole ||
        (!allowFontScaleGlide && (existing.fontSize - fontSize).abs() > 1.5);

    final CachedLyricLineMetrics metrics;
    if (lockedMetricsOverride != null) {
      metrics =
          (lockedMetricsOverride.columnWidth - containerWidth).abs() <= 0.01
              ? lockedMetricsOverride
              : lockedMetricsOverride.copyWithContainerWidth(containerWidth);
    } else {
      metrics = NowPlayingView.measureLyricLineWithHysteresis(
        rawText,
        containerWidth: containerWidth,
        fontSize: fontSize,
        isActiveRole: isActiveRole,
        previousWrapCount:
            roleOrFontChanged ? null : existing.committedWrapCount,
        hysteresisMarginPx: roleOrFontChanged ? 0.0 : hysteresisMarginPx,
        devicePixelRatio: devicePixelRatio,
      );
    }

    final targetRowTops = _canonicalRowTopsForMetrics(metrics);

    if (roleOrFontChanged) {
      if (animateRoleChange &&
          allowTriggerGlide &&
          existing != null &&
          !textChanged) {
        final oldWrap = existing.committedWrapCount;
        final newWrap = metrics.wrappedLineCount;
        final liveSlotH = existing.currentSlotHeight;

        final shouldGlide =
            (metrics.slotHeight - liveSlotH).abs() > 0.01 || newWrap != oldWrap;
        existing.rawText = rawText;
        existing.committedWrapCount = newWrap;
        existing.isActiveRole = isActiveRole;
        existing.fontSize = fontSize;
        existing.fromSlotHeight = liveSlotH;
        existing.toSlotHeight = metrics.slotHeight;
        // Keep each wrapped row at its natural canonical localTop so row 1
        // never overlaps row 0 at y = 0 when a line activates from 1 -> 2 rows.
        existing.fromRowTops = targetRowTops;
        existing.toRowTops = targetRowTops;
        existing.glideDurationMs = roleChangeGlideDurationMs;
        if (shouldGlide) {
          existing.glideStartTimeStamp =
              SchedulerBinding.instance.currentFrameTimeStamp;
          existing.glideProgress = 0.0;
          existing.isGliding = true;
          if (_rowGlideTicker != null && !_rowGlideTicker!.isActive) {
            _rowGlideTicker!.start();
          }
        } else {
          existing.glideProgress = 1.0;
          existing.isGliding = false;
        }
        if (recordAsRenderedState) {
          _lastRenderedLineMorphStates[lineIndex] = existing;
        }
        return _ResolvedLineRowLayout(
          metrics: metrics,
          animatedSlotHeight: existing.currentSlotHeight,
          animatedRowTops: existing.currentRowTops,
          isGliding: existing.isGliding,
        );
      }

      final initialState = _LineMorphRowState(
        rawText: rawText,
        committedWrapCount: metrics.wrappedLineCount,
        isActiveRole: isActiveRole,
        fontSize: fontSize,
        fromSlotHeight: metrics.slotHeight,
        toSlotHeight: metrics.slotHeight,
        fromRowTops: targetRowTops,
        toRowTops: targetRowTops,
        glideDurationMs: animateRoleChange
            ? roleChangeGlideDurationMs
            : NowPlayingView.lyricRowGlideDurationMs,
        glideProgress: 1.0,
        isGliding: false,
      );
      _lineMorphRowStates[stateKey] = initialState;
      if (recordAsRenderedState) {
        _lastRenderedLineMorphStates[lineIndex] = initialState;
      }
      return _ResolvedLineRowLayout(
        metrics: metrics,
        animatedSlotHeight: metrics.slotHeight,
        animatedRowTops: targetRowTops,
        isGliding: false,
      );
    }

    final state = existing;
    state.fontSize = fontSize;
    if (allowTriggerGlide &&
        metrics.wrappedLineCount != state.committedWrapCount) {
      final oldWrap = state.committedWrapCount;
      final newWrap = metrics.wrappedLineCount;
      final wasGliding = state.isGliding;
      final liveSlotH = state.currentSlotHeight;
      final liveRowTops = List<double>.from(state.currentRowTops);

      if (!wasGliding && newWrap < oldWrap) {
        // Merging rows (e.g., 2 -> 1 or 3 -> 2): the surviving bottom row
        // starts offset toward the absorbed row below so it glides smoothly
        // into its merged slot position over 180ms.
        final singleRowH = metrics.rows.isNotEmpty
            ? metrics.rows.first.height
            : (metrics.slotHeight / math.max(1, newWrap));
        final mergedIdx = (newWrap - 1).clamp(0, 2);
        liveRowTops[mergedIdx] = liveRowTops[mergedIdx] + singleRowH * 0.5;
      }

      state.committedWrapCount = newWrap;
      state.fromSlotHeight = liveSlotH;
      state.toSlotHeight = metrics.slotHeight;
      state.fromRowTops = liveRowTops;
      state.toRowTops = targetRowTops;
      state.glideDurationMs = NowPlayingView.lyricRowGlideDurationMs;
      state.glideStartTimeStamp =
          SchedulerBinding.instance.currentFrameTimeStamp;
      state.glideProgress = 0.0;
      state.isGliding = true;

      if (_rowGlideTicker != null && !_rowGlideTicker!.isActive) {
        _rowGlideTicker!.start();
      }
    } else if (!state.isGliding) {
      state.committedWrapCount = metrics.wrappedLineCount;
      state.fromSlotHeight = metrics.slotHeight;
      state.toSlotHeight = metrics.slotHeight;
      state.fromRowTops = targetRowTops;
      state.toRowTops = targetRowTops;
    }

    if (recordAsRenderedState) {
      _lastRenderedLineMorphStates[lineIndex] = state;
    }

    return _ResolvedLineRowLayout(
      metrics: metrics,
      animatedSlotHeight: state.currentSlotHeight,
      animatedRowTops: state.currentRowTops,
      isGliding: state.isGliding,
    );
  }

  Map<int, _LyricLineAnimSnapshot> _computeRestLineSnapshotsForCenter({
    required List<SyncedLyricEntry> entries,
    required int centerIdx,
    required double t,
    required double containerWidth,
    required double homeWidth,
    required double zoneHeight,
    required double preferredOffset,
    double? homePreferredOffset,
    double homeMinFontSize = MusEveePalette.lyricActiveMinFontSize,
    double homeSecondaryFontSize = MusEveePalette.lyricSecondaryFontSize,
    required double stageScrollDelta,
    required double dpr,
    required double emptySlotHeight,
    double? resolvedPrevSlotH,
    double? resolvedCenterSlotH,
    double? resolvedNextSlotH,
    bool includeAllStageLines = false,
  }) {
    final count = entries.length;
    if (count == 0) return const <int, _LyricLineAnimSnapshot>{};
    final clampedT = t.clamp(0.0, 1.0);
    final secFontSize = NowPlayingView.computeMorphSecondaryFontSize(
      clampedT,
      homeFontSize: homeSecondaryFontSize,
    );
    const gap = NowPlayingView.lyricSlotVerticalGap;

    double secSlotHeightFor(int k, {double? resolvedOverride}) {
      if (resolvedOverride != null) return resolvedOverride;
      if (k < 0 || k >= count) return emptySlotHeight;
      final raw = entries[k].text.trim();
      final text = raw.isEmpty ? '♪' : raw;
      if (clampedT <= 1e-4 && _cachedSecondaryLineMetrics.containsKey(k)) {
        return _cachedSecondaryLineMetrics[k]!.slotHeight;
      }
      if (clampedT >= 1.0 - 1e-4 &&
          _cachedPanel0SecondaryMetrics.containsKey(k)) {
        return _cachedPanel0SecondaryMetrics[k]!.slotHeight;
      }
      if (clampedT >= 0.5 && _cachedPanel0ActiveMetrics.containsKey(k)) {
        return NowPlayingView.measureSecondaryLyricFromActiveMetrics(
          _cachedPanel0ActiveMetrics[k]!,
          containerWidth: containerWidth,
          fontSize: secFontSize,
          devicePixelRatio: dpr,
        ).slotHeight;
      }
      return NowPlayingView.measureLyricLineAtWidth(
        text,
        containerWidth: containerWidth,
        fontSize: secFontSize,
        isActiveRole: false,
        devicePixelRatio: dpr,
      ).slotHeight;
    }

    // Section C: Intro stack (`centerIdx < 0`, i.e., `effectiveIdx == -1`):
    // Lines 0, 1, 2 fill the top, middle, and bottom slots in secondary styling
    // with 1.0 / 0.72 / 0.48 opacity at Home (t = 0.0) and 0.90 / 0.65 / 0.0 at Stage (t = 1.0).
    if (centerIdx < 0) {
      final h0 = secSlotHeightFor(0, resolvedOverride: resolvedPrevSlotH);
      final h1 = secSlotHeightFor(1, resolvedOverride: resolvedCenterSlotH);
      final h2 = secSlotHeightFor(2, resolvedOverride: resolvedNextSlotH);

      final homeMidTop = NowPlayingView.snapToPhysicalPixel(
        (zoneHeight - h1 + h0 - h2) / 2.0,
        dpr,
      );
      final homeTopTop = homeMidTop - gap - h0;
      final homeBotTop = homeMidTop + h1 + gap;

      final stageTop0 = NowPlayingView.snapToPhysicalPixel(
            (zoneHeight - h0) / 2.0,
            dpr,
          ) +
          stageScrollDelta;
      final stageTop1 = stageTop0 + h0 + gap;
      final stageTop2 = stageTop1 + h1 + gap;

      final top0 = homeTopTop + (stageTop0 - homeTopTop) * clampedT;
      final top1 = homeMidTop + (stageTop1 - homeMidTop) * clampedT;
      final top2 = homeBotTop + (stageTop2 - homeBotTop) * clampedT;

      final op0 = (MusEveePalette.homeIntroLine0Opacity +
              (NowPlayingView.lyricPanelOpacityForDistance(1) -
                      MusEveePalette.homeIntroLine0Opacity) *
                  clampedT)
          .clamp(0.0, 1.0);
      final op1 = (MusEveePalette.homeIntroLine1Opacity +
              (NowPlayingView.lyricPanelOpacityForDistance(2) -
                      MusEveePalette.homeIntroLine1Opacity) *
                  clampedT)
          .clamp(0.0, 1.0);
      final op2 = (MusEveePalette.homeIntroLine2Opacity * (1.0 - clampedT))
          .clamp(0.0, 1.0);

      final introResult = <int, _LyricLineAnimSnapshot>{
        0: _LyricLineAnimSnapshot(
          top: top0,
          slotHeight: h0,
          fontSize: secFontSize,
          colorBlend: 0.0,
          opacity: op0,
        ),
      };
      if (1 < count) {
        introResult[1] = _LyricLineAnimSnapshot(
          top: top1,
          slotHeight: h1,
          fontSize: secFontSize,
          colorBlend: 0.0,
          opacity: op1,
        );
      }
      if (2 < count) {
        introResult[2] = _LyricLineAnimSnapshot(
          top: top2,
          slotHeight: h2,
          fontSize: secFontSize,
          colorBlend: 0.0,
          opacity: op2,
        );
      }
      if (includeAllStageLines && count > 3) {
        double runningBelow = top2 + h2 + gap;
        for (int k = 3; k < count; k++) {
          final hk = secSlotHeightFor(k);
          introResult[k] = _LyricLineAnimSnapshot(
            top: runningBelow,
            slotHeight: hk,
            fontSize: secFontSize,
            colorBlend: 0.0,
            opacity: 0.0,
          );
          runningBelow += hk + gap;
        }
      }
      return introResult;
    }

    final c = centerIdx.clamp(0, count - 1);

    double fontSizeFor(int k) {
      if (k == c) {
        final raw = (k >= 0 && k < count) ? entries[k].text.trim() : '';
        final text = raw.isEmpty ? '♪' : raw;
        final homeSize = _cachedActiveLineMetrics[c]?.fontSize ??
            NowPlayingView.computeActiveLyricFontSize(
              text,
              maxWidth: homeWidth,
              preferredOffset: homePreferredOffset ?? preferredOffset,
              minFontSize: homeMinFontSize,
            );
        final stageSize = _cachedPanel0ActiveMetrics[c]?.fontSize ??
            NowPlayingView.computeActiveLyricFontSize(
              text,
              maxWidth: homeWidth,
              preferredOffset: preferredOffset,
            );
        return homeSize + (stageSize - homeSize) * clampedT;
      }
      return secFontSize;
    }

    double slotHeightFor(int k) {
      if (k < 0 || k >= count) return emptySlotHeight;
      if (k == c - 1 && resolvedPrevSlotH != null) return resolvedPrevSlotH;
      if (k == c && resolvedCenterSlotH != null) return resolvedCenterSlotH;
      if (k == c + 1 && resolvedNextSlotH != null) return resolvedNextSlotH;
      final raw = entries[k].text.trim();
      final text = raw.isEmpty ? '♪' : raw;
      if (k == c) {
        if (clampedT <= 1e-4 && _cachedActiveLineMetrics.containsKey(c)) {
          return _cachedActiveLineMetrics[c]!.slotHeight;
        }
        if (clampedT >= 1.0 - 1e-4 &&
            _cachedPanel0ActiveMetrics.containsKey(c)) {
          return _cachedPanel0ActiveMetrics[c]!.slotHeight;
        }
        return NowPlayingView.measureLyricLineAtWidth(
          text,
          containerWidth: containerWidth,
          fontSize: fontSizeFor(c),
          isActiveRole: true,
          devicePixelRatio: dpr,
        ).slotHeight;
      } else {
        return secSlotHeightFor(k);
      }
    }

    final prevH = slotHeightFor(c - 1);
    final centerH = slotHeightFor(c);
    final nextH = slotHeightFor(c + 1);

    final homeCenterTop = NowPlayingView.snapToPhysicalPixel(
      (zoneHeight - centerH + prevH - nextH) / 2.0,
      dpr,
    );
    final stageCenterTop = NowPlayingView.snapToPhysicalPixel(
          (zoneHeight - centerH) / 2.0,
          dpr,
        ) +
        stageScrollDelta;
    final centerTop =
        homeCenterTop + (stageCenterTop - homeCenterTop) * clampedT;
    final prevTop = centerTop - gap - prevH;
    final nextTop = centerTop + centerH + gap;

    final result = <int, _LyricLineAnimSnapshot>{};

    if (c - 2 >= 0) {
      final outH = slotHeightFor(c - 2);
      final outTop = prevTop - gap - outH;
      result[c - 2] = _LyricLineAnimSnapshot(
        top: outTop,
        slotHeight: outH,
        fontSize: secFontSize,
        colorBlend: 0.0,
        opacity: 0.0,
      );
      if (includeAllStageLines && c - 3 >= 0) {
        double runningAbove = outTop;
        for (int k = c - 3; k >= 0; k--) {
          final hk = slotHeightFor(k);
          runningAbove -= (gap + hk);
          result[k] = _LyricLineAnimSnapshot(
            top: runningAbove,
            slotHeight: hk,
            fontSize: secFontSize,
            colorBlend: 0.0,
            opacity: 0.0,
          );
        }
      }
    }

    if (c - 1 >= 0) {
      final stageOp = NowPlayingView.lyricPanelOpacityForDistance(1);
      final prevOp = (1.0 + (stageOp - 1.0) * clampedT).clamp(0.0, 1.0);
      result[c - 1] = _LyricLineAnimSnapshot(
        top: prevTop,
        slotHeight: prevH,
        fontSize: secFontSize,
        colorBlend: 0.0,
        opacity: prevOp,
      );
    }

    result[c] = _LyricLineAnimSnapshot(
      top: centerTop,
      slotHeight: centerH,
      fontSize: fontSizeFor(c),
      colorBlend: 1.0,
      opacity: 1.0,
    );

    if (c + 1 < count) {
      final stageOp = NowPlayingView.lyricPanelOpacityForDistance(1);
      final nextOp = (1.0 + (stageOp - 1.0) * clampedT).clamp(0.0, 1.0);
      result[c + 1] = _LyricLineAnimSnapshot(
        top: nextTop,
        slotHeight: nextH,
        fontSize: secFontSize,
        colorBlend: 0.0,
        opacity: nextOp,
      );
    }

    if (c + 2 < count) {
      final inNextH = slotHeightFor(c + 2);
      final inNextTop = nextTop + nextH + gap;
      final inNextOp = c == 0 ? 0.0 : (0.18 * (1.0 - clampedT)).clamp(0.0, 1.0);
      result[c + 2] = _LyricLineAnimSnapshot(
        top: inNextTop,
        slotHeight: inNextH,
        fontSize: secFontSize,
        colorBlend: 0.0,
        opacity: inNextOp,
      );
      if (includeAllStageLines && c + 3 < count) {
        double runningBelow = inNextTop + inNextH + gap;
        for (int k = c + 3; k < count; k++) {
          final hk = slotHeightFor(k);
          result[k] = _LyricLineAnimSnapshot(
            top: runningBelow,
            slotHeight: hk,
            fontSize: secFontSize,
            colorBlend: 0.0,
            opacity: 0.0,
          );
          runningBelow += hk + gap;
        }
      }
    }

    return result;
  }

  void _syncSharedLineChangeAnimation({
    required LocalSong song,
    required List<SyncedLyricEntry> entries,
    required int effectiveIdx,
    required bool autoScrollLyrics,
    required double currentT,
    required double containerWidth,
    required double homeWidth,
    required double zoneHeight,
    required double preferredOffset,
    double? homePreferredOffset,
    double homeMinFontSize = MusEveePalette.lyricActiveMinFontSize,
    double homeSecondaryFontSize = MusEveePalette.lyricSecondaryFontSize,
    required double stageScrollDelta,
    required double dpr,
    required double emptySlotHeight,
    required bool isInFluidMorph,
    bool allowSettledPanel0Slide = false,
    bool isPanel0TapSeek = false,
  }) {
    final isDifferentSong = _lastTrackedLyricSongPath != song.filePath ||
        _lastObservedActiveLyricIndex == -999;
    if (isDifferentSong) {
      _lastTrackedLyricSongPath = song.filePath;
      _lastObservedActiveLyricIndex = effectiveIdx;
      _suppressNextLyricSlideFromSeek = false;
      _outgoingTopLyricText = '';
      _outgoingTopLyricIndex = -1;
      _slideAnimatedLyricIndex = -999;
      _slideFromCenterIdx = -999;
      _slideInterpolateRoleSize = false;
      _slideStartedInSettledPanel0 = false;
      _slideResidualTop.clear();
      _slideResidualSlotH.clear();
      _slideResidualFontSize.clear();
      _slideResidualColorBlend.clear();
      _slideResidualOpacity.clear();
      _lastRenderedLineSnapshots.clear();
      _lyricSlideController.value = 1.0;
      return;
    }

    if (effectiveIdx == _lastObservedActiveLyricIndex) {
      if (_suppressNextLyricSlideFromSeek) {
        _suppressNextLyricSlideFromSeek = false;
      }
      if (_lyricSlideController.value >= 1.0 && _slideInterpolateRoleSize) {
        _slideInterpolateRoleSize = false;
        _slideStartedInSettledPanel0 = false;
        _slideResidualTop.clear();
        _slideResidualSlotH.clear();
        _slideResidualFontSize.clear();
        _slideResidualColorBlend.clear();
        _slideResidualOpacity.clear();
      }
      return;
    }

    final prevObservedIdx = _lastObservedActiveLyricIndex;
    _lastObservedActiveLyricIndex = effectiveIdx;

    // Section C: Promotion (-1 -> 0) and Demotion (>= 0 -> -1) always animate
    // on Home, during the Fluid Morph, and in the settled Lyrics panel (400ms Curves.easeOutCubic).
    final isPromotion = prevObservedIdx == -1 &&
        effectiveIdx == 0 &&
        (!_suppressNextLyricSlideFromSeek || isPanel0TapSeek) &&
        autoScrollLyrics;
    final isDemotion = prevObservedIdx >= 0 && effectiveIdx == -1;
    final isNaturalStep = !_suppressNextLyricSlideFromSeek &&
        prevObservedIdx >= 0 &&
        effectiveIdx == prevObservedIdx + 1 &&
        autoScrollLyrics;
    final isSettledPanel0 = !isInFluidMorph && currentT >= 1.0 - 1e-4;
    final isSettledPanel0SeekStep =
        isSettledPanel0 && isPanel0TapSeek && prevObservedIdx != effectiveIdx;
    _suppressNextLyricSlideFromSeek = false;

    if ((!isNaturalStep &&
            !isPromotion &&
            !isDemotion &&
            !isSettledPanel0SeekStep) ||
        (isSettledPanel0 && !allowSettledPanel0Slide)) {
      _outgoingTopLyricText = '';
      _outgoingTopLyricIndex = -1;
      _slideAnimatedLyricIndex = -999;
      _slideFromCenterIdx = -999;
      _slideInterpolateRoleSize = false;
      _slideStartedInSettledPanel0 = false;
      _slideResidualTop.clear();
      _slideResidualSlotH.clear();
      _slideResidualFontSize.clear();
      _slideResidualColorBlend.clear();
      _slideResidualOpacity.clear();
      _lyricSlideController.value = 1.0;
      return;
    }

    final outgoingTopIdx =
        (isPromotion || isDemotion) ? -1 : (prevObservedIdx - 1);
    if (outgoingTopIdx >= 0 && outgoingTopIdx < entries.length) {
      final rawOut = entries[outgoingTopIdx].text.trim();
      _outgoingTopLyricText = rawOut.isEmpty ? '♪' : rawOut;
      _outgoingTopLyricIndex = outgoingTopIdx;
    } else {
      _outgoingTopLyricText = '';
      _outgoingTopLyricIndex = -1;
    }

    final wasAnimating = _lyricSlideController.value < 1.0;
    final effectiveFromIdx =
        (isDemotion && !isSettledPanel0) ? 0 : prevObservedIdx;
    _slideFromCenterIdx = effectiveFromIdx;
    _slideAnimatedLyricIndex = effectiveIdx;
    _slideStartedInSettledPanel0 = isSettledPanel0;
    _slideInterpolateRoleSize = isPromotion ||
        isDemotion ||
        isInFluidMorph ||
        (isSettledPanel0 && allowSettledPanel0Slide) ||
        (wasAnimating && _slideInterpolateRoleSize);

    final restOld = _computeRestLineSnapshotsForCenter(
      entries: entries,
      centerIdx: effectiveFromIdx,
      t: currentT,
      containerWidth: containerWidth,
      homeWidth: homeWidth,
      zoneHeight: zoneHeight,
      preferredOffset: preferredOffset,
      homePreferredOffset: homePreferredOffset,
      homeMinFontSize: homeMinFontSize,
      homeSecondaryFontSize: homeSecondaryFontSize,
      stageScrollDelta: 0.0,
      dpr: dpr,
      emptySlotHeight: emptySlotHeight,
      includeAllStageLines: isSettledPanel0,
    );

    _slideResidualTop.clear();
    _slideResidualSlotH.clear();
    _slideResidualFontSize.clear();
    _slideResidualColorBlend.clear();
    _slideResidualOpacity.clear();

    final minK = isSettledPanel0
        ? 0
        : math.max(0, math.min(effectiveIdx, effectiveFromIdx) - 2);
    final maxK = isSettledPanel0
        ? (entries.length - 1)
        : math.min(
            entries.length - 1,
            math.max(effectiveIdx, effectiveFromIdx) + 2,
          );
    for (int k = minK; k <= maxK; k++) {
      final prevLive = _lastRenderedLineSnapshots[k];
      final oldRest = restOld[k];
      if (prevLive != null && oldRest != null) {
        final double prevTop = (isSettledPanel0 &&
                isPanel0TapSeek &&
                _lastPanel0RenderedDocTops.containsKey(k) &&
                _lyricsPanelScrollController.hasClients)
            ? (_lastPanel0RenderedDocTops[k]! -
                _lyricsPanelScrollController.offset)
            : prevLive.top;
        _slideResidualTop[k] = prevTop - oldRest.top;
        _slideResidualSlotH[k] = prevLive.slotHeight - oldRest.slotHeight;
        _slideResidualFontSize[k] = prevLive.fontSize - oldRest.fontSize;
        _slideResidualColorBlend[k] = prevLive.colorBlend - oldRest.colorBlend;
        _slideResidualOpacity[k] = prevLive.opacity - oldRest.opacity;
      }
    }

    if (isInFluidMorph || isSettledPanel0) {
      // Re-target the morph's frozen stage scroll offset to the new active line
      // over the ~400ms animation so settling at p = 0 or starting a swipe mid-slide never jumps.
      _frozenStageScrollOffsetAtDragStart = null;
    }

    _lyricSlideController.forward(from: 0.0);
  }

  Map<int, _LyricLineAnimSnapshot> _resolveInterpolatedLineSnapshots({
    required List<SyncedLyricEntry> entries,
    required int centerIdx,
    required double t,
    required double u,
    required double containerWidth,
    required double homeWidth,
    required double zoneHeight,
    required double preferredOffset,
    double? homePreferredOffset,
    double homeMinFontSize = MusEveePalette.lyricActiveMinFontSize,
    double homeSecondaryFontSize = MusEveePalette.lyricSecondaryFontSize,
    required double stageScrollDelta,
    required double dpr,
    required double emptySlotHeight,
    double? resolvedPrevSlotH,
    double? resolvedCenterSlotH,
    double? resolvedNextSlotH,
    bool includeAllStageLines = false,
  }) {
    final restNew = _computeRestLineSnapshotsForCenter(
      entries: entries,
      centerIdx: centerIdx,
      t: t,
      containerWidth: containerWidth,
      homeWidth: homeWidth,
      zoneHeight: zoneHeight,
      preferredOffset: preferredOffset,
      homePreferredOffset: homePreferredOffset,
      homeMinFontSize: homeMinFontSize,
      homeSecondaryFontSize: homeSecondaryFontSize,
      stageScrollDelta: stageScrollDelta,
      dpr: dpr,
      emptySlotHeight: emptySlotHeight,
      resolvedPrevSlotH: resolvedPrevSlotH,
      resolvedCenterSlotH: resolvedCenterSlotH,
      resolvedNextSlotH: resolvedNextSlotH,
      includeAllStageLines: includeAllStageLines,
    );

    if (u >= 1.0 - 1e-5 || _slideFromCenterIdx < -1) {
      for (final entry in restNew.entries) {
        _lastRenderedLineSnapshots[entry.key] = entry.value;
      }
      return restNew;
    }

    final restOld = _computeRestLineSnapshotsForCenter(
      entries: entries,
      centerIdx: _slideFromCenterIdx,
      t: t,
      containerWidth: containerWidth,
      homeWidth: homeWidth,
      zoneHeight: zoneHeight,
      preferredOffset: preferredOffset,
      homePreferredOffset: homePreferredOffset,
      homeMinFontSize: homeMinFontSize,
      homeSecondaryFontSize: homeSecondaryFontSize,
      stageScrollDelta: 0.0,
      dpr: dpr,
      emptySlotHeight: emptySlotHeight,
      includeAllStageLines: includeAllStageLines,
    );

    final clampedU = u.clamp(0.0, 1.0);
    final result = <int, _LyricLineAnimSnapshot>{};

    for (final entry in restNew.entries) {
      final k = entry.key;
      final newSnap = entry.value;
      final oldSnap = restOld[k] ?? newSnap;
      final startTop = oldSnap.top + (_slideResidualTop[k] ?? 0.0);
      final startSlotH = oldSnap.slotHeight + (_slideResidualSlotH[k] ?? 0.0);
      final startFontSize =
          oldSnap.fontSize + (_slideResidualFontSize[k] ?? 0.0);
      final startColorBlend =
          (oldSnap.colorBlend + (_slideResidualColorBlend[k] ?? 0.0))
              .clamp(0.0, 1.0);
      final startOpacity =
          (oldSnap.opacity + (_slideResidualOpacity[k] ?? 0.0)).clamp(0.0, 1.0);

      final liveSnap = _LyricLineAnimSnapshot(
        top: startTop + (newSnap.top - startTop) * clampedU,
        slotHeight: startSlotH + (newSnap.slotHeight - startSlotH) * clampedU,
        fontSize: startFontSize + (newSnap.fontSize - startFontSize) * clampedU,
        colorBlend:
            startColorBlend + (newSnap.colorBlend - startColorBlend) * clampedU,
        opacity: startOpacity + (newSnap.opacity - startOpacity) * clampedU,
      );
      result[k] = liveSnap;
      _lastRenderedLineSnapshots[k] = liveSnap;
    }

    return result;
  }

  void _onPanelProgressChanged() {
    final p = _panelProgressController.value;
    if (p > 0.001) {
      _lastPanel0ResolvedEffectiveIdx = -999;
      _lastPanel0RenderedDocTops.clear();
      _panel0SlideAnchorOffset = null;
      _panel0SlideTargetAnchorOffset = null;
      _panel0SlideWasTapSeek = false;
      _lastPanel0RenderedAnchorOffset = null;
      _slideStartedInSettledPanel0 = false;
      if (_lyricsPanelScrollController.hasClients &&
          _frozenStageScrollOffsetAtDragStart == null) {
        if (!_isLyricsPanelUserScrollPaused &&
            (_lyricSlideController.isAnimating || _isPanel0Traveling)) {
          _frozenStageScrollOffsetAtDragStart = null;
        } else {
          final centerExtraDy =
              (_isPanel0Traveling && _panel0TravelController.isAnimating)
                  ? (1.0 -
                          Curves.easeOutCubic
                              .transform(_panel0TravelController.value)) *
                      (_panel0TravelExtraDyByLine[
                              _lastLyricsPanelScrolledLineIndex] ??
                          0.0)
                  : 0.0;
          _frozenStageScrollOffsetAtDragStart =
              _lyricsPanelScrollController.offset - centerExtraDy;
        }
      }
      if (_isPanel0Traveling || _panel0TravelController.isAnimating) {
        _isPanel0Traveling = false;
        _panel0TravelExtraDyByLine.clear();
        if (_panel0TravelController.isAnimating) {
          _panel0TravelController.stop();
        }
      }
    }
    if ((p - 1.0).abs() <= 1e-4 ||
        p >= 2.0 - 1e-4 ||
        (p <= 1e-4 &&
            _slideInterpolateRoleSize &&
            _lyricSlideController.isAnimating)) {
      _frozenStageScrollOffsetAtDragStart = null;
    }
    // Reset Stage Mode to Rest Mode & freeze vertical manual-scroll pause when leaving settled Lyrics panel (p = 0)
    if (p > 0.001 &&
        (_isLyricsPanelUserScrollPaused ||
            _isLyricsPanelExploreMode ||
            _lyricsStageReturnController.isAnimating)) {
      _lyricsPanelResumeTimer?.cancel();
      _isLyricsPanelUserScrollPaused = false;
      _isLyricsPanelExploreMode = false;
      if (_lyricsStageReturnController.isAnimating ||
          _lyricsStageReturnController.value != 0.0) {
        _lyricsStageReturnController.stop();
        _lyricsStageReturnController.value = 0.0;
      }
    }
    // If the user drags into the fluid morph (0 < p < 1) while a line-change
    // animation is already in flight, continue that animation inside the morph.
    if (p > 1e-4 &&
        p < 1.0 - 1e-4 &&
        _lyricSlideController.isAnimating &&
        !_slideInterpolateRoleSize) {
      _slideInterpolateRoleSize = true;
    }
    final rounded = p.round().clamp(0, NowPlayingView.pagerPanelCount - 1);
    if (_currentPagerIndex != rounded && mounted) {
      setState(() {
        _currentPagerIndex = rounded;
      });
    }
  }

  void _settlePanelProgressAfterDrag({required double velocityPxPerSec}) {
    final currentP = _panelProgressController.value;
    int targetIndex;
    const flingThreshold = 320.0;
    if (velocityPxPerSec < -flingThreshold) {
      targetIndex = math
          .max(currentP.ceil(), _dragStartSettledIndex + 1)
          .clamp(0, NowPlayingView.pagerPanelCount - 1);
    } else if (velocityPxPerSec > flingThreshold) {
      targetIndex = math
          .min(currentP.floor(), _dragStartSettledIndex - 1)
          .clamp(0, NowPlayingView.pagerPanelCount - 1);
    } else {
      targetIndex =
          currentP.round().clamp(0, NowPlayingView.pagerPanelCount - 1);
    }
    _dragStartSettledIndex = targetIndex;
    _panelProgressController.animateTo(
      targetIndex.toDouble(),
      duration: const Duration(
        milliseconds: MusEveePalette.pagerSettleDurationMs,
      ),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProvider = Provider.of<LocalMusicProvider>(
      context,
      listen: false,
    );
    if (!identical(_observedLocalProvider, nextProvider)) {
      _observedLocalProvider?.removeListener(_onProviderStateChanged);
      _observedLocalProvider = nextProvider;
      _observedLocalProvider?.addListener(_onProviderStateChanged);
    }
  }

  void _onProviderStateChanged() {
    final p = _observedLocalProvider;
    if (p == null || !mounted) return;
    _syncDiscTickerState(
      isPlaying: p.isPlaying,
      hasSong: p.currentSong != null,
    );
  }

  @override
  void didUpdateWidget(covariant NowPlayingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isVisible != widget.isVisible) {
      _syncDiscTickerState(
        isPlaying: _latestIsPlaying,
        hasSong: _latestHasSong,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final resumed = state == AppLifecycleState.resumed;
    if (_isAppResumed != resumed) {
      _isAppResumed = resumed;
      _syncDiscTickerState(
        isPlaying: _latestIsPlaying,
        hasSong: _latestHasSong,
      );
    }
  }

  void _onDiscTick(Duration elapsed) {
    final prev = _lastTickElapsed;
    _lastTickElapsed = elapsed;
    if (prev == null) return;

    final rawDt = (elapsed - prev).inMicroseconds / 1000000.0;
    if (rawDt <= 0.0) return;
    final dt = rawDt.clamp(0.0, 5.0);

    final provider = _observedLocalProvider;
    final isPlayingNow =
        provider != null ? provider.isPlaying : _latestIsPlaying;
    final hasSongNow =
        provider != null ? (provider.currentSong != null) : _latestHasSong;
    _latestIsPlaying = isPlayingNow;
    _latestHasSong = hasSongNow;

    // If tab is hidden or app is backgrounded, stop ticker immediately (battery)
    if (!widget.isVisible || !_isAppResumed || !hasSongNow) {
      _angularSpeedFactor = 0.0;
      _stopDiscTicker();
      return;
    }

    const rampDurationSec = MusEveePalette.discSpinDownDurationMs / 1000.0;
    final prevSpeed = _angularSpeedFactor;
    final step = dt / rampDurationSec;

    if (isPlayingNow) {
      _angularSpeedFactor = (prevSpeed + step).clamp(0.0, 1.0);
      final avgSpeed = (prevSpeed + _angularSpeedFactor) * 0.5;
      final s = avgSpeed;
      final easedSpeed = s >= 1.0 ? 1.0 : (s * s * (3.0 - 2.0 * s));
      final deltaAngle = _maxAngularSpeedRadPerSec * easedSpeed * dt;
      _discAngleRad.value = (_discAngleRad.value + deltaAngle) % _twoPi;
    } else {
      final timeToZero = prevSpeed * rampDurationSec;
      final activeSpinDownDt = math.min(dt, timeToZero);
      _angularSpeedFactor = (prevSpeed - step).clamp(0.0, 1.0);
      if (activeSpinDownDt > 0.0) {
        final avgSpeed = (prevSpeed + _angularSpeedFactor) * 0.5;
        final deltaAngle =
            _maxAngularSpeedRadPerSec * avgSpeed * activeSpinDownDt;
        _discAngleRad.value = (_discAngleRad.value + deltaAngle) % _twoPi;
      }
      if (_angularSpeedFactor <= 0.0) {
        _stopDiscTicker();
      }
    }
  }

  void _syncDiscTickerState({
    required bool isPlaying,
    required bool hasSong,
  }) {
    _latestIsPlaying = isPlaying;
    _latestHasSong = hasSong;

    final ticker = _discTicker;
    if (ticker == null) return;

    if (!widget.isVisible || !_isAppResumed || !hasSong) {
      _angularSpeedFactor = 0.0;
      _stopDiscTicker();
      return;
    }

    if (isPlaying) {
      if (!ticker.isActive) {
        _lastTickElapsed = null;
        ticker.start();
      }
    } else {
      if (_angularSpeedFactor <= 0.0 && ticker.isActive) {
        _stopDiscTicker();
      }
    }
  }

  void _stopDiscTicker() {
    _lastTickElapsed = null;
    if (_discTicker?.isActive == true) {
      _discTicker!.stop();
    }
  }

  void _ensureSongLyricMetricsCached({
    required LocalSong song,
    required List<SyncedLyricEntry> entries,
    required double columnWidth,
    required double preferredOffset,
    double minFontSize = MusEveePalette.lyricActiveMinFontSize,
    double secondaryFontSize = MusEveePalette.lyricSecondaryFontSize,
    double? devicePixelRatio,
  }) {
    final textSig = _computeEntriesTextSignature(entries);
    if (_cachedMetricsSongPath == song.filePath &&
        _cachedMetricsTextSignature == textSig &&
        (_cachedMetricsColumnWidth - columnWidth).abs() < 0.01 &&
        (_cachedMetricsFontOffset - preferredOffset).abs() < 0.001 &&
        (_cachedMetricsMinFontSize - minFontSize).abs() < 0.001 &&
        (_cachedMetricsSecondaryFontSize - secondaryFontSize).abs() < 0.001 &&
        _cachedMetricsEntryCount == entries.length &&
        _cachedEmptySecondarySlotMetrics != null) {
      return;
    }

    final fontPrefChanged = _cachedMetricsSongPath == song.filePath &&
        ((_cachedMetricsFontOffset - preferredOffset).abs() >= 0.001 ||
            (_cachedMetricsMinFontSize - minFontSize).abs() >= 0.001 ||
            (_cachedMetricsSecondaryFontSize - secondaryFontSize).abs() >=
                0.001);
    if (_cachedMetricsSongPath == song.filePath &&
        ((_cachedMetricsTextSignature.isNotEmpty &&
                _cachedMetricsTextSignature != textSig) ||
            fontPrefChanged)) {
      _lineMorphRowStates.clear();
      _lastRenderedLineMorphStates.clear();
      _stopRowGlideTicker();
    }

    _cachedMetricsSongPath = song.filePath;
    _cachedMetricsTextSignature = textSig;
    _cachedMetricsColumnWidth = columnWidth;
    _cachedMetricsFontOffset = preferredOffset;
    _cachedMetricsMinFontSize = minFontSize;
    _cachedMetricsSecondaryFontSize = secondaryFontSize;
    _cachedMetricsEntryCount = entries.length;
    _cachedActiveLineMetrics.clear();
    _cachedSecondaryLineMetrics.clear();
    _cachedEmptySecondarySlotMetrics = NowPlayingView.measureSecondaryLyricSlot(
      '',
      columnWidth: columnWidth,
      fontSize: secondaryFontSize,
      devicePixelRatio: devicePixelRatio,
    );

    for (int i = 0; i < entries.length; i++) {
      final raw = entries[i].text.trim();
      final text = raw.isEmpty ? '♪' : raw;
      _cachedActiveLineMetrics[i] = NowPlayingView.measureActiveLyricLine(
        text,
        columnWidth: columnWidth,
        preferredOffset: preferredOffset,
        minFontSize: minFontSize,
        devicePixelRatio: devicePixelRatio,
      );
      _cachedSecondaryLineMetrics[i] = NowPlayingView.measureSecondaryLyricSlot(
        text,
        columnWidth: columnWidth,
        fontSize: secondaryFontSize,
        devicePixelRatio: devicePixelRatio,
      );
    }
  }

  void _ensurePanel0LyricsMetricsCached({
    required LocalSong song,
    required List<SyncedLyricEntry> entries,
    required double columnWidth,
    required double homeColumnWidth,
    required double preferredOffset,
    double? homePreferredOffset,
    double homeMinFontSize = MusEveePalette.lyricActiveMinFontSize,
    double homeSecondaryFontSize = MusEveePalette.lyricSecondaryFontSize,
    double? devicePixelRatio,
  }) {
    _ensureSongLyricMetricsCached(
      song: song,
      entries: entries,
      columnWidth: homeColumnWidth,
      preferredOffset: homePreferredOffset ?? preferredOffset,
      minFontSize: homeMinFontSize,
      secondaryFontSize: homeSecondaryFontSize,
      devicePixelRatio: devicePixelRatio,
    );
    final textSig = _computeEntriesTextSignature(entries);
    if (_cachedPanel0SongPath == song.filePath &&
        _cachedPanel0TextSignature == textSig &&
        (_cachedPanel0ColumnWidth - columnWidth).abs() < 0.01 &&
        (_cachedPanel0HomeColumnWidth - homeColumnWidth).abs() < 0.01 &&
        (_cachedPanel0FontOffset - preferredOffset).abs() < 0.001 &&
        _cachedPanel0EntryCount == entries.length &&
        _cachedPanel0ActiveMetrics.length == entries.length &&
        _cachedPanel0SecondaryMetrics.length == entries.length) {
      return;
    }

    if (_cachedPanel0SongPath == song.filePath &&
        _cachedPanel0TextSignature.isNotEmpty &&
        _cachedPanel0TextSignature != textSig) {
      _lineMorphRowStates.clear();
      _lastRenderedLineMorphStates.clear();
      _stopRowGlideTicker();
    }

    _cachedPanel0SongPath = song.filePath;
    _cachedPanel0TextSignature = textSig;
    _cachedPanel0ColumnWidth = columnWidth;
    _cachedPanel0HomeColumnWidth = homeColumnWidth;
    _cachedPanel0FontOffset = preferredOffset;
    _cachedPanel0EntryCount = entries.length;
    _cachedPanel0ActiveMetrics.clear();
    _cachedPanel0SecondaryMetrics.clear();

    final reuseHomeActiveFontSize =
        ((homePreferredOffset ?? preferredOffset) - preferredOffset).abs() <
                0.001 &&
            (homeMinFontSize - MusEveePalette.lyricActiveMinFontSize).abs() <
                0.001;
    for (int i = 0; i < entries.length; i++) {
      final raw = entries[i].text.trim();
      final text = raw.isEmpty ? '♪' : raw;
      final activeRoleFontSize =
          (reuseHomeActiveFontSize && _cachedActiveLineMetrics[i] != null)
              ? _cachedActiveLineMetrics[i]!.fontSize
              : NowPlayingView.measureActiveLyricLine(
                  text,
                  columnWidth: homeColumnWidth,
                  preferredOffset: preferredOffset,
                  devicePixelRatio: devicePixelRatio,
                ).fontSize;
      final activeMetrics = NowPlayingView.measureLyricLineAtWidth(
        text,
        containerWidth: columnWidth,
        fontSize: activeRoleFontSize,
        isActiveRole: true,
        devicePixelRatio: devicePixelRatio,
      );
      _cachedPanel0ActiveMetrics[i] = activeMetrics;
      _cachedPanel0SecondaryMetrics[i] =
          NowPlayingView.measureSecondaryLyricFromActiveMetrics(
        activeMetrics,
        containerWidth: columnWidth,
        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
        devicePixelRatio: devicePixelRatio,
      );
    }
  }

  double _panel0SlotHeightForIndex(
    int index,
    int centerIdx, {
    bool isCenterActive = true,
  }) {
    if (isCenterActive && index == centerIdx) {
      return _cachedPanel0ActiveMetrics[index]?.slotHeight ?? 26.0;
    }
    return _cachedPanel0SecondaryMetrics[index]?.slotHeight ?? 22.0;
  }

  double _computePanel0TargetScrollOffset(
    int lineIndex,
    double zoneHeight, {
    int? centerIdx,
    bool isCenterActive = true,
    double devicePixelRatio = 1.0,
  }) {
    final count = _cachedPanel0ActiveMetrics.length;
    if (count == 0) return 0.0;
    final clamped = lineIndex.clamp(0, count - 1);
    final effectiveCenterIdx = (centerIdx ?? clamped).clamp(0, count - 1);
    const gap = NowPlayingView.lyricSlotVerticalGap;

    final List<double> slotH = List<double>.generate(
      count,
      (k) => _panel0SlotHeightForIndex(
        k,
        effectiveCenterIdx,
        isCenterActive: isCenterActive,
      ),
      growable: false,
    );
    final List<double> restScreenTop = List<double>.filled(count, 0.0);
    final centerSlotH = slotH[effectiveCenterIdx];
    final stageCenterTop = NowPlayingView.snapToPhysicalPixel(
      (zoneHeight - centerSlotH) / 2.0,
      devicePixelRatio,
    );
    restScreenTop[effectiveCenterIdx] = stageCenterTop;

    if (effectiveCenterIdx > 0) {
      final prevIdx = effectiveCenterIdx - 1;
      final prevTop = NowPlayingView.snapToPhysicalPixel(
        stageCenterTop - gap - slotH[prevIdx],
        devicePixelRatio,
      );
      restScreenTop[prevIdx] = prevTop;
      double runningAbove = prevTop;
      for (int i = effectiveCenterIdx - 2; i >= 0; i--) {
        runningAbove -= (gap + slotH[i]);
        restScreenTop[i] = NowPlayingView.snapToPhysicalPixel(
          runningAbove,
          devicePixelRatio,
        );
      }
    }

    if (effectiveCenterIdx + 1 < count) {
      final nextIdx = effectiveCenterIdx + 1;
      final nextTop = NowPlayingView.snapToPhysicalPixel(
        stageCenterTop + centerSlotH + gap,
        devicePixelRatio,
      );
      restScreenTop[nextIdx] = nextTop;
      double runningBelow = nextTop + slotH[nextIdx] + gap;
      for (int i = effectiveCenterIdx + 2; i < count; i++) {
        restScreenTop[i] = NowPlayingView.snapToPhysicalPixel(
          runningBelow,
          devicePixelRatio,
        );
        runningBelow += slotH[i] + gap;
      }
    }

    final topSpacer = NowPlayingView.snapToPhysicalPixel(
      math.max(0.0, (zoneHeight - slotH[0]) / 2.0),
      devicePixelRatio,
    );
    final baseTarget = NowPlayingView.snapToPhysicalPixel(
      math.max(0.0, topSpacer - restScreenTop[0]),
      devicePixelRatio,
    );
    if (clamped == effectiveCenterIdx) {
      return baseTarget;
    }
    final itemScrollTop = baseTarget + restScreenTop[clamped];
    final itemCenterY = itemScrollTop + slotH[clamped] / 2.0;
    return math.max(0.0, itemCenterY - zoneHeight / 2.0);
  }

  ({
    List<double> slotH,
    List<double> restScreenTop,
    double targetScrollOffset,
  }) _computePanel0LayoutSnapshot({
    required int centerIdx,
    required bool isCenterActive,
    required double zoneHeight,
    required double devicePixelRatio,
  }) {
    final count = _cachedPanel0ActiveMetrics.length;
    if (count == 0) {
      return (
        slotH: const <double>[],
        restScreenTop: const <double>[],
        targetScrollOffset: 0.0,
      );
    }
    final effectiveCenterIdx = centerIdx.clamp(0, count - 1);
    const gap = NowPlayingView.lyricSlotVerticalGap;

    final List<double> slotH = List<double>.generate(
      count,
      (k) => NowPlayingView.snapToPhysicalPixel(
        _panel0SlotHeightForIndex(
          k,
          effectiveCenterIdx,
          isCenterActive: isCenterActive,
        ),
        devicePixelRatio,
      ),
      growable: false,
    );
    final List<double> restScreenTop = List<double>.filled(count, 0.0);
    final centerSlotH = slotH[effectiveCenterIdx];
    final stageCenterTop = NowPlayingView.snapToPhysicalPixel(
      (zoneHeight - centerSlotH) / 2.0,
      devicePixelRatio,
    );
    restScreenTop[effectiveCenterIdx] = stageCenterTop;

    if (effectiveCenterIdx > 0) {
      final prevIdx = effectiveCenterIdx - 1;
      final prevTop = NowPlayingView.snapToPhysicalPixel(
        stageCenterTop - gap - slotH[prevIdx],
        devicePixelRatio,
      );
      restScreenTop[prevIdx] = prevTop;
      double runningAbove = prevTop;
      for (int i = effectiveCenterIdx - 2; i >= 0; i--) {
        runningAbove -= (gap + slotH[i]);
        restScreenTop[i] = NowPlayingView.snapToPhysicalPixel(
          runningAbove,
          devicePixelRatio,
        );
      }
    }

    if (effectiveCenterIdx + 1 < count) {
      final nextIdx = effectiveCenterIdx + 1;
      final nextTop = NowPlayingView.snapToPhysicalPixel(
        stageCenterTop + centerSlotH + gap,
        devicePixelRatio,
      );
      restScreenTop[nextIdx] = nextTop;
      double runningBelow = nextTop + slotH[nextIdx] + gap;
      for (int i = effectiveCenterIdx + 2; i < count; i++) {
        restScreenTop[i] = NowPlayingView.snapToPhysicalPixel(
          runningBelow,
          devicePixelRatio,
        );
        runningBelow += slotH[i] + gap;
      }
    }

    final topSpacer = NowPlayingView.snapToPhysicalPixel(
      math.max(0.0, (zoneHeight - slotH[0]) / 2.0),
      devicePixelRatio,
    );
    final targetScrollOffset = NowPlayingView.snapToPhysicalPixel(
      math.max(0.0, topSpacer - restScreenTop[0]),
      devicePixelRatio,
    );
    return (
      slotH: slotH,
      restScreenTop: restScreenTop,
      targetScrollOffset: targetScrollOffset,
    );
  }

  void _scrollLyricsPanelToIndex(
    int lineIndex, {
    required bool animate,
    int? centerIdx,
    bool isCenterActive = true,
  }) {
    if (!mounted || !_lyricsPanelScrollController.hasClients) return;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final position = _lyricsPanelScrollController.position;
    final rawTarget = _computePanel0TargetScrollOffset(
      lineIndex,
      _lastLyricsPanelZoneHeight > 0.0
          ? _lastLyricsPanelZoneHeight
          : position.viewportDimension,
      centerIdx: centerIdx,
      isCenterActive: isCenterActive,
      devicePixelRatio: dpr,
    );
    final target = rawTarget
        .clamp(
          position.minScrollExtent,
          math.max(position.minScrollExtent, position.maxScrollExtent),
        )
        .toDouble();
    if (!animate) {
      _isPanel0Traveling = false;
      _panel0TravelExtraDyByLine.clear();
      if (_panel0TravelController.isAnimating) {
        _panel0TravelController.stop();
      }
      if ((position.pixels - target).abs() > 0.05) {
        _lyricsPanelScrollController.jumpTo(target);
      }
      return;
    }
    _isPanel0Traveling = true;
    _panel0TravelFromScrollOffset = position.pixels;
    _panel0TravelToScrollOffset = target;
    _panel0TravelExtraDyByLine.clear();
    _panel0TravelController.forward(from: 0.0);
  }

  void _onLyricsPanelUserManualScroll() {
    if (_isPanel0Traveling && _panel0TravelController.isAnimating) {
      final centerExtraDy =
          (1.0 - Curves.easeOutCubic.transform(_panel0TravelController.value)) *
              (_panel0TravelExtraDyByLine[_lastLyricsPanelScrolledLineIndex] ??
                  0.0);
      _isPanel0Traveling = false;
      _panel0TravelExtraDyByLine.clear();
      _panel0TravelController.stop();
      if (_lyricsPanelScrollController.hasClients &&
          centerExtraDy.abs() > 1e-4) {
        final pos = _lyricsPanelScrollController.position;
        final adjusted = (pos.pixels - centerExtraDy)
            .clamp(
              pos.minScrollExtent,
              math.max(pos.minScrollExtent, pos.maxScrollExtent),
            )
            .toDouble();
        _lyricsPanelScrollController.jumpTo(adjusted);
      }
    } else {
      _isPanel0Traveling = false;
      _panel0TravelExtraDyByLine.clear();
      if (_panel0TravelController.isAnimating) {
        _panel0TravelController.stop();
      }
    }
    final wasReturning = _lyricsStageReturnController.isAnimating;
    if (wasReturning) {
      _lyricsStageReturnController.stop();
      _lyricsStageReturnController.value = 0.0;
      _returnGlideStartScrollOffset = null;
      _returnGlideTargetScrollOffset = null;
      if (_lyricsPanelScrollController.hasClients) {
        // Freeze the return scroll at its exact current pixel position (no jump, no snap)
        _lyricsPanelScrollController.jumpTo(
          _lyricsPanelScrollController.offset,
        );
      }
    }
    if (!_isLyricsPanelUserScrollPaused ||
        !_isLyricsPanelExploreMode ||
        wasReturning) {
      setState(() {
        _isLyricsPanelUserScrollPaused = true;
        _isLyricsPanelExploreMode = true;
      });
    }
    _restartLyricsPanelIdleTimer();
  }

  void _restartLyricsPanelIdleTimer() {
    _lyricsPanelResumeTimer?.cancel();
    _lyricsPanelResumeTimer = Timer(
      const Duration(
        seconds: MusEveePalette.lyricsManualScrollResumeDelaySeconds,
      ),
      _onLyricsPanelIdleTimeout,
    );
  }

  void _onLyricsPanelIdleTimeout() {
    if (!mounted) return;
    final targetIdx = _lastLyricsPanelScrolledLineIndex >= 0
        ? _lastLyricsPanelScrolledLineIndex
        : 0;
    final isCenterAct = _lastPanel0ResolvedEffectiveIdx >= 0;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    if (_lyricsPanelScrollController.hasClients) {
      final pos = _lyricsPanelScrollController.position;
      final rawTarget = _computePanel0TargetScrollOffset(
        targetIdx,
        _lastLyricsPanelZoneHeight > 0.0
            ? _lastLyricsPanelZoneHeight
            : pos.viewportDimension,
        centerIdx: targetIdx,
        isCenterActive: isCenterAct,
        devicePixelRatio: dpr,
      );
      _returnGlideStartScrollOffset = pos.pixels;
      _returnGlideTargetScrollOffset = rawTarget.clamp(
        pos.minScrollExtent,
        math.max(pos.minScrollExtent, pos.maxScrollExtent),
      );
    } else {
      _returnGlideStartScrollOffset = null;
      _returnGlideTargetScrollOffset = null;
    }
    _isPanel0Traveling = false;
    _panel0TravelExtraDyByLine.clear();
    if (_panel0TravelController.isAnimating) {
      _panel0TravelController.stop();
    }
    setState(() {
      _isLyricsPanelUserScrollPaused = false;
      _isLyricsPanelExploreMode = true;
    });
    _lyricsStageReturnController.forward(from: 0.0);
  }

  void _seekFromUserGesture(LocalMusicProvider localProvider, int timeMs) {
    _suppressNextLyricSlideFromSeek = true;
    localProvider.seekTo(timeMs);
  }

  @override
  void dispose() {
    _lyricsPanelResumeTimer?.cancel();
    _observedLocalProvider?.removeListener(_onProviderStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _discTicker?.dispose();
    _rowGlideTicker?.dispose();
    _rowGlideTickVersion.dispose();
    _lyricSlideController.dispose();
    _lyricsStageReturnController.dispose();
    _panel0TravelController.dispose();
    _panelProgressController.dispose();
    _lyricsPanelScrollController.dispose();
    _discAngleRad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;

    return Consumer2<LocalMusicProvider, DownloaderProvider>(
      builder: (context, localProvider, downloaderProvider, _) {
        final song = localProvider.currentSong;
        _syncDiscTickerState(
          isPlaying: localProvider.isPlaying,
          hasSong: song != null,
        );

        // Trigger on-demand USLT lyrics hydration if needed
        if (song != null &&
            song.hasLyrics &&
            !song.isLyricsLoadedInMemory &&
            _requestedOnDemandLyricsPath != song.filePath) {
          _requestedOnDemandLyricsPath = song.filePath;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              localProvider.ensureSongLyricsLoaded(song);
            }
          });
        }

        return ColoredBox(
          color: palette.nowPlayingBg,
          child: SafeArea(
            bottom: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. TOP BAR (ONLY `...` ON LEFT & FAVORITE HEART ON RIGHT)
                    _buildTopBar(
                      context: context,
                      localProvider: localProvider,
                      downloaderProvider: downloaderProvider,
                      song: song,
                      palette: palette,
                    ),

                    // 2. MIDDLE ZONE — 3-PANEL HORIZONTAL PAGER ([0] Lyrics, [1] Home, [2] Full Disc)
                    Expanded(
                      child: _buildMiddleThreePanelPager(
                        context: context,
                        localProvider: localProvider,
                        downloaderProvider: downloaderProvider,
                        song: song,
                        palette: palette,
                      ),
                    ),

                    // 2.5. 3-DOT PAGER INDICATOR (CENTERED BELOW MIDDLE ZONE, ABOVE SONG TITLE)
                    const SizedBox(height: 6),
                    _buildPagerDotsIndicator(palette: palette),
                    const SizedBox(height: 12),

                    // 3. SONG INFO (CENTERED BOLD TITLE + GRAY ARTIST)
                    _buildSongInfoSection(song: song, palette: palette),
                    const SizedBox(height: 14),

                    // 4. THIN SEEKBAR WITH TIMESTAMPS BELOW ENDS
                    _buildSeekbarSection(
                      localProvider: localProvider,
                      song: song,
                      palette: palette,
                    ),
                    const SizedBox(height: 12),

                    // 5. TRANSPORT ROW (ONLY 5 ELEMENTS: SHUFFLE, PREV, PLAY/PAUSE, NEXT, REPEAT)
                    _buildTransportRow(
                      context: context,
                      localProvider: localProvider,
                      song: song,
                      palette: palette,
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
                if (localProvider.isProcessingLocalTag)
                  Container(
                    color: palette.nowPlayingBg.withValues(alpha: 0.78),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: palette.nowPlayingPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          song != null
                              ? AppStrings.tr(
                                  'Memperbarui tag ${song.audioFormatLabel}...',
                                  'Updating ${song.audioFormatLabel} tags...',
                                  context,
                                )
                              : AppStrings.tr(
                                  'Memperbarui tag audio...',
                                  'Updating audio tags...',
                                  context,
                                ),
                          style: TextStyle(
                            color: palette.nowPlayingPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // 1. TOP BAR (CLEAN, ONLY 2 ICONS: `...` AND FAVORITE HEART)
  // ===========================================================================
  Widget _buildTopBar({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
    required MusEveePalette palette,
  }) {
    final isFav = song != null && localProvider.isFavorite(song.filePath);

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top-left: `...` overflow icon
            Tooltip(
              message: AppStrings.tr(
                'Menu Cepat Lagu',
                'Song & Audio Menu',
                context,
              ),
              child: MographSpringTap(
                pressedScale: 0.82,
                tapRotationRad: 0.20,
                child: InkWell(
                  key: const ValueKey<String>('now_playing_overflow_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _showOverflowMenuSheet(
                    context: context,
                    localProvider: localProvider,
                    downloaderProvider: downloaderProvider,
                    song: song,
                  ),
                  child: SizedBox(
                    width: MusEveePalette.minTouchTargetSize,
                    height: MusEveePalette.minTouchTargetSize,
                    child: Center(
                      child: Image.asset(
                        'assets/icons/dot.png',
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                        color: palette.nowPlayingPrimary,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Top-right: Favorite Heart (red when active, pale gray outline when inactive)
            Tooltip(
              message: AppStrings.tr('Favorit', 'Favorite', context),
              child: MographSpringTap(
                pressedScale: 0.78,
                enabled: song != null,
                child: InkWell(
                  key: const ValueKey<String>('now_playing_favorite_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: song == null
                      ? null
                      : () => localProvider.toggleFavorite(song.filePath),
                  child: SizedBox(
                    width: MusEveePalette.minTouchTargetSize,
                    height: MusEveePalette.minTouchTargetSize,
                    child: Center(
                      child: MographStatePop(
                        stateKey: isFav,
                        scaleBoost: isFav ? 0.28 : 0.10,
                        rotationKickRad: isFav ? -0.24 : 0.12,
                        child: MographAnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          beginScale: 0.65,
                          child: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key: ValueKey<bool>(isFav),
                            size: 24,
                            color: isFav
                                ? palette.favoriteActive
                                : palette.nowPlayingInactiveIcon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. MIDDLE ZONE — PROGRESS-DRIVEN 3-PANEL SCENE (p ∈ [0.0, 2.0]: 0 = Lyrics, 1 = Home, 2 = Full Disc)
  // ===========================================================================
  Widget _buildMiddleThreePanelPager({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
    required MusEveePalette palette,
  }) {
    return LayoutBuilder(
      key: const ValueKey<String>('now_playing_middle_pager'),
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final zoneHeight = constraints.maxHeight;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;

        const leftPad = 26.0;
        const columnGap = 14.0;
        final homeLeftSnapped =
            NowPlayingView.snapToPhysicalPixel(leftPad, dpr);
        final homeTargetWidthSnapped =
            NowPlayingView.computeStandardHomeColumnWidth(
          screenWidth,
          leftPad: leftPad,
          columnGap: columnGap,
          devicePixelRatio: dpr,
        );

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _pointerDownLocalPos = event.localPosition;
            _lastHorizontalDragX = event.localPosition.dx;
            _lockedDragAxis = _MiddleDragAxis.undecided;
            if (_panelProgressController.value <= 1e-4 &&
                _lyricsPanelScrollController.hasClients) {
              if (!_isLyricsPanelUserScrollPaused &&
                  (_lyricSlideController.isAnimating || _isPanel0Traveling)) {
                _frozenStageScrollOffsetAtDragStart = null;
              } else {
                final centerExtraDy =
                    (_isPanel0Traveling && _panel0TravelController.isAnimating)
                        ? (1.0 -
                                Curves.easeOutCubic
                                    .transform(_panel0TravelController.value)) *
                            (_panel0TravelExtraDyByLine[
                                    _lastLyricsPanelScrolledLineIndex] ??
                                0.0)
                        : 0.0;
                _frozenStageScrollOffsetAtDragStart =
                    _lyricsPanelScrollController.offset - centerExtraDy;
              }
            }
            _dragStartSettledIndex = _panelProgressController.value
                .round()
                .clamp(0, NowPlayingView.pagerPanelCount - 1);
          },
          onPointerMove: (event) {
            final start = _pointerDownLocalPos;
            if (start != null && _lockedDragAxis == _MiddleDragAxis.undecided) {
              final dx = (event.localPosition.dx - start.dx).abs();
              final dy = (event.localPosition.dy - start.dy).abs();
              final distance = math.sqrt(dx * dx + dy * dy);
              // Direction lock within the first ~10px of a drag in the middle zone
              if (distance >= 10.0) {
                _lockedDragAxis = dx >= dy
                    ? _MiddleDragAxis.horizontal
                    : _MiddleDragAxis.vertical;
              }
            }
          },
          onPointerUp: (_) {
            _pointerDownLocalPos = null;
            _lastHorizontalDragX = null;
          },
          onPointerCancel: (_) {
            _pointerDownLocalPos = null;
            _lastHorizontalDragX = null;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) {
              if (_lockedDragAxis == _MiddleDragAxis.vertical) return;
              _lockedDragAxis = _MiddleDragAxis.horizontal;
              if (_panelProgressController.value <= 1e-4 &&
                  _lyricsPanelScrollController.hasClients) {
                if (!_isLyricsPanelUserScrollPaused &&
                    (_lyricSlideController.isAnimating || _isPanel0Traveling)) {
                  _frozenStageScrollOffsetAtDragStart = null;
                } else {
                  final centerExtraDy = (_isPanel0Traveling &&
                          _panel0TravelController.isAnimating)
                      ? (1.0 -
                              Curves.easeOutCubic
                                  .transform(_panel0TravelController.value)) *
                          (_panel0TravelExtraDyByLine[
                                  _lastLyricsPanelScrolledLineIndex] ??
                              0.0)
                      : 0.0;
                  _frozenStageScrollOffsetAtDragStart =
                      _lyricsPanelScrollController.offset - centerExtraDy;
                }
              }
              _panelProgressController.stop();
              final prevX = _lastHorizontalDragX;
              _lastHorizontalDragX = details.localPosition.dx;
              if (prevX != null && screenWidth > 0.0) {
                final initialDx = details.localPosition.dx - prevX;
                if (initialDx.abs() < screenWidth) {
                  _panelProgressController.value =
                      (_panelProgressController.value -
                              (initialDx / screenWidth))
                          .clamp(0.0, 2.0);
                }
              }
            },
            onHorizontalDragUpdate: (details) {
              if (_lockedDragAxis == _MiddleDragAxis.vertical) return;
              _lockedDragAxis = _MiddleDragAxis.horizontal;
              _lastHorizontalDragX = details.localPosition.dx;
              if (screenWidth <= 0.0) return;
              final deltaDx = details.primaryDelta ?? details.delta.dx;
              final nextP =
                  (_panelProgressController.value - (deltaDx / screenWidth))
                      .clamp(0.0, 2.0);
              _panelProgressController.value = nextP;
            },
            onHorizontalDragEnd: (details) {
              if (_lockedDragAxis == _MiddleDragAxis.vertical) {
                _lockedDragAxis = _MiddleDragAxis.undecided;
                return;
              }
              _lockedDragAxis = _MiddleDragAxis.undecided;
              _settlePanelProgressAfterDrag(
                velocityPxPerSec: details.primaryVelocity ?? 0.0,
              );
            },
            onHorizontalDragCancel: () {
              if (_lockedDragAxis == _MiddleDragAxis.vertical) {
                _lockedDragAxis = _MiddleDragAxis.undecided;
                return;
              }
              _lockedDragAxis = _MiddleDragAxis.undecided;
              _settlePanelProgressAfterDrag(velocityPxPerSec: 0.0);
            },
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _panelProgressController,
                builder: (context, _) {
                  final p = _panelProgressController.value.clamp(0.0, 2.0);
                  const settledEps = 1e-4;
                  final isSettledAt0 = p <= settledEps;
                  final isSettledAt1 = (p - 1.0).abs() <= settledEps;
                  final isSettledAt2 = p >= 2.0 - settledEps;

                  // Home -> Full Disc (p ∈ [1.0, 2.0]) choreography (unchanged from Phase 1.6)
                  final homeLyricsOpacity =
                      NowPlayingView.computeHomeLyricsOpacityForProgress(p);
                  final homeLyricsDx =
                      NowPlayingView.computeHomeLyricsDxForProgress(
                    progress: p,
                    screenWidth: screenWidth,
                    columnWidth: homeTargetWidthSnapped,
                    leftPad: homeLeftSnapped,
                  );

                  // Settled-state exclusivity:
                  // - p == 0.0: ONLY the interactive scrollable Lyrics Stage is mounted
                  // - 0.0 < p < 1.0: ONLY the single Fluid Lyrics Morph scene (t = 1 - p) is mounted
                  // - 1.0 <= p < 2.0: ONLY the Home 3-line column is mounted (fading out toward Full Disc)
                  // - p == 2.0: NO lyrics layer is mounted
                  final renderSettledLyricsStage =
                      isSettledAt0 && !debugRenderMorphAtSettledEndpoints;
                  final renderFluidMorphScene =
                      (!isSettledAt0 && !isSettledAt1 && p < 1.0) ||
                          (debugRenderMorphAtSettledEndpoints &&
                              p <= 1.0 + settledEps);
                  final renderHomeLyricsColumn =
                      (isSettledAt1 && !debugRenderMorphAtSettledEndpoints) ||
                          (!isSettledAt1 &&
                              !isSettledAt2 &&
                              p > 1.0 &&
                              homeLyricsOpacity > 0.001);

                  // Single Shared Disc choreography (p = 0.0: off-screen right; p = 1.0: Home right-cropped; p = 2.0: Full Disc centered)
                  final discGeom =
                      NowPlayingView.computeDiscGeometryForProgress(
                    progress: p,
                    screenWidth: screenWidth,
                    zoneHeight: zoneHeight,
                  );

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    fit: StackFit.expand,
                    children: [
                      // LAYER 1A (p == 0.0 settled): INTERACTIVE SCROLLABLE LYRICS STAGE
                      if (renderSettledLyricsStage)
                        Positioned.fill(
                          child: _buildLyricsStagePanel(
                            context: context,
                            localProvider: localProvider,
                            downloaderProvider: downloaderProvider,
                            song: song,
                            palette: palette,
                            homeColumnWidth: homeTargetWidthSnapped,
                          ),
                        ),

                      // LAYER 1B (0.0 < p < 1.0): SINGLE FLUID LYRICS MORPH SCENE (t = 1.0 - p)
                      if (renderFluidMorphScene)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _buildFluidMorphLyricsScene(
                              context: context,
                              localProvider: localProvider,
                              downloaderProvider: downloaderProvider,
                              song: song,
                              palette: palette,
                              t: (1.0 - p).clamp(0.0, 1.0),
                              screenWidth: screenWidth,
                              zoneHeight: zoneHeight,
                              homeColumnWidth: homeTargetWidthSnapped,
                              homeLeftPad: homeLeftSnapped,
                            ),
                          ),
                        ),

                      // LAYER 2 (1.0 <= p < 2.0): HOME 3-LINE LYRICS COLUMN
                      if (renderHomeLyricsColumn)
                        Positioned(
                          left: homeLeftSnapped,
                          top: 0,
                          bottom: 0,
                          width: homeTargetWidthSnapped,
                          child: IgnorePointer(
                            ignoring: !isSettledAt1,
                            child: Opacity(
                              key: const ValueKey<String>(
                                'now_playing_home_lyrics_opacity',
                              ),
                              opacity: homeLyricsOpacity,
                              child: Transform.translate(
                                key: const ValueKey<String>(
                                  'now_playing_home_lyrics_transform',
                                ),
                                offset: Offset(homeLyricsDx, 0.0),
                                child: SizedBox(
                                  width: homeTargetWidthSnapped,
                                  height: zoneHeight,
                                  child: _buildLeftLyricsColumn(
                                    context: context,
                                    localProvider: localProvider,
                                    downloaderProvider: downloaderProvider,
                                    song: song,
                                    palette: palette,
                                    columnWidth: homeTargetWidthSnapped,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      if (p.round() == NowPlayingView.fullDiscPanelIndex)
                        const Positioned.fill(
                          key: ValueKey<String>(
                            'now_playing_full_disc_panel',
                          ),
                          child: IgnorePointer(child: SizedBox.expand()),
                        ),

                      // LAYER 3: THE ONE SHARED ROTATING DISC (Never unmounted, never duplicated)
                      Positioned(
                        key: const ValueKey<String>(
                          'now_playing_single_shared_disc',
                        ),
                        left: discGeom.left,
                        top: discGeom.top,
                        width: discGeom.diameter,
                        height: discGeom.diameter,
                        child: IgnorePointer(
                          ignoring: !isSettledAt1 && !isSettledAt2,
                          child: _buildAnimatedTrackDisc(
                            localProvider: localProvider,
                            song: song,
                            palette: palette,
                            discDiameter: discGeom.diameter,
                            slideInOnTrackChange: p < 1.5,
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
      },
    );
  }

  Widget _buildPagerDotsIndicator({required MusEveePalette palette}) {
    const dotSize = MusEveePalette.pagerDotSize;
    const dotSpacing = MusEveePalette.pagerDotSpacing;

    return AnimatedBuilder(
      animation: _panelProgressController,
      builder: (context, _) {
        final activeIndex = _panelProgressController.value
            .round()
            .clamp(0, NowPlayingView.pagerPanelCount - 1);
        final dotColors = NowPlayingView.resolvePagerDotColors(
          activePageIndex: activeIndex,
          palette: palette,
        );

        return Row(
          key: const ValueKey<String>('now_playing_pager_dots'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(NowPlayingView.pagerPanelCount, (i) {
            return Padding(
              padding: EdgeInsets.only(
                right:
                    i < NowPlayingView.pagerPanelCount - 1 ? dotSpacing : 0.0,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => animateToPagerPanel(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: AnimatedContainer(
                    key: ValueKey<String>('now_playing_pager_dot_$i'),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColors[i],
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  /// Shared row-level lyric renderer used identically by:
  /// - Settled Lyrics Stage (`p == 0.0`, `centeringT == 1.0`)
  /// - Fluid Lyrics Morph (`0.0 < p < 1.0`, `centeringT == t`)
  /// - Settled Home 3-Line Column (`p == 1.0`, `centeringT == 0.0`)
  Widget _buildLyricRowBlock({
    required CachedLyricLineMetrics metrics,
    required double containerWidth,
    required double centeringT,
    required Color textColor,
    required double devicePixelRatio,
    double? fontSizeOverride,
    double? slotHeightOverride,
    List<double>? animatedRowTops,
    bool snapRowPositions = false,
    String? rowKeyPrefix,
    Key? firstRowTextKey,
  }) {
    final rows = metrics.rows;
    if (rows.isEmpty) {
      return const SizedBox.expand();
    }

    final effectiveFontSize = fontSizeOverride ?? metrics.fontSize;
    final fontScale =
        metrics.fontSize > 0.0 ? (effectiveFontSize / metrics.fontSize) : 1.0;
    final heightScale = (slotHeightOverride != null && metrics.slotHeight > 0.0)
        ? (slotHeightOverride / metrics.slotHeight)
        : 1.0;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: <Widget>[
        for (int r = 0; r < rows.length; r++)
          Builder(
            builder: (context) {
              final row = rows[r];
              final rawTop =
                  ((animatedRowTops != null && r < animatedRowTops.length)
                          ? animatedRowTops[r]
                          : row.localTop) *
                      heightScale;
              final rowTop = rawTop;
              final scaledRowWidth =
                  (row.width * fontScale).clamp(0.0, containerWidth);
              final rowOffsetX = NowPlayingView.computeMorphRowOffsetX(
                t: centeringT,
                containerWidth: containerWidth,
                rowWidth: scaledRowWidth,
                devicePixelRatio: devicePixelRatio,
              );
              final rowHeight = math.max(1.0, row.height * heightScale);

              return Positioned(
                key: rowKeyPrefix != null
                    ? ValueKey<String>('${rowKeyPrefix}_row_$r')
                    : null,
                left: rowOffsetX,
                top: rowTop,
                width: containerWidth,
                height: rowHeight,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    row.text,
                    key: r == 0
                        ? (firstRowTextKey ??
                            (rowKeyPrefix != null
                                ? ValueKey<String>('${rowKeyPrefix}_row_text_0')
                                : null))
                        : (rowKeyPrefix != null
                            ? ValueKey<String>('${rowKeyPrefix}_row_text_$r')
                            : null),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: textColor,
                      fontSize: effectiveFontSize,
                      fontWeight: FontWeight.w400,
                      height: metrics.lineHeight,
                      letterSpacing: metrics.letterSpacing,
                    ),
                    strutStyle: StrutStyle(
                      fontFamily: 'Poppins',
                      fontSize: effectiveFontSize,
                      fontWeight: FontWeight.w400,
                      height: metrics.lineHeight,
                      forceStrutHeight: true,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLyricsStagePanel({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
    required MusEveePalette palette,
    required double homeColumnWidth,
  }) {
    return LayoutBuilder(
      key: const ValueKey<String>('now_playing_lyrics_panel'),
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final screenWidth = constraints.maxWidth;
        final zoneHeight = constraints.maxHeight;
        _lastLyricsPanelZoneHeight = zoneHeight;
        const stageSidePad = 32.0;
        final stageLeftSnapped =
            NowPlayingView.snapToPhysicalPixel(stageSidePad, dpr);
        final textColumnWidth = NowPlayingView.snapToPhysicalPixel(
          math.max(140.0, screenWidth - stageSidePad * 2.0),
          dpr,
        );
        final homeWidthSnapped =
            NowPlayingView.snapToPhysicalPixel(homeColumnWidth, dpr);

        if (song == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _buildEmptyLibraryColumn(
                context: context,
                localProvider: localProvider,
                palette: palette,
              ),
            ),
          );
        }

        if (song.hasLyrics && !song.isLyricsLoadedInMemory) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: palette.nowPlayingSecondary,
              ),
            ),
          );
        }

        final lyricsFontPt = localProvider.lyricsFontSize;
        final stagePrefOffset =
            NowPlayingView.computeStageActiveFontPrefOffset(lyricsFontPt);
        final homePrefOffset =
            NowPlayingView.computeHomeActiveFontPrefOffset(lyricsFontPt);
        final homeMinFontSize =
            NowPlayingView.computeHomeActiveMinFontSize(lyricsFontPt);
        final homeSecondaryFontSize = localProvider.secondaryLyricsFontSize;
        final edgeFadeHeight =
            zoneHeight * MusEveePalette.lyricsPanelEdgeFadeHeightFactor;

        // 1. Synced USLT Lyrics Mode — Full lyrics centered, rendered by the shared row-level layout engine
        if (localProvider.lyricsDisplayMode ==
                EmbeddedLyricsDisplayMode.synced &&
            song.hasSyncedLyrics) {
          final entries = localProvider.syncedLyricsFor(song);
          if (entries.isNotEmpty) {
            _ensurePanel0LyricsMetricsCached(
              song: song,
              entries: entries,
              columnWidth: textColumnWidth,
              homeColumnWidth: homeWidthSnapped,
              preferredOffset: stagePrefOffset,
              homePreferredOffset: homePrefOffset,
              homeMinFontSize: homeMinFontSize,
              homeSecondaryFontSize: homeSecondaryFontSize,
              devicePixelRatio: dpr,
            );

            return AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                localProvider.activeLyricIndexNotifier,
                localProvider.progressNotifier,
                _rowGlideTickVersion,
                _lyricSlideProgress,
                _lyricsStageReturnController,
                _panel0TravelController,
              ]),
              builder: (context, _) {
                final exploreBlend = lyricsPanelExploreBlend;
                final rawActiveIdx =
                    NowPlayingView.resolveActiveSyncedLyricIndex(
                  entries,
                  localProvider.positionMs,
                );
                final int effectiveIdx;
                if (localProvider.autoScrollLyrics) {
                  effectiveIdx = rawActiveIdx >= 0
                      ? rawActiveIdx.clamp(0, entries.length - 1)
                      : -1;
                  _frozenLyricIndex = effectiveIdx;
                } else {
                  effectiveIdx = _frozenLyricIndex >= 0
                      ? _frozenLyricIndex.clamp(0, entries.length - 1)
                      : -1;
                }

                _syncSharedLineChangeAnimation(
                  song: song,
                  entries: entries,
                  effectiveIdx: effectiveIdx,
                  autoScrollLyrics: localProvider.autoScrollLyrics,
                  currentT: 1.0,
                  containerWidth: textColumnWidth,
                  homeWidth: homeWidthSnapped,
                  zoneHeight: zoneHeight,
                  preferredOffset: stagePrefOffset,
                  homePreferredOffset: homePrefOffset,
                  homeMinFontSize: homeMinFontSize,
                  homeSecondaryFontSize: homeSecondaryFontSize,
                  stageScrollDelta: 0.0,
                  dpr: dpr,
                  emptySlotHeight: 22.0,
                  isInFluidMorph: false,
                  allowSettledPanel0Slide: _pendingPanel0TapSeek ||
                      (!_isLyricsPanelPointerDown &&
                          (localProvider.autoScrollLyrics ||
                              effectiveIdx == -1)),
                  isPanel0TapSeek: _pendingPanel0TapSeek,
                );

                final centerIdx = effectiveIdx >= 0 ? effectiveIdx : 0;
                final isCenterActive = effectiveIdx >= 0;
                final prevIdx = centerIdx - 1;
                final nextIdx = centerIdx + 1;
                final hasPrev = prevIdx >= 0;
                final hasNext = nextIdx < entries.length;

                final prevPanel0EffectiveIdx = _lastPanel0ResolvedEffectiveIdx;
                final isPanel0LineChange =
                    _lastPanel0ResolvedSongPath == song.filePath &&
                        prevPanel0EffectiveIdx != -999 &&
                        prevPanel0EffectiveIdx != effectiveIdx;
                _lastPanel0ResolvedSongPath = song.filePath;
                _lastPanel0ResolvedEffectiveIdx = effectiveIdx;

                final prevText = hasPrev
                    ? (entries[prevIdx].text.trim().isEmpty
                        ? '♪'
                        : entries[prevIdx].text.trim())
                    : '';
                final centerText = entries[centerIdx].text.trim().isEmpty
                    ? '♪'
                    : entries[centerIdx].text.trim();
                final nextText = hasNext
                    ? (entries[nextIdx].text.trim().isEmpty
                        ? '♪'
                        : entries[nextIdx].text.trim())
                    : '';

                final activeRoleFontSize =
                    _cachedPanel0ActiveMetrics[centerIdx]?.fontSize ??
                        NowPlayingView.computeActiveLyricFontSize(
                          centerText,
                          maxWidth: homeWidthSnapped,
                          preferredOffset: stagePrefOffset,
                        );

                final _ResolvedLineRowLayout? prevLayout = hasPrev
                    ? _resolveLineMorphMetricsAndGlide(
                        songPath: song.filePath,
                        centerIdx: centerIdx,
                        lineIndex: prevIdx,
                        rawText: prevText,
                        containerWidth: textColumnWidth,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        isActiveRole: false,
                        hysteresisMarginPx:
                            NowPlayingView.wrapHysteresisMarginPx,
                        devicePixelRatio: dpr,
                        lockedMetricsOverride:
                            _cachedPanel0SecondaryMetrics[prevIdx],
                      )
                    : null;
                final centerActiveRoleLayout = _resolveLineMorphMetricsAndGlide(
                  songPath: song.filePath,
                  centerIdx: centerIdx,
                  lineIndex: centerIdx,
                  rawText: centerText,
                  containerWidth: textColumnWidth,
                  fontSize: activeRoleFontSize,
                  isActiveRole: true,
                  hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                  devicePixelRatio: dpr,
                  recordAsRenderedState: isCenterActive,
                  lockedMetricsOverride: _cachedPanel0ActiveMetrics[centerIdx],
                );
                final centerRenderLayout = isCenterActive
                    ? centerActiveRoleLayout
                    : _resolveLineMorphMetricsAndGlide(
                        songPath: song.filePath,
                        centerIdx: centerIdx,
                        lineIndex: centerIdx,
                        rawText: centerText,
                        containerWidth: textColumnWidth,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        isActiveRole: false,
                        hysteresisMarginPx:
                            NowPlayingView.wrapHysteresisMarginPx,
                        devicePixelRatio: dpr,
                        recordAsRenderedState: true,
                        lockedMetricsOverride:
                            _cachedPanel0SecondaryMetrics[centerIdx],
                      );
                final _ResolvedLineRowLayout? nextLayout = hasNext
                    ? _resolveLineMorphMetricsAndGlide(
                        songPath: song.filePath,
                        centerIdx: centerIdx,
                        lineIndex: nextIdx,
                        rawText: nextText,
                        containerWidth: textColumnWidth,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        isActiveRole: false,
                        hysteresisMarginPx:
                            NowPlayingView.wrapHysteresisMarginPx,
                        devicePixelRatio: dpr,
                        lockedMetricsOverride:
                            _cachedPanel0SecondaryMetrics[nextIdx],
                      )
                    : null;

                final count = entries.length;
                const gap = NowPlayingView.lyricSlotVerticalGap;
                final isPanel0SlideAnimating = _slideInterpolateRoleSize &&
                    _slideAnimatedLyricIndex == effectiveIdx &&
                    _lyricSlideController.value < 1.0;
                final isMorphHandoverOnly =
                    isPanel0SlideAnimating && !_slideStartedInSettledPanel0;
                final isPanel0TravelingNow =
                    _isPanel0Traveling && _panel0TravelController.isAnimating;
                final snapPositions = !isRowGlideAnimating &&
                    !isPanel0SlideAnimating &&
                    !isPanel0TravelingNow;
                final List<double> slotH = List<double>.filled(count, 22.0);
                final List<CachedLyricLineMetrics> lineMetrics =
                    List<CachedLyricLineMetrics>.generate(count, (i) {
                  if (i == centerIdx) {
                    final rawCenterH = isCenterActive
                        ? centerActiveRoleLayout.animatedSlotHeight
                        : centerRenderLayout.animatedSlotHeight;
                    slotH[i] = NowPlayingView.snapToPhysicalPixel(
                      rawCenterH,
                      dpr,
                    );
                    return centerRenderLayout.metrics;
                  }
                  if (i == prevIdx && prevLayout != null) {
                    slotH[i] = NowPlayingView.snapToPhysicalPixel(
                      prevLayout.animatedSlotHeight,
                      dpr,
                    );
                    return prevLayout.metrics;
                  }
                  if (i == nextIdx && nextLayout != null) {
                    slotH[i] = NowPlayingView.snapToPhysicalPixel(
                      nextLayout.animatedSlotHeight,
                      dpr,
                    );
                    return nextLayout.metrics;
                  }
                  final cached = _cachedPanel0SecondaryMetrics[i] ??
                      NowPlayingView.measureLyricLineAtWidth(
                        entries[i].text,
                        containerWidth: textColumnWidth,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        isActiveRole: false,
                        devicePixelRatio: dpr,
                      );
                  slotH[i] = NowPlayingView.snapToPhysicalPixel(
                    cached.slotHeight,
                    dpr,
                  );
                  final canonicalTops = _canonicalRowTopsForMetrics(cached);
                  _lastRenderedLineMorphStates[i] = _LineMorphRowState(
                    rawText: cached.text,
                    committedWrapCount: cached.wrappedLineCount,
                    isActiveRole: false,
                    fontSize: cached.fontSize,
                    fromSlotHeight: cached.slotHeight,
                    toSlotHeight: cached.slotHeight,
                    fromRowTops: canonicalTops,
                    toRowTops: canonicalTops,
                    glideDurationMs: NowPlayingView.lyricRowGlideDurationMs,
                    glideProgress: 1.0,
                    isGliding: false,
                  );
                  return cached;
                }, growable: false);

                final List<double> restScreenTop =
                    List<double>.filled(count, 0.0);
                final centerSlotH = slotH[centerIdx];
                final stageCenterTop = NowPlayingView.snapToPhysicalPixel(
                  (zoneHeight - centerSlotH) / 2.0,
                  dpr,
                );
                restScreenTop[centerIdx] = stageCenterTop;

                if (hasPrev) {
                  final prevTop = NowPlayingView.snapToPhysicalPixel(
                    stageCenterTop - gap - slotH[prevIdx],
                    dpr,
                  );
                  restScreenTop[prevIdx] = prevTop;
                  double runningAbove = prevTop;
                  for (int i = centerIdx - 2; i >= 0; i--) {
                    runningAbove -= (gap + slotH[i]);
                    restScreenTop[i] = NowPlayingView.snapToPhysicalPixel(
                      runningAbove,
                      dpr,
                    );
                  }
                }

                if (hasNext) {
                  final nextTop = NowPlayingView.snapToPhysicalPixel(
                    stageCenterTop + centerSlotH + gap,
                    dpr,
                  );
                  restScreenTop[nextIdx] = nextTop;
                  double runningBelow = nextTop + slotH[nextIdx] + gap;
                  for (int i = centerIdx + 2; i < count; i++) {
                    restScreenTop[i] = NowPlayingView.snapToPhysicalPixel(
                      runningBelow,
                      dpr,
                    );
                    runningBelow += slotH[i] + gap;
                  }
                }

                final topSpacer = NowPlayingView.snapToPhysicalPixel(
                  math.max(0.0, (zoneHeight - slotH[0]) / 2.0),
                  dpr,
                );
                final bottomSpacer = NowPlayingView.snapToPhysicalPixel(
                  math.max(0.0, (zoneHeight - slotH[count - 1]) / 2.0),
                  dpr,
                );
                final rawTargetScrollOffset =
                    math.max(0.0, topSpacer - restScreenTop[0]);
                final targetScrollOffset = NowPlayingView.snapToPhysicalPixel(
                  rawTargetScrollOffset,
                  dpr,
                );

                final handoverSnaps = _resolveInterpolatedLineSnapshots(
                  entries: entries,
                  centerIdx: effectiveIdx,
                  t: 1.0,
                  u: isPanel0SlideAnimating ? _lyricSlideProgress.value : 1.0,
                  containerWidth: textColumnWidth,
                  homeWidth: homeWidthSnapped,
                  zoneHeight: zoneHeight,
                  preferredOffset: stagePrefOffset,
                  homePreferredOffset: homePrefOffset,
                  homeMinFontSize: homeMinFontSize,
                  homeSecondaryFontSize: homeSecondaryFontSize,
                  stageScrollDelta: 0.0,
                  dpr: dpr,
                  emptySlotHeight: 22.0,
                  resolvedPrevSlotH: prevLayout?.animatedSlotHeight,
                  resolvedCenterSlotH:
                      centerActiveRoleLayout.animatedSlotHeight,
                  resolvedNextSlotH: nextLayout?.animatedSlotHeight,
                  includeAllStageLines: true,
                );

                if (isPanel0SlideAnimating) {
                  for (final entry in handoverSnaps.entries) {
                    final idx = entry.key;
                    if (idx >= 0 && idx < count) {
                      restScreenTop[idx] = entry.value.top;
                      slotH[idx] = entry.value.slotHeight;
                    }
                  }
                }

                final isDifferentSong =
                    _lastLyricsPanelScrolledSongPath != song.filePath;
                if (isDifferentSong) {
                  _lastLyricsPanelScrolledSongPath = song.filePath;
                  _lastLyricsPanelScrolledLineIndex = centerIdx;
                  _frozenStageScrollOffsetAtDragStart = null;
                  _panel0SlideAnchorOffset = null;
                  _panel0SlideTargetAnchorOffset = null;
                  _panel0SlideWasTapSeek = false;
                  _lastPanel0RenderedAnchorOffset = null;
                  _isPanel0Traveling = false;
                  _panel0TravelExtraDyByLine.clear();
                  _lastPanel0RenderedDocTops.clear();
                  if (_panel0TravelController.isAnimating) {
                    _panel0TravelController.stop();
                  }
                  _pendingPanel0TapSeek = false;
                  _lyricsPanelResumeTimer?.cancel();
                  _isLyricsPanelUserScrollPaused = false;
                  _isLyricsPanelExploreMode = false;
                  if (_lyricsStageReturnController.isAnimating ||
                      _lyricsStageReturnController.value != 0.0) {
                    _lyricsStageReturnController.stop();
                    _lyricsStageReturnController.value = 0.0;
                  }
                  _returnGlideStartScrollOffset = null;
                  _returnGlideTargetScrollOffset = null;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollLyricsPanelToIndex(
                      centerIdx,
                      animate: false,
                      centerIdx: centerIdx,
                      isCenterActive: isCenterActive,
                    );
                  });
                } else if (isPanel0SlideAnimating) {
                  final wasTapSeek = _pendingPanel0TapSeek;
                  _pendingPanel0TapSeek = false;
                  _lastLyricsPanelScrolledLineIndex = centerIdx;
                  _frozenStageScrollOffsetAtDragStart = null;
                  _isPanel0Traveling = false;
                  _panel0TravelExtraDyByLine.clear();
                  if (_panel0TravelController.isAnimating) {
                    _panel0TravelController.stop();
                  }
                  if (wasTapSeek) {
                    _panel0SlideAnchorOffset =
                        _lyricsPanelScrollController.hasClients
                            ? _lyricsPanelScrollController.offset
                            : (_lastPanel0RenderedAnchorOffset ??
                                targetScrollOffset);
                    _panel0SlideWasTapSeek = true;
                  } else if (isMorphHandoverOnly &&
                      _panel0SlideAnchorOffset == null) {
                    _panel0SlideAnchorOffset = targetScrollOffset;
                    if (_lyricsPanelScrollController.hasClients &&
                        (_lyricsPanelScrollController.offset -
                                    targetScrollOffset)
                                .abs() >
                            0.5) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollLyricsPanelToIndex(
                          centerIdx,
                          animate: false,
                          centerIdx: centerIdx,
                          isCenterActive: isCenterActive,
                        );
                      });
                    }
                  } else {
                    _panel0SlideAnchorOffset ??=
                        _lastPanel0RenderedAnchorOffset ??
                            (_lyricsPanelScrollController.hasClients
                                ? _lyricsPanelScrollController.offset
                                : targetScrollOffset);
                  }
                  _panel0SlideTargetAnchorOffset = targetScrollOffset;
                } else {
                  if (_panel0SlideAnchorOffset != null) {
                    final startAnchor = _panel0SlideAnchorOffset!;
                    final targetAnchor =
                        _panel0SlideTargetAnchorOffset ?? targetScrollOffset;
                    final wasSlideTapSeek = _panel0SlideWasTapSeek;
                    _panel0SlideAnchorOffset = null;
                    _panel0SlideTargetAnchorOffset = null;
                    _panel0SlideWasTapSeek = false;
                    if (_lyricsPanelScrollController.hasClients) {
                      final pos = _lyricsPanelScrollController.position;
                      final rawDesired = (!wasSlideTapSeek &&
                              _isLyricsPanelExploreMode &&
                              _isLyricsPanelUserScrollPaused)
                          ? (pos.pixels + (targetAnchor - startAnchor))
                          : targetScrollOffset;
                      if ((pos.pixels - rawDesired).abs() > 0.5) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted ||
                              !_lyricsPanelScrollController.hasClients) {
                            return;
                          }
                          final p = _lyricsPanelScrollController.position;
                          final clamped = rawDesired
                              .clamp(
                                p.minScrollExtent,
                                math.max(p.minScrollExtent, p.maxScrollExtent),
                              )
                              .toDouble();
                          if ((p.pixels - clamped).abs() > 0.05) {
                            _lyricsPanelScrollController.jumpTo(clamped);
                          }
                        });
                      }
                    }
                  }
                  if (isPanel0LineChange ||
                      centerIdx != _lastLyricsPanelScrolledLineIndex ||
                      _pendingPanel0TapSeek) {
                    final prevScrolledCenterIdx =
                        _lastLyricsPanelScrolledLineIndex;
                    _lastLyricsPanelScrolledLineIndex = centerIdx;
                    final wasTapSeek = _pendingPanel0TapSeek;
                    _pendingPanel0TapSeek = false;
                    if (wasTapSeek ||
                        (!_isLyricsPanelPointerDown &&
                            (localProvider.autoScrollLyrics ||
                                effectiveIdx == -1))) {
                      _frozenStageScrollOffsetAtDragStart = null;
                      final settledTarget = _computePanel0TargetScrollOffset(
                        centerIdx,
                        zoneHeight,
                        centerIdx: centerIdx,
                        isCenterActive: isCenterActive,
                        devicePixelRatio: dpr,
                      );
                      final oldCenterIdx = (prevPanel0EffectiveIdx != -999 &&
                              prevPanel0EffectiveIdx >= 0)
                          ? prevPanel0EffectiveIdx.clamp(0, count - 1)
                          : (prevScrolledCenterIdx >= 0
                              ? prevScrolledCenterIdx.clamp(0, count - 1)
                              : 0);
                      final oldIsCenterActive = prevPanel0EffectiveIdx == -999
                          ? isCenterActive
                          : (prevPanel0EffectiveIdx >= 0);
                      final oldLayout = _computePanel0LayoutSnapshot(
                        centerIdx: oldCenterIdx,
                        isCenterActive: oldIsCenterActive,
                        zoneHeight: zoneHeight,
                        devicePixelRatio: dpr,
                      );
                      final List<double> startDocTop = List<double>.generate(
                        count,
                        (i) =>
                            _lastPanel0RenderedDocTops[i] ??
                            (oldLayout.targetScrollOffset +
                                (i < oldLayout.restScreenTop.length
                                    ? oldLayout.restScreenTop[i]
                                    : 0.0)),
                        growable: false,
                      );
                      _panel0TravelExtraDyByLine.clear();
                      bool anyExtraDy = false;
                      for (int i = 0; i < count; i++) {
                        final targetDocTopI =
                            targetScrollOffset + restScreenTop[i];
                        final deltaI = startDocTop[i] - targetDocTopI;
                        _panel0TravelExtraDyByLine[i] = deltaI;
                        if (deltaI.abs() > 0.05) {
                          anyExtraDy = true;
                        }
                      }

                      final currentPixels =
                          _lyricsPanelScrollController.hasClients
                              ? _lyricsPanelScrollController.offset
                              : oldLayout.targetScrollOffset;
                      final baseExploreRefOffset = (_isPanel0Traveling &&
                              _panel0TravelController.isAnimating)
                          ? _panel0TravelToScrollOffset
                          : currentPixels;
                      final rawDesiredTarget = (!wasTapSeek &&
                              _isLyricsPanelExploreMode &&
                              _isLyricsPanelUserScrollPaused)
                          ? (baseExploreRefOffset +
                              (settledTarget - oldLayout.targetScrollOffset))
                          : settledTarget;
                      final settledLastOff = _computePanel0TargetScrollOffset(
                        count - 1,
                        zoneHeight,
                        centerIdx: centerIdx,
                        isCenterActive: isCenterActive,
                        devicePixelRatio: dpr,
                      );
                      final maxPreScroll = math.max(
                        0.0,
                        math.max(
                              targetScrollOffset +
                                  restScreenTop[count - 1] +
                                  slotH[count - 1] +
                                  bottomSpacer,
                              settledLastOff + zoneHeight,
                            ) -
                            zoneHeight,
                      );
                      final clampedTarget =
                          rawDesiredTarget.clamp(0.0, maxPreScroll).toDouble();
                      if ((clampedTarget - currentPixels).abs() > 0.05 ||
                          anyExtraDy) {
                        _isPanel0Traveling = true;
                        _panel0TravelFromScrollOffset = currentPixels;
                        _panel0TravelToScrollOffset = clampedTarget;
                        _panel0TravelController.forward(from: 0.0);
                      } else {
                        _isPanel0Traveling = false;
                        _panel0TravelExtraDyByLine.clear();
                        if (_panel0TravelController.isAnimating) {
                          _panel0TravelController.stop();
                        }
                      }
                    }
                  }
                }

                // Pure document-coordinate anchoring: while `isPanel0SlideAnimating` is true,
                // keep `effectiveAnchorOffset` locked to the viewport scroll anchor (`_panel0SlideAnchorOffset`)
                // so every line's document top comes purely from `handoverSnaps[i].top` on the same clock
                // as typography, then re-anchor to `targetScrollOffset` at `u = 1.0`.
                final effectiveAnchorOffset = isPanel0SlideAnimating
                    ? (_panel0SlideAnchorOffset ?? targetScrollOffset)
                    : targetScrollOffset;
                _lastPanel0RenderedAnchorOffset = effectiveAnchorOffset;

                _lyricsPanelScrollController.initialOffsetResolver = () =>
                    _frozenStageScrollOffsetAtDragStart ??
                    effectiveAnchorOffset;

                final double travelRemainingFactor =
                    (_isPanel0Traveling && _panel0TravelController.isAnimating)
                        ? (1.0 -
                            Curves.easeOutCubic
                                .transform(_panel0TravelController.value))
                        : 0.0;
                final double lastLineExtraDy = isPanel0SlideAnimating
                    ? 0.0
                    : (travelRemainingFactor *
                        (_panel0TravelExtraDyByLine[count - 1] ?? 0.0));
                final double lastLineSlotH = (isPanel0SlideAnimating &&
                        handoverSnaps.containsKey(count - 1))
                    ? handoverSnaps[count - 1]!.slotHeight
                    : slotH[count - 1];
                final liveContentHeight = effectiveAnchorOffset +
                    restScreenTop[count - 1] +
                    math.max(0.0, lastLineExtraDy) +
                    lastLineSlotH +
                    bottomSpacer;
                final settledLastLineTargetOffset =
                    _computePanel0TargetScrollOffset(
                  count - 1,
                  zoneHeight,
                  centerIdx: centerIdx,
                  isCenterActive: isCenterActive,
                  devicePixelRatio: dpr,
                );
                final settledContentHeight =
                    settledLastLineTargetOffset + zoneHeight;
                final travelRequiredHeight =
                    (_isPanel0Traveling && _panel0TravelController.isAnimating)
                        ? math.max(
                            _panel0TravelFromScrollOffset + zoneHeight,
                            _panel0TravelToScrollOffset + zoneHeight,
                          )
                        : 0.0;
                final slideRequiredHeight = isPanel0SlideAnimating
                    ? math.max(
                        effectiveAnchorOffset + zoneHeight,
                        targetScrollOffset + zoneHeight,
                      )
                    : 0.0;
                final totalScrollContentHeight = math.max(
                  zoneHeight,
                  math.max(
                    math.max(liveContentHeight, settledContentHeight),
                    math.max(travelRequiredHeight, slideRequiredHeight),
                  ),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) {
                        _isLyricsPanelPointerDown = true;
                        if (_isLyricsPanelExploreMode ||
                            _isLyricsPanelUserScrollPaused ||
                            _lyricsStageReturnController.isAnimating) {
                          _onLyricsPanelUserManualScroll();
                        }
                      },
                      onPointerMove: (_) {
                        if (_isLyricsPanelExploreMode ||
                            _isLyricsPanelUserScrollPaused ||
                            _lyricsStageReturnController.isAnimating) {
                          _onLyricsPanelUserManualScroll();
                        }
                      },
                      onPointerUp: (_) {
                        _isLyricsPanelPointerDown = false;
                        if (_isLyricsPanelExploreMode &&
                            _isLyricsPanelUserScrollPaused) {
                          _restartLyricsPanelIdleTimer();
                        }
                      },
                      onPointerCancel: (_) {
                        _isLyricsPanelPointerDown = false;
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if ((notification is ScrollStartNotification &&
                                  notification.dragDetails != null) ||
                              (notification is ScrollUpdateNotification &&
                                  notification.dragDetails != null) ||
                              (notification is UserScrollNotification &&
                                  notification.direction !=
                                      ScrollDirection.idle)) {
                            _onLyricsPanelUserManualScroll();
                          }
                          return false;
                        },
                        child: SingleChildScrollView(
                          key: const ValueKey<String>(
                            'lyrics_panel_scroll_view',
                          ),
                          controller: _lyricsPanelScrollController,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          child: SizedBox(
                            width: screenWidth,
                            height: totalScrollContentHeight,
                            child: Stack(
                              clipBehavior: Clip.none,
                              fit: StackFit.expand,
                              children: <Widget>[
                                for (int i = 0; i < count; i++)
                                  Builder(
                                    builder: (context) {
                                      final _LyricLineAnimSnapshot? snap =
                                          isPanel0SlideAnimating
                                              ? handoverSnaps[i]
                                              : null;
                                      final double itemSlotH = snap != null
                                          ? snap.slotHeight
                                          : slotH[i];
                                      final double? itemFontOverride =
                                          snap?.fontSize;
                                      final double? itemSlotHOverride =
                                          snap?.slotHeight;
                                      final Color? itemColorOverride =
                                          snap != null
                                              ? Color.lerp(
                                                  palette.nowPlayingSecondary,
                                                  palette.nowPlayingPrimary,
                                                  snap.colorBlend,
                                                )
                                              : null;
                                      CachedLyricLineMetrics itemMetrics =
                                          lineMetrics[i];
                                      if (snap != null) {
                                        final secM =
                                            _cachedPanel0SecondaryMetrics[i] ??
                                                lineMetrics[i];
                                        final actM =
                                            _cachedPanel0ActiveMetrics[i] ??
                                                lineMetrics[i];
                                        itemMetrics =
                                            NowPlayingView.lerpPanel0RowMetrics(
                                          secondaryMetrics: secM,
                                          activeMetrics: actM,
                                          fontSize: snap.fontSize,
                                          slotHeight: itemSlotH,
                                          colorBlend: snap.colorBlend,
                                          containerWidth: textColumnWidth,
                                        );
                                        final canonicalTops =
                                            _canonicalRowTopsForMetrics(
                                                itemMetrics);
                                        _lastRenderedLineMorphStates[i] =
                                            _LineMorphRowState(
                                          rawText: itemMetrics.text,
                                          committedWrapCount:
                                              itemMetrics.wrappedLineCount,
                                          isActiveRole: snap.colorBlend >= 0.5,
                                          fontSize: snap.fontSize,
                                          fromSlotHeight: itemSlotH,
                                          toSlotHeight: itemSlotH,
                                          fromRowTops: canonicalTops,
                                          toRowTops: canonicalTops,
                                          glideDurationMs: NowPlayingView
                                              .lyricRowGlideDurationMs,
                                          glideProgress: 1.0,
                                          isGliding: false,
                                        );
                                      }
                                      double? itemOpacityOverride;
                                      if (snap != null) {
                                        final int distance = isCenterActive
                                            ? (i - effectiveIdx).abs()
                                            : (i + 1);
                                        final int stageDistance =
                                            (i - centerIdx).abs();
                                        final double ladderOp = NowPlayingView
                                            .lyricPanelOpacityForDistance(
                                                distance);
                                        final double restOp =
                                            (!isMorphHandoverOnly &&
                                                    stageDistance > 1)
                                                ? 0.0
                                                : snap.opacity;
                                        final double clampedExplore =
                                            exploreBlend.clamp(0.0, 1.0);
                                        itemOpacityOverride = restOp +
                                            (ladderOp - restOp) *
                                                clampedExplore;
                                      }
                                      final List<double>? itemRowTops = snap !=
                                              null
                                          ? null
                                          : (i == centerIdx
                                              ? centerRenderLayout
                                                  .animatedRowTops
                                              : (i == prevIdx &&
                                                      prevLayout != null
                                                  ? prevLayout.animatedRowTops
                                                  : (i == nextIdx &&
                                                          nextLayout != null
                                                      ? nextLayout
                                                          .animatedRowTops
                                                      : null)));
                                      final double liveLineExtraDy =
                                          isPanel0SlideAnimating
                                              ? 0.0
                                              : (travelRemainingFactor *
                                                  (_panel0TravelExtraDyByLine[
                                                          i] ??
                                                      0.0));
                                      final double liveDocTop =
                                          effectiveAnchorOffset +
                                              (isPanel0SlideAnimating
                                                  ? (snap?.top ??
                                                      restScreenTop[i])
                                                  : (restScreenTop[i] +
                                                      liveLineExtraDy));
                                      _lastPanel0RenderedDocTops[i] =
                                          liveDocTop;

                                      return Positioned(
                                        left: stageLeftSnapped,
                                        top: liveDocTop,
                                        width: textColumnWidth,
                                        height: itemSlotH,
                                        child: _buildPanel0SyncedLyricItem(
                                          index: i,
                                          effectiveIndex: effectiveIdx,
                                          centerIdx: centerIdx,
                                          exploreBlend: exploreBlend,
                                          entry: entries[i],
                                          localProvider: localProvider,
                                          palette: palette,
                                          columnWidth: textColumnWidth,
                                          itemHeight: itemSlotH,
                                          renderMetrics: itemMetrics,
                                          animatedRowTops: itemRowTops,
                                          snapRowPositions: snapPositions,
                                          devicePixelRatio: dpr,
                                          fontSizeOverride: itemFontOverride,
                                          slotHeightOverride: itemSlotHOverride,
                                          colorOverride: itemColorOverride,
                                          opacityOverride: itemOpacityOverride,
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Top & bottom edge fade (melts distant lines into page background)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: edgeFadeHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                palette.nowPlayingBg,
                                palette.nowPlayingBg.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: edgeFadeHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                palette.nowPlayingBg.withValues(alpha: 0.0),
                                palette.nowPlayingBg,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          }
        }

        // 2. Plain (untimed) USLT Lyrics Mode — full text as static scrollable centered list (manual-only scroll, no idle return timer)
        if (song.hasLyrics) {
          final nonEmpty = localProvider
              .plainLyricLinesFor(song)
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          if (nonEmpty.isNotEmpty) {
            if (_lastLyricsPanelScrolledSongPath != song.filePath) {
              _lastLyricsPanelScrolledSongPath = song.filePath;
              _lastLyricsPanelScrolledLineIndex = -1;
              _lyricsPanelResumeTimer?.cancel();
              _isLyricsPanelUserScrollPaused = false;
              _isLyricsPanelExploreMode = false;
              _isPanel0Traveling = false;
              _panel0TravelExtraDyByLine.clear();
              _lastPanel0RenderedDocTops.clear();
              if (_panel0TravelController.isAnimating) {
                _panel0TravelController.stop();
              }
              _lyricsPanelScrollController.initialOffsetResolver = () => 0.0;
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                ListView.separated(
                  key: const ValueKey<String>('lyrics_panel_plain_list'),
                  controller: _lyricsPanelScrollController,
                  padding: EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: math.max(24.0, edgeFadeHeight),
                  ),
                  itemCount: nonEmpty.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    return Text(
                      nonEmpty[index],
                      key: ValueKey<String>('lyrics_panel_plain_line_$index'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.nowPlayingSecondary,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        fontWeight: FontWeight.w400,
                        height: MusEveePalette.lyricLineHeight,
                      ),
                      strutStyle: const StrutStyle(
                        fontFamily: 'Poppins',
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        fontWeight: FontWeight.w400,
                        height: MusEveePalette.lyricLineHeight,
                        forceStrutHeight: true,
                      ),
                    );
                  },
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: edgeFadeHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            palette.nowPlayingBg,
                            palette.nowPlayingBg.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: edgeFadeHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            palette.nowPlayingBg.withValues(alpha: 0.0),
                            palette.nowPlayingBg,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        }

        // 3. No USLT Lyrics Yet — same pale prompt & LRCLIB / manual entry action sheet as Home
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: GestureDetector(
              key: const ValueKey<String>('lyrics_panel_no_lyrics_prompt'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _showNoLyricsActionSheet(
                context: context,
                localProvider: localProvider,
                downloaderProvider: downloaderProvider,
                song: song,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.tr(
                        'Belum ada lirik tertanam pada file ${song.audioFormatLabel} ini.',
                        'No embedded lyrics in this ${song.audioFormatLabel} file yet.',
                        context,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.nowPlayingSecondary,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.tr(
                        'Ketuk untuk Cari Lirik LRCLIB atau Isi Manual',
                        'Tap to Search LRCLIB Lyrics or Enter Manually',
                        context,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: palette.nowPlayingPrimary.withValues(
                          alpha: 0.72,
                        ),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPanel0SyncedLyricItem({
    required int index,
    required int effectiveIndex,
    required int centerIdx,
    required double exploreBlend,
    required SyncedLyricEntry entry,
    required LocalMusicProvider localProvider,
    required MusEveePalette palette,
    required double columnWidth,
    required double itemHeight,
    required CachedLyricLineMetrics renderMetrics,
    required List<double>? animatedRowTops,
    required bool snapRowPositions,
    required double devicePixelRatio,
    double? fontSizeOverride,
    double? slotHeightOverride,
    Color? colorOverride,
    double? opacityOverride,
  }) {
    final distance = (index - effectiveIndex).abs();
    final stageDistance = (index - centerIdx).abs();
    final isActive = index == effectiveIndex;
    final ladderOpacity = NowPlayingView.lyricPanelOpacityForDistance(distance);
    final restOpacity = stageDistance <= 1 ? ladderOpacity : 0.0;
    final clampedExploreBlend = exploreBlend.clamp(0.0, 1.0);
    final modeOpacity =
        restOpacity + (ladderOpacity - restOpacity) * clampedExploreBlend;
    final lineOpacity = opacityOverride ?? modeOpacity;
    final isInExploreOrReturning =
        _isLyricsPanelExploreMode || _lyricsStageReturnController.isAnimating;
    final isTappable = isInExploreOrReturning || stageDistance <= 1;

    return IgnorePointer(
      key: ValueKey<String>('lyrics_panel_line_pointer_$index'),
      ignoring: !isTappable,
      child: GestureDetector(
        key: ValueKey<String>('lyrics_panel_line_$index'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _pendingPanel0TapSeek = true;
            if (isInExploreOrReturning) {
              if (_lyricsStageReturnController.isAnimating) {
                _lyricsStageReturnController.stop();
                _lyricsStageReturnController.value = 0.0;
                _returnGlideStartScrollOffset = null;
                _returnGlideTargetScrollOffset = null;
              }
              _isLyricsPanelUserScrollPaused = true;
              _isLyricsPanelExploreMode = true;
              _restartLyricsPanelIdleTimer();
            } else {
              _lyricsPanelResumeTimer?.cancel();
              _isLyricsPanelUserScrollPaused = false;
            }
          });
          _seekFromUserGesture(localProvider, entry.timeMs);
        },
        child: SizedBox(
          width: columnWidth,
          height: itemHeight,
          child: AnimatedOpacity(
            key: ValueKey<String>('lyrics_panel_line_opacity_$index'),
            duration: (opacityOverride != null ||
                    stageDistance > 1 ||
                    _lyricsStageReturnController.isAnimating)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            opacity: lineOpacity,
            child: _buildLyricRowBlock(
              metrics: renderMetrics,
              containerWidth: columnWidth,
              centeringT: 1.0,
              textColor: colorOverride ??
                  (isActive
                      ? palette.nowPlayingPrimary
                      : palette.nowPlayingSecondary),
              devicePixelRatio: devicePixelRatio,
              animatedRowTops: animatedRowTops,
              snapRowPositions: snapRowPositions,
              rowKeyPrefix: 'lyrics_panel_line_$index',
              firstRowTextKey:
                  ValueKey<String>('lyrics_panel_line_text_$index'),
              fontSizeOverride: fontSizeOverride,
              slotHeightOverride: slotHeightOverride,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 2A-MORPH. FLUID LYRICS MORPH SCENE FOR `p ∈ [0.0, 1.0]` (`t = 1.0 - p`)
  // ===========================================================================
  Widget _buildFluidMorphLyricsScene({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
    required MusEveePalette palette,
    required double t,
    required double screenWidth,
    required double zoneHeight,
    required double homeColumnWidth,
    double homeLeftPad = 26.0,
    double stageSidePad = 32.0,
  }) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final clampedT = t.clamp(0.0, 1.0);
    final isEndpoint = clampedT <= 1e-4 || clampedT >= 1.0 - 1e-4;
    final homeLeftSnapped =
        NowPlayingView.snapToPhysicalPixel(homeLeftPad, dpr);
    final stageLeftSnapped =
        NowPlayingView.snapToPhysicalPixel(stageSidePad, dpr);
    final homeWidthSnapped =
        NowPlayingView.snapToPhysicalPixel(homeColumnWidth, dpr);
    final stageWidth = NowPlayingView.snapToPhysicalPixel(
      math.max(140.0, screenWidth - stageSidePad * 2.0),
      dpr,
    );

    final rawContainerLeft =
        homeLeftSnapped + (stageLeftSnapped - homeLeftSnapped) * clampedT;
    final containerLeft = isEndpoint
        ? NowPlayingView.snapToPhysicalPixel(rawContainerLeft, dpr)
        : rawContainerLeft;
    final rawContainerWidth =
        homeWidthSnapped + (stageWidth - homeWidthSnapped) * clampedT;
    final containerWidth = isEndpoint
        ? NowPlayingView.snapToPhysicalPixel(rawContainerWidth, dpr)
        : rawContainerWidth;

    final extraFadeFactor =
        NowPlayingView.computeMorphExtraLinesFadeFactor(clampedT);
    final edgeFadeHeight =
        zoneHeight * MusEveePalette.lyricsPanelEdgeFadeHeightFactor;

    if (song == null) {
      return Stack(
        key: const ValueKey<String>('now_playing_lyrics_morph_scene'),
        fit: StackFit.expand,
        children: [
          Positioned(
            key: const ValueKey<String>('now_playing_lyrics_morph_container'),
            left: containerLeft,
            top: 0,
            bottom: 0,
            width: containerWidth,
            child: Center(
              child: _buildEmptyLibraryColumn(
                context: context,
                localProvider: localProvider,
                palette: palette,
              ),
            ),
          ),
        ],
      );
    }

    if (song.hasLyrics && !song.isLyricsLoadedInMemory) {
      return Stack(
        key: const ValueKey<String>('now_playing_lyrics_morph_scene'),
        fit: StackFit.expand,
        children: [
          Positioned(
            key: const ValueKey<String>('now_playing_lyrics_morph_container'),
            left: containerLeft,
            top: 0,
            bottom: 0,
            width: containerWidth,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: palette.nowPlayingSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final lyricsFontPt = localProvider.lyricsFontSize;
    final stagePrefOffset =
        NowPlayingView.computeStageActiveFontPrefOffset(lyricsFontPt);
    final homePrefOffset =
        NowPlayingView.computeHomeActiveFontPrefOffset(lyricsFontPt);
    final homeMinFontSize =
        NowPlayingView.computeHomeActiveMinFontSize(lyricsFontPt);
    final homeSecondaryFontSize = localProvider.secondaryLyricsFontSize;

    if (localProvider.lyricsDisplayMode == EmbeddedLyricsDisplayMode.synced &&
        song.hasSyncedLyrics) {
      final entries = localProvider.syncedLyricsFor(song);
      if (entries.isNotEmpty) {
        _ensurePanel0LyricsMetricsCached(
          song: song,
          entries: entries,
          columnWidth: stageWidth,
          homeColumnWidth: homeWidthSnapped,
          preferredOffset: stagePrefOffset,
          homePreferredOffset: homePrefOffset,
          homeMinFontSize: homeMinFontSize,
          homeSecondaryFontSize: homeSecondaryFontSize,
          devicePixelRatio: dpr,
        );

        return AnimatedBuilder(
          key: const ValueKey<String>('now_playing_lyrics_morph_scene'),
          animation: Listenable.merge(<Listenable>[
            localProvider.activeLyricIndexNotifier,
            localProvider.progressNotifier,
            _rowGlideTickVersion,
            _lyricSlideProgress,
          ]),
          builder: (context, _) {
            final rawActiveIdx = NowPlayingView.resolveActiveSyncedLyricIndex(
              entries,
              localProvider.positionMs,
            );
            final int effectiveIdx;
            if (localProvider.autoScrollLyrics) {
              effectiveIdx = rawActiveIdx >= 0
                  ? rawActiveIdx.clamp(0, entries.length - 1)
                  : -1;
              _frozenLyricIndex = effectiveIdx;
            } else {
              effectiveIdx = _frozenLyricIndex >= 0
                  ? _frozenLyricIndex.clamp(0, entries.length - 1)
                  : -1;
            }

            final morphSecondaryFontSize =
                NowPlayingView.computeMorphSecondaryFontSize(
              clampedT,
              homeFontSize: homeSecondaryFontSize,
            );
            final emptySlotMetrics = NowPlayingView.measureLyricLineAtWidth(
              '',
              containerWidth: containerWidth,
              fontSize: morphSecondaryFontSize,
              isActiveRole: false,
              devicePixelRatio: dpr,
            );

            final centerIdx = effectiveIdx >= 0 ? effectiveIdx : 0;
            final isCenterActive = effectiveIdx >= 0;
            _lastLyricsPanelScrolledSongPath = song.filePath;
            _lastLyricsPanelScrolledLineIndex = centerIdx;
            final targetStageScrollOffset = _computePanel0TargetScrollOffset(
              centerIdx,
              zoneHeight,
              centerIdx: centerIdx,
              isCenterActive: isCenterActive,
              devicePixelRatio: dpr,
            );
            final preSyncStageScrollDelta =
                _frozenStageScrollOffsetAtDragStart != null
                    ? (targetStageScrollOffset -
                        _frozenStageScrollOffsetAtDragStart!)
                    : 0.0;

            _syncSharedLineChangeAnimation(
              song: song,
              entries: entries,
              effectiveIdx: effectiveIdx,
              autoScrollLyrics: localProvider.autoScrollLyrics,
              currentT: clampedT,
              containerWidth: containerWidth,
              homeWidth: homeWidthSnapped,
              zoneHeight: zoneHeight,
              preferredOffset: stagePrefOffset,
              homePreferredOffset: homePrefOffset,
              homeMinFontSize: homeMinFontSize,
              homeSecondaryFontSize: homeSecondaryFontSize,
              stageScrollDelta: preSyncStageScrollDelta,
              dpr: dpr,
              emptySlotHeight: emptySlotMetrics.slotHeight,
              isInFluidMorph: true,
            );

            _lyricsPanelScrollController.initialOffsetResolver = () =>
                _frozenStageScrollOffsetAtDragStart ?? targetStageScrollOffset;

            const gap = NowPlayingView.lyricSlotVerticalGap;
            final stageScrollDelta = _frozenStageScrollOffsetAtDragStart != null
                ? (targetStageScrollOffset -
                    _frozenStageScrollOffsetAtDragStart!)
                : 0.0;

            CachedLyricLineMetrics? stageLockedSecMetricsFor(int lineIdx) {
              if (clampedT < 0.5) return null;
              final actM = _cachedPanel0ActiveMetrics[lineIdx];
              if (actM == null) return null;
              if (clampedT >= 1.0 - 1e-4 &&
                  (containerWidth - stageWidth).abs() <= 0.01 &&
                  _cachedPanel0SecondaryMetrics.containsKey(lineIdx)) {
                return _cachedPanel0SecondaryMetrics[lineIdx];
              }
              return NowPlayingView.measureSecondaryLyricFromActiveMetrics(
                actM,
                containerWidth: containerWidth,
                fontSize: morphSecondaryFontSize,
                devicePixelRatio: dpr,
              );
            }

            // Section C: Intro stack (`effectiveIdx == -1`, including Demotion `0 -> -1`)
            if (!isCenterActive) {
              final has0 = entries.isNotEmpty;
              final has1 = entries.length > 1;
              final has2 = entries.length > 2;
              final text0 = has0
                  ? (entries[0].text.trim().isEmpty
                      ? '♪'
                      : entries[0].text.trim())
                  : '';
              final text1 = has1
                  ? (entries[1].text.trim().isEmpty
                      ? '♪'
                      : entries[1].text.trim())
                  : '';
              final text2 = has2
                  ? (entries[2].text.trim().isEmpty
                      ? '♪'
                      : entries[2].text.trim())
                  : '';
              final homeActiveRoleFontSize0 =
                  _cachedActiveLineMetrics[0]?.fontSize ??
                      NowPlayingView.computeActiveLyricFontSize(
                        text0,
                        maxWidth: homeWidthSnapped,
                        preferredOffset: homePrefOffset,
                        minFontSize: homeMinFontSize,
                      );
              final stageActiveRoleFontSize0 =
                  _cachedPanel0ActiveMetrics[0]?.fontSize ??
                      NowPlayingView.computeActiveLyricFontSize(
                        text0,
                        maxWidth: homeWidthSnapped,
                        preferredOffset: stagePrefOffset,
                      );
              final activeRoleFontSize0 = homeActiveRoleFontSize0 +
                  (stageActiveRoleFontSize0 - homeActiveRoleFontSize0) *
                      clampedT;

              final secLayout0 = has0
                  ? _resolveLineMorphMetricsAndGlide(
                      songPath: song.filePath,
                      centerIdx: 0,
                      lineIndex: 0,
                      rawText: text0,
                      containerWidth: containerWidth,
                      fontSize: morphSecondaryFontSize,
                      isActiveRole: false,
                      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                      devicePixelRatio: dpr,
                      lockedMetricsOverride: stageLockedSecMetricsFor(0),
                      allowFontScaleGlide: true,
                    )
                  : _ResolvedLineRowLayout(
                      metrics: emptySlotMetrics,
                      animatedSlotHeight: emptySlotMetrics.slotHeight,
                      animatedRowTops:
                          _canonicalRowTopsForMetrics(emptySlotMetrics),
                      isGliding: false,
                    );
              final actLayout0 = has0
                  ? _resolveLineMorphMetricsAndGlide(
                      songPath: song.filePath,
                      centerIdx: 0,
                      lineIndex: 0,
                      rawText: text0,
                      containerWidth: containerWidth,
                      fontSize: activeRoleFontSize0,
                      isActiveRole: true,
                      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                      devicePixelRatio: dpr,
                      recordAsRenderedState: false,
                      allowFontScaleGlide: true,
                    )
                  : secLayout0;
              final secLayout1 = has1
                  ? _resolveLineMorphMetricsAndGlide(
                      songPath: song.filePath,
                      centerIdx: 0,
                      lineIndex: 1,
                      rawText: text1,
                      containerWidth: containerWidth,
                      fontSize: morphSecondaryFontSize,
                      isActiveRole: false,
                      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                      devicePixelRatio: dpr,
                      lockedMetricsOverride: stageLockedSecMetricsFor(1),
                      allowFontScaleGlide: true,
                    )
                  : _ResolvedLineRowLayout(
                      metrics: emptySlotMetrics,
                      animatedSlotHeight: emptySlotMetrics.slotHeight,
                      animatedRowTops:
                          _canonicalRowTopsForMetrics(emptySlotMetrics),
                      isGliding: false,
                    );
              final secLayout2 = has2
                  ? _resolveLineMorphMetricsAndGlide(
                      songPath: song.filePath,
                      centerIdx: 0,
                      lineIndex: 2,
                      rawText: text2,
                      containerWidth: containerWidth,
                      fontSize: morphSecondaryFontSize,
                      isActiveRole: false,
                      hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                      devicePixelRatio: dpr,
                      lockedMetricsOverride: stageLockedSecMetricsFor(2),
                      allowFontScaleGlide: true,
                    )
                  : _ResolvedLineRowLayout(
                      metrics: emptySlotMetrics,
                      animatedSlotHeight: emptySlotMetrics.slotHeight,
                      animatedRowTops:
                          _canonicalRowTopsForMetrics(emptySlotMetrics),
                      isGliding: false,
                    );

              final isDemotionStep = _slideAnimatedLyricIndex == -1 &&
                  _lyricSlideController.value < 1.0;
              final slideU = isDemotionStep ? _lyricSlideProgress.value : 1.0;
              final snapPositions =
                  isEndpoint && !isRowGlideAnimating && !isDemotionStep;

              final h0 = snapPositions
                  ? NowPlayingView.snapToPhysicalPixel(
                      secLayout0.animatedSlotHeight,
                      dpr,
                    )
                  : secLayout0.animatedSlotHeight;
              final h1 = snapPositions
                  ? NowPlayingView.snapToPhysicalPixel(
                      secLayout1.animatedSlotHeight,
                      dpr,
                    )
                  : secLayout1.animatedSlotHeight;
              final h2 = snapPositions
                  ? NowPlayingView.snapToPhysicalPixel(
                      secLayout2.animatedSlotHeight,
                      dpr,
                    )
                  : secLayout2.animatedSlotHeight;

              final liveSnaps = _resolveInterpolatedLineSnapshots(
                entries: entries,
                centerIdx: -1,
                t: clampedT,
                u: slideU,
                containerWidth: containerWidth,
                homeWidth: homeWidthSnapped,
                zoneHeight: zoneHeight,
                preferredOffset: stagePrefOffset,
                homePreferredOffset: homePrefOffset,
                homeMinFontSize: homeMinFontSize,
                homeSecondaryFontSize: homeSecondaryFontSize,
                stageScrollDelta: stageScrollDelta,
                dpr: dpr,
                emptySlotHeight: emptySlotMetrics.slotHeight,
                resolvedPrevSlotH: h0,
                resolvedCenterSlotH: h1,
                resolvedNextSlotH: h2,
              );

              final snap0 = liveSnaps[0]!;
              final snap1 = liveSnaps[1];
              final snap2 = liveSnaps[2];

              final top0 = snapPositions
                  ? NowPlayingView.snapToPhysicalPixel(snap0.top, dpr)
                  : snap0.top;
              final slotH0 = snapPositions
                  ? NowPlayingView.snapToPhysicalPixel(snap0.slotHeight, dpr)
                  : snap0.slotHeight;
              final color0 = Color.lerp(
                    palette.nowPlayingSecondary,
                    palette.nowPlayingPrimary,
                    snap0.colorBlend,
                  ) ??
                  palette.nowPlayingSecondary;

              CachedLyricLineMetrics metrics0 = secLayout0.metrics;
              List<double>? rowTops0 = secLayout0.animatedRowTops;
              double? fontOverride0 = isDemotionStep ? snap0.fontSize : null;
              if (isDemotionStep &&
                  secLayout0.metrics.wrappedLineCount !=
                      actLayout0.metrics.wrappedLineCount) {
                metrics0 = snap0.colorBlend >= 0.5
                    ? actLayout0.metrics
                    : secLayout0.metrics;
                rowTops0 = null;
                final maxSafeFont0 = slotH0 /
                    (math.max(1, metrics0.wrappedLineCount) *
                        MusEveePalette.lyricLineHeight);
                fontOverride0 = math.min(snap0.fontSize, maxSafeFont0);
              }

              final top1 = snap1 != null
                  ? (snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(snap1.top, dpr)
                      : snap1.top)
                  : (top0 + slotH0 + gap);
              final slotH1 = snap1 != null
                  ? (snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(
                          snap1.slotHeight,
                          dpr,
                        )
                      : snap1.slotHeight)
                  : h1;
              final op1 = snap1?.opacity ?? 0.0;

              final top2 = snap2 != null
                  ? (snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(snap2.top, dpr)
                      : snap2.top)
                  : (top1 + slotH1 + gap);
              final slotH2 = snap2 != null
                  ? (snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(
                          snap2.slotHeight,
                          dpr,
                        )
                      : snap2.slotHeight)
                  : h2;
              final op2 = snap2?.opacity ?? 0.0;

              final List<Widget> introExtraWidgets = <Widget>[];
              if (extraFadeFactor > 0.0) {
                double runningBelowTop = top2 + slotH2 + gap;
                for (int i = 3; i < entries.length; i++) {
                  final baseM = _cachedPanel0SecondaryMetrics[i] ??
                      NowPlayingView.measureLyricLineAtWidth(
                        entries[i].text,
                        containerWidth: stageWidth,
                        fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                        isActiveRole: false,
                        devicePixelRatio: dpr,
                      );
                  final m = baseM.copyWithContainerWidth(containerWidth);
                  final slotH = m.slotHeight;
                  final lineTop = snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(runningBelowTop, dpr)
                      : runningBelowTop;
                  runningBelowTop += slotH + gap;
                  if (lineTop > zoneHeight + 40.0) continue;
                  introExtraWidgets.add(
                    Positioned(
                      key: ValueKey<String>('morph_lyric_slot_$i'),
                      left: 0,
                      top: lineTop,
                      width: containerWidth,
                      height: slotH,
                      child: IgnorePointer(
                        child: Opacity(
                          key: ValueKey<String>('morph_lyric_opacity_$i'),
                          opacity: 0.0,
                          child: _buildLyricRowBlock(
                            metrics: m,
                            containerWidth: containerWidth,
                            centeringT: 1.0,
                            textColor: palette.nowPlayingSecondary,
                            devicePixelRatio: dpr,
                            snapRowPositions: snapPositions,
                            rowKeyPrefix: 'morph_lyric_$i',
                            firstRowTextKey:
                                ValueKey<String>('morph_lyric_text_$i'),
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    key: const ValueKey<String>(
                      'now_playing_lyrics_morph_container',
                    ),
                    left: containerLeft,
                    top: 0,
                    bottom: 0,
                    width: containerWidth,
                    child: Stack(
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        ...introExtraWidgets,
                        // Intro Slot 0 (Line 0: top slot at Home -> center slot at Stage)
                        Positioned(
                          key: const ValueKey<String>('morph_lyric_slot_0'),
                          left: 0,
                          top: top0,
                          width: containerWidth,
                          height: slotH0,
                          child: Opacity(
                            key: const ValueKey<String>(
                              'morph_lyric_opacity_0',
                            ),
                            opacity: snap0.opacity.clamp(0.0, 1.0),
                            child: _buildLyricRowBlock(
                              metrics: metrics0,
                              containerWidth: containerWidth,
                              centeringT: clampedT,
                              textColor: color0,
                              devicePixelRatio: dpr,
                              animatedRowTops: rowTops0,
                              snapRowPositions: snapPositions,
                              rowKeyPrefix: 'morph_lyric_0',
                              firstRowTextKey: const ValueKey<String>(
                                'morph_lyric_text_0',
                              ),
                              fontSizeOverride: fontOverride0,
                              slotHeightOverride:
                                  isDemotionStep ? slotH0 : null,
                            ),
                          ),
                        ),
                        // Intro Slot 1 (Line 1: middle slot at Home -> next slot at Stage)
                        Positioned(
                          key: has1
                              ? const ValueKey<String>('morph_lyric_slot_1')
                              : const ValueKey<String>(
                                  'morph_lyric_slot_next_empty',
                                ),
                          left: 0,
                          top: top1,
                          width: containerWidth,
                          height: slotH1,
                          child: Opacity(
                            key: has1
                                ? const ValueKey<String>(
                                    'morph_lyric_opacity_1',
                                  )
                                : const ValueKey<String>(
                                    'morph_lyric_opacity_next_empty',
                                  ),
                            opacity: op1.clamp(0.0, 1.0),
                            child: _buildLyricRowBlock(
                              metrics: secLayout1.metrics,
                              containerWidth: containerWidth,
                              centeringT: clampedT,
                              textColor: palette.nowPlayingSecondary,
                              devicePixelRatio: dpr,
                              animatedRowTops: secLayout1.animatedRowTops,
                              snapRowPositions: snapPositions,
                              rowKeyPrefix: has1
                                  ? 'morph_lyric_1'
                                  : 'morph_lyric_next_empty',
                              firstRowTextKey: has1
                                  ? const ValueKey<String>('morph_lyric_text_1')
                                  : const ValueKey<String>(
                                      'morph_lyric_text_next_empty',
                                    ),
                              fontSizeOverride:
                                  isDemotionStep ? snap1?.fontSize : null,
                              slotHeightOverride:
                                  isDemotionStep ? slotH1 : null,
                            ),
                          ),
                        ),
                        // Intro Slot 2 (Line 2: bottom slot at Home -> fades to 0.0 at Stage)
                        if (has2)
                          Positioned(
                            key: const ValueKey<String>('morph_lyric_slot_2'),
                            left: 0,
                            top: top2,
                            width: containerWidth,
                            height: slotH2,
                            child: Opacity(
                              key: const ValueKey<String>(
                                'morph_lyric_opacity_2',
                              ),
                              opacity: op2.clamp(0.0, 1.0),
                              child: _buildLyricRowBlock(
                                metrics: secLayout2.metrics,
                                containerWidth: containerWidth,
                                centeringT: clampedT,
                                textColor: palette.nowPlayingSecondary,
                                devicePixelRatio: dpr,
                                animatedRowTops: secLayout2.animatedRowTops,
                                snapRowPositions: snapPositions,
                                rowKeyPrefix: 'morph_lyric_2',
                                firstRowTextKey: const ValueKey<String>(
                                  'morph_lyric_text_2',
                                ),
                                fontSizeOverride:
                                    isDemotionStep ? snap2?.fontSize : null,
                                slotHeightOverride:
                                    isDemotionStep ? slotH2 : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }

            final prevIdx = centerIdx - 1;
            final nextIdx = centerIdx + 1;
            final hasPrev = prevIdx >= 0;
            final hasNext = nextIdx < entries.length;

            final prevText = hasPrev
                ? (entries[prevIdx].text.trim().isEmpty
                    ? '♪'
                    : entries[prevIdx].text.trim())
                : '';
            final centerText = entries[centerIdx].text.trim().isEmpty
                ? '♪'
                : entries[centerIdx].text.trim();
            final nextText = hasNext
                ? (entries[nextIdx].text.trim().isEmpty
                    ? '♪'
                    : entries[nextIdx].text.trim())
                : '';

            final homeActiveRoleFontSize =
                _cachedActiveLineMetrics[centerIdx]?.fontSize ??
                    NowPlayingView.computeActiveLyricFontSize(
                      centerText,
                      maxWidth: homeWidthSnapped,
                      preferredOffset: homePrefOffset,
                      minFontSize: homeMinFontSize,
                    );
            final stageActiveRoleFontSize =
                _cachedPanel0ActiveMetrics[centerIdx]?.fontSize ??
                    NowPlayingView.computeActiveLyricFontSize(
                      centerText,
                      maxWidth: homeWidthSnapped,
                      preferredOffset: stagePrefOffset,
                    );
            final activeRoleFontSize = homeActiveRoleFontSize +
                (stageActiveRoleFontSize - homeActiveRoleFontSize) * clampedT;

            // Live row-level measurement of the 3 core lines against current containerWidth(t)
            // with ±8px wrap hysteresis and 180ms easeOutCubic row-glide animation
            final prevLayout = hasPrev
                ? _resolveLineMorphMetricsAndGlide(
                    songPath: song.filePath,
                    centerIdx: centerIdx,
                    lineIndex: prevIdx,
                    rawText: prevText,
                    containerWidth: containerWidth,
                    fontSize: morphSecondaryFontSize,
                    isActiveRole: false,
                    hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                    devicePixelRatio: dpr,
                    lockedMetricsOverride: stageLockedSecMetricsFor(prevIdx),
                    allowFontScaleGlide: true,
                  )
                : _ResolvedLineRowLayout(
                    metrics: emptySlotMetrics,
                    animatedSlotHeight: emptySlotMetrics.slotHeight,
                    animatedRowTops: _canonicalRowTopsForMetrics(
                      emptySlotMetrics,
                    ),
                    isGliding: false,
                  );
            final centerActiveRoleLayout = _resolveLineMorphMetricsAndGlide(
              songPath: song.filePath,
              centerIdx: centerIdx,
              lineIndex: centerIdx,
              rawText: centerText,
              containerWidth: containerWidth,
              fontSize: activeRoleFontSize,
              isActiveRole: true,
              hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
              devicePixelRatio: dpr,
              recordAsRenderedState: true,
              allowFontScaleGlide: true,
              lockedMetricsOverride: (clampedT >= 1.0 - 1e-4 &&
                      (containerWidth - stageWidth).abs() <= 0.01)
                  ? _cachedPanel0ActiveMetrics[centerIdx]
                  : null,
            );
            final centerRenderLayout = centerActiveRoleLayout;
            final nextLayout = hasNext
                ? _resolveLineMorphMetricsAndGlide(
                    songPath: song.filePath,
                    centerIdx: centerIdx,
                    lineIndex: nextIdx,
                    rawText: nextText,
                    containerWidth: containerWidth,
                    fontSize: morphSecondaryFontSize,
                    isActiveRole: false,
                    hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                    devicePixelRatio: dpr,
                    lockedMetricsOverride: stageLockedSecMetricsFor(nextIdx),
                    allowFontScaleGlide: true,
                  )
                : _ResolvedLineRowLayout(
                    metrics: emptySlotMetrics,
                    animatedSlotHeight: emptySlotMetrics.slotHeight,
                    animatedRowTops: _canonicalRowTopsForMetrics(
                      emptySlotMetrics,
                    ),
                    isGliding: false,
                  );

            final isAnimatingStep = isCenterActive &&
                _slideAnimatedLyricIndex == effectiveIdx &&
                _lyricSlideController.value < 1.0;
            final slideU = isAnimatingStep ? _lyricSlideProgress.value : 1.0;
            final snapPositions =
                isEndpoint && !isRowGlideAnimating && !isAnimatingStep;
            final basePrevSlotH = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(
                    prevLayout.animatedSlotHeight,
                    dpr,
                  )
                : prevLayout.animatedSlotHeight;
            final baseCenterSlotH = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(
                    centerActiveRoleLayout.animatedSlotHeight,
                    dpr,
                  )
                : centerActiveRoleLayout.animatedSlotHeight;
            final baseNextSlotH = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(
                    nextLayout.animatedSlotHeight,
                    dpr,
                  )
                : nextLayout.animatedSlotHeight;

            final liveSnaps = _resolveInterpolatedLineSnapshots(
              entries: entries,
              centerIdx: centerIdx,
              t: clampedT,
              u: slideU,
              containerWidth: containerWidth,
              homeWidth: homeWidthSnapped,
              zoneHeight: zoneHeight,
              preferredOffset: stagePrefOffset,
              homePreferredOffset: homePrefOffset,
              homeMinFontSize: homeMinFontSize,
              homeSecondaryFontSize: homeSecondaryFontSize,
              stageScrollDelta: stageScrollDelta,
              dpr: dpr,
              emptySlotHeight: emptySlotMetrics.slotHeight,
              resolvedPrevSlotH: basePrevSlotH,
              resolvedCenterSlotH: baseCenterSlotH,
              resolvedNextSlotH: baseNextSlotH,
            );

            final homeCenterTop = NowPlayingView.snapToPhysicalPixel(
              (zoneHeight - baseCenterSlotH + basePrevSlotH - baseNextSlotH) /
                  2.0,
              dpr,
            );
            final stageCenterTop = NowPlayingView.snapToPhysicalPixel(
              (zoneHeight - baseCenterSlotH) / 2.0,
              dpr,
            );
            final effectiveStageCenterTop = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(
                    stageCenterTop + stageScrollDelta,
                    dpr,
                  )
                : (stageCenterTop + stageScrollDelta);
            final rawCenterTop = homeCenterTop +
                (effectiveStageCenterTop - homeCenterTop) * clampedT;
            final restCenterTop = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(rawCenterTop, dpr)
                : rawCenterTop;
            final restPrevTop = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(
                    restCenterTop - gap - basePrevSlotH,
                    dpr,
                  )
                : (restCenterTop - gap - basePrevSlotH);
            final restNextTop = snapPositions
                ? NowPlayingView.snapToPhysicalPixel(
                    restCenterTop + baseCenterSlotH + gap,
                    dpr,
                  )
                : (restCenterTop + baseCenterSlotH + gap);

            final prevSnap = hasPrev ? liveSnaps[prevIdx] : null;
            final centerSnap = liveSnaps[centerIdx];
            final nextSnap = hasNext ? liveSnaps[nextIdx] : null;

            final prevTop = (isAnimatingStep && prevSnap != null)
                ? prevSnap.top
                : restPrevTop;
            final prevSlotH = (isAnimatingStep && prevSnap != null)
                ? prevSnap.slotHeight
                : basePrevSlotH;
            final prevFontSize = (isAnimatingStep && prevSnap != null)
                ? prevSnap.fontSize
                : null;
            final prevColor = (isAnimatingStep && prevSnap != null)
                ? (Color.lerp(
                      palette.nowPlayingSecondary,
                      palette.nowPlayingPrimary,
                      prevSnap.colorBlend,
                    ) ??
                    palette.nowPlayingSecondary)
                : palette.nowPlayingSecondary;

            final centerTop = (isAnimatingStep && centerSnap != null)
                ? centerSnap.top
                : restCenterTop;
            final centerSlotH = (isAnimatingStep && centerSnap != null)
                ? centerSnap.slotHeight
                : baseCenterSlotH;
            final centerFontSize = (isAnimatingStep && centerSnap != null)
                ? centerSnap.fontSize
                : null;
            final centerMetricsToRender = centerRenderLayout.metrics;
            final centerRowTopsToRender = centerRenderLayout.animatedRowTops;
            final centerColor = (isAnimatingStep && centerSnap != null)
                ? (Color.lerp(
                      palette.nowPlayingSecondary,
                      palette.nowPlayingPrimary,
                      centerSnap.colorBlend,
                    ) ??
                    palette.nowPlayingPrimary)
                : palette.nowPlayingPrimary;

            final nextTop = (isAnimatingStep && nextSnap != null)
                ? nextSnap.top
                : restNextTop;
            final nextSlotH = (isAnimatingStep && nextSnap != null)
                ? nextSnap.slotHeight
                : baseNextSlotH;
            final nextFontSize = (isAnimatingStep && nextSnap != null)
                ? nextSnap.fontSize
                : null;
            final nextColor = (isAnimatingStep && nextSnap != null)
                ? (Color.lerp(
                      palette.nowPlayingSecondary,
                      palette.nowPlayingPrimary,
                      nextSnap.colorBlend,
                    ) ??
                    palette.nowPlayingSecondary)
                : palette.nowPlayingSecondary;

            final prevStageOpacity = hasPrev
                ? NowPlayingView.lyricPanelOpacityForDistance(
                    (prevIdx - effectiveIdx).abs(),
                  )
                : 0.0;
            final centerStageOpacity =
                NowPlayingView.lyricPanelOpacityForDistance(
              (centerIdx - effectiveIdx).abs(),
            );
            final nextStageOpacity = hasNext
                ? NowPlayingView.lyricPanelOpacityForDistance(
                    (nextIdx - effectiveIdx).abs(),
                  )
                : 0.0;

            final restPrevOpacity =
                hasPrev ? (1.0 + (prevStageOpacity - 1.0) * clampedT) : 1.0;
            final restCenterOpacity = isCenterActive
                ? 1.0
                : (1.0 + (centerStageOpacity - 1.0) * clampedT);
            final restNextOpacity =
                hasNext ? (1.0 + (nextStageOpacity - 1.0) * clampedT) : 1.0;

            final prevOpacity = (isAnimatingStep && prevSnap != null)
                ? prevSnap.opacity
                : restPrevOpacity;
            final centerOpacity = (isAnimatingStep && centerSnap != null)
                ? centerSnap.opacity
                : restCenterOpacity;
            final nextOpacity = (isAnimatingStep && nextSnap != null)
                ? nextSnap.opacity
                : restNextOpacity;

            // Outgoing top line (centerIdx - 2) during a mid-morph line change,
            // outgoing bottom line (2) during Promotion (-1 -> 0),
            // plus extra stage lines beyond the core three (distance >= 2 from centerIdx)
            // which stay at Rest opacity 0.0 (Section B).
            final List<Widget> extraLineWidgets = <Widget>[];
            final outgoingTopIdx = centerIdx - 2;
            final hasAnimatedOutgoingTop = isAnimatingStep &&
                outgoingTopIdx >= 0 &&
                liveSnaps.containsKey(outgoingTopIdx);
            if (hasAnimatedOutgoingTop) {
              final outSnap = liveSnaps[outgoingTopIdx]!;
              final outRaw = entries[outgoingTopIdx].text.trim();
              final outText = outRaw.isEmpty ? '♪' : outRaw;
              final outLayout = _resolveLineMorphMetricsAndGlide(
                songPath: song.filePath,
                centerIdx: centerIdx,
                lineIndex: outgoingTopIdx,
                rawText: outText,
                containerWidth: containerWidth,
                fontSize: morphSecondaryFontSize,
                isActiveRole: false,
                hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                devicePixelRatio: dpr,
                lockedMetricsOverride: stageLockedSecMetricsFor(outgoingTopIdx),
              );
              extraLineWidgets.add(
                Positioned(
                  key: ValueKey<String>('morph_lyric_slot_$outgoingTopIdx'),
                  left: 0,
                  top: outSnap.top,
                  width: containerWidth,
                  height: outSnap.slotHeight,
                  child: Opacity(
                    key: ValueKey<String>(
                      'morph_lyric_opacity_$outgoingTopIdx',
                    ),
                    opacity: outSnap.opacity.clamp(0.0, 1.0),
                    child: _buildLyricRowBlock(
                      metrics: outLayout.metrics,
                      containerWidth: containerWidth,
                      centeringT: clampedT,
                      textColor: palette.nowPlayingSecondary,
                      devicePixelRatio: dpr,
                      animatedRowTops: outLayout.animatedRowTops,
                      snapRowPositions: snapPositions,
                      rowKeyPrefix: 'morph_lyric_$outgoingTopIdx',
                      firstRowTextKey: ValueKey<String>(
                        'morph_lyric_text_$outgoingTopIdx',
                      ),
                      fontSizeOverride: outSnap.fontSize,
                      slotHeightOverride: outSnap.slotHeight,
                    ),
                  ),
                ),
              );
            }

            final hasAnimatedPromotionBottom = isAnimatingStep &&
                _slideFromCenterIdx == -1 &&
                centerIdx == 0 &&
                entries.length > 2 &&
                liveSnaps.containsKey(2);
            if (hasAnimatedPromotionBottom) {
              final outBotSnap = liveSnaps[2]!;
              final outBotRaw = entries[2].text.trim();
              final outBotText = outBotRaw.isEmpty ? '♪' : outBotRaw;
              final outBotLayout = _resolveLineMorphMetricsAndGlide(
                songPath: song.filePath,
                centerIdx: 0,
                lineIndex: 2,
                rawText: outBotText,
                containerWidth: containerWidth,
                fontSize: morphSecondaryFontSize,
                isActiveRole: false,
                hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                devicePixelRatio: dpr,
                lockedMetricsOverride: stageLockedSecMetricsFor(2),
              );
              extraLineWidgets.add(
                Positioned(
                  key: const ValueKey<String>('morph_lyric_slot_2'),
                  left: 0,
                  top: outBotSnap.top,
                  width: containerWidth,
                  height: outBotSnap.slotHeight,
                  child: Opacity(
                    key: const ValueKey<String>('morph_lyric_opacity_2'),
                    opacity: outBotSnap.opacity.clamp(0.0, 1.0),
                    child: _buildLyricRowBlock(
                      metrics: outBotLayout.metrics,
                      containerWidth: containerWidth,
                      centeringT: clampedT,
                      textColor: palette.nowPlayingSecondary,
                      devicePixelRatio: dpr,
                      animatedRowTops: outBotLayout.animatedRowTops,
                      snapRowPositions: snapPositions,
                      rowKeyPrefix: 'morph_lyric_2',
                      firstRowTextKey: const ValueKey<String>(
                        'morph_lyric_text_2',
                      ),
                      fontSizeOverride: outBotSnap.fontSize,
                      slotHeightOverride: outBotSnap.slotHeight,
                    ),
                  ),
                ),
              );
            }

            if (extraFadeFactor > 0.0) {
              double runningAboveTop = hasAnimatedOutgoingTop
                  ? liveSnaps[outgoingTopIdx]!.top
                  : prevTop;
              final startAboveIdx =
                  hasAnimatedOutgoingTop ? (centerIdx - 3) : (centerIdx - 2);
              for (int i = startAboveIdx; i >= 0; i--) {
                final baseM = _cachedPanel0SecondaryMetrics[i] ??
                    NowPlayingView.measureLyricLineAtWidth(
                      entries[i].text,
                      containerWidth: stageWidth,
                      fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                      isActiveRole: false,
                      devicePixelRatio: dpr,
                    );
                final m = baseM.copyWithContainerWidth(containerWidth);
                final slotH = m.slotHeight;
                runningAboveTop -= (gap + slotH);
                final lineTop = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(runningAboveTop, dpr)
                    : runningAboveTop;
                if (lineTop + slotH < -40.0) continue;
                // Section B: Extra lines target Rest mode opacity (0.0) during morph
                extraLineWidgets.add(
                  Positioned(
                    key: ValueKey<String>('morph_lyric_slot_$i'),
                    left: 0,
                    top: lineTop,
                    width: containerWidth,
                    height: slotH,
                    child: IgnorePointer(
                      child: Opacity(
                        key: ValueKey<String>('morph_lyric_opacity_$i'),
                        opacity: 0.0,
                        child: _buildLyricRowBlock(
                          metrics: m,
                          containerWidth: containerWidth,
                          centeringT: 1.0,
                          textColor: palette.nowPlayingSecondary,
                          devicePixelRatio: dpr,
                          snapRowPositions: snapPositions,
                          rowKeyPrefix: 'morph_lyric_$i',
                          firstRowTextKey:
                              ValueKey<String>('morph_lyric_text_$i'),
                        ),
                      ),
                    ),
                  ),
                );
              }

              double runningBelowTop = hasAnimatedPromotionBottom
                  ? (liveSnaps[2]!.top + liveSnaps[2]!.slotHeight + gap)
                  : (nextTop + nextSlotH + gap);
              final startBelowIdx =
                  hasAnimatedPromotionBottom ? 3 : (centerIdx + 2);
              for (int i = startBelowIdx; i < entries.length; i++) {
                final baseM = _cachedPanel0SecondaryMetrics[i] ??
                    NowPlayingView.measureLyricLineAtWidth(
                      entries[i].text,
                      containerWidth: stageWidth,
                      fontSize: MusEveePalette.lyricPanelSecondaryFontSize,
                      isActiveRole: false,
                      devicePixelRatio: dpr,
                    );
                final m = baseM.copyWithContainerWidth(containerWidth);
                final slotH = m.slotHeight;
                final lineTop = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(runningBelowTop, dpr)
                    : runningBelowTop;
                runningBelowTop += slotH + gap;
                if (lineTop > zoneHeight + 40.0) continue;
                // Section B: Extra lines target Rest mode opacity (0.0) during morph
                extraLineWidgets.add(
                  Positioned(
                    key: ValueKey<String>('morph_lyric_slot_$i'),
                    left: 0,
                    top: lineTop,
                    width: containerWidth,
                    height: slotH,
                    child: IgnorePointer(
                      child: Opacity(
                        key: ValueKey<String>('morph_lyric_opacity_$i'),
                        opacity: 0.0,
                        child: _buildLyricRowBlock(
                          metrics: m,
                          containerWidth: containerWidth,
                          centeringT: 1.0,
                          textColor: palette.nowPlayingSecondary,
                          devicePixelRatio: dpr,
                          snapRowPositions: snapPositions,
                          rowKeyPrefix: 'morph_lyric_$i',
                          firstRowTextKey:
                              ValueKey<String>('morph_lyric_text_$i'),
                        ),
                      ),
                    ),
                  ),
                );
              }
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  key: const ValueKey<String>(
                    'now_playing_lyrics_morph_container',
                  ),
                  left: containerLeft,
                  top: 0,
                  bottom: 0,
                  width: containerWidth,
                  child: Stack(
                    clipBehavior: Clip.none,
                    fit: StackFit.expand,
                    children: [
                      ...extraLineWidgets,

                      // 1. Core Previous Slot (or empty placeholder at song start)
                      Positioned(
                        key: hasPrev
                            ? ValueKey<String>('morph_lyric_slot_$prevIdx')
                            : const ValueKey<String>(
                                'morph_lyric_slot_prev_empty',
                              ),
                        left: 0,
                        top: prevTop,
                        width: containerWidth,
                        height: prevSlotH,
                        child: Opacity(
                          key: hasPrev
                              ? ValueKey<String>(
                                  'morph_lyric_opacity_$prevIdx',
                                )
                              : const ValueKey<String>(
                                  'morph_lyric_opacity_prev_empty',
                                ),
                          opacity: prevOpacity,
                          child: _buildLyricRowBlock(
                            metrics: prevLayout.metrics,
                            containerWidth: containerWidth,
                            centeringT: clampedT,
                            textColor: prevColor,
                            devicePixelRatio: dpr,
                            animatedRowTops: prevLayout.animatedRowTops,
                            snapRowPositions: snapPositions,
                            rowKeyPrefix: hasPrev
                                ? 'morph_lyric_$prevIdx'
                                : 'morph_lyric_prev_empty',
                            firstRowTextKey: hasPrev
                                ? ValueKey<String>('morph_lyric_text_$prevIdx')
                                : const ValueKey<String>(
                                    'morph_lyric_text_prev_empty',
                                  ),
                            fontSizeOverride: prevFontSize,
                            slotHeightOverride:
                                isAnimatingStep ? prevSlotH : null,
                          ),
                        ),
                      ),

                      // 2. Core Center Slot (Active line when effectiveIdx >= 0)
                      Positioned(
                        key: ValueKey<String>('morph_lyric_slot_$centerIdx'),
                        left: 0,
                        top: centerTop,
                        width: containerWidth,
                        height: centerSlotH,
                        child: Opacity(
                          key: ValueKey<String>(
                            'morph_lyric_opacity_$centerIdx',
                          ),
                          opacity: centerOpacity,
                          child: _buildLyricRowBlock(
                            metrics: centerMetricsToRender,
                            containerWidth: containerWidth,
                            centeringT: clampedT,
                            textColor: centerColor,
                            devicePixelRatio: dpr,
                            animatedRowTops: centerRowTopsToRender,
                            snapRowPositions: snapPositions,
                            rowKeyPrefix: 'morph_lyric_$centerIdx',
                            firstRowTextKey: ValueKey<String>(
                              'morph_lyric_text_$centerIdx',
                            ),
                            fontSizeOverride: centerFontSize,
                            slotHeightOverride:
                                isAnimatingStep ? centerSlotH : null,
                          ),
                        ),
                      ),

                      // 3. Core Next Slot (or empty placeholder at song end)
                      Positioned(
                        key: hasNext
                            ? ValueKey<String>('morph_lyric_slot_$nextIdx')
                            : const ValueKey<String>(
                                'morph_lyric_slot_next_empty',
                              ),
                        left: 0,
                        top: nextTop,
                        width: containerWidth,
                        height: nextSlotH,
                        child: Opacity(
                          key: hasNext
                              ? ValueKey<String>(
                                  'morph_lyric_opacity_$nextIdx',
                                )
                              : const ValueKey<String>(
                                  'morph_lyric_opacity_next_empty',
                                ),
                          opacity: nextOpacity,
                          child: _buildLyricRowBlock(
                            metrics: nextLayout.metrics,
                            containerWidth: containerWidth,
                            centeringT: clampedT,
                            textColor: nextColor,
                            devicePixelRatio: dpr,
                            animatedRowTops: nextLayout.animatedRowTops,
                            snapRowPositions: snapPositions,
                            rowKeyPrefix: hasNext
                                ? 'morph_lyric_$nextIdx'
                                : 'morph_lyric_next_empty',
                            firstRowTextKey: hasNext
                                ? ValueKey<String>('morph_lyric_text_$nextIdx')
                                : const ValueKey<String>(
                                    'morph_lyric_text_next_empty',
                                  ),
                            fontSizeOverride: nextFontSize,
                            slotHeightOverride:
                                isAnimatingStep ? nextSlotH : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (extraFadeFactor > 0.0) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: edgeFadeHeight,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: extraFadeFactor,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                palette.nowPlayingBg,
                                palette.nowPlayingBg.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: edgeFadeHeight,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: extraFadeFactor,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                palette.nowPlayingBg.withValues(alpha: 0.0),
                                palette.nowPlayingBg,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      }
    }

    // Plain (untimed) or no-lyrics fallback inside the morphing container
    return Stack(
      key: const ValueKey<String>('now_playing_lyrics_morph_scene'),
      fit: StackFit.expand,
      children: [
        Positioned(
          key: const ValueKey<String>('now_playing_lyrics_morph_container'),
          left: containerLeft,
          top: 0,
          bottom: 0,
          width: containerWidth,
          child: _buildLeftLyricsColumn(
            context: context,
            localProvider: localProvider,
            downloaderProvider: downloaderProvider,
            song: song,
            palette: palette,
            columnWidth: containerWidth,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2B. HOME 3-LINE LYRICS COLUMN (LEFT)
  // ===========================================================================
  Widget _buildLeftLyricsColumn({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
    required MusEveePalette palette,
    required double columnWidth,
  }) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final columnWidthSnapped =
        NowPlayingView.snapToPhysicalPixel(columnWidth, dpr);

    if (song == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: columnWidthSnapped,
          child: _buildEmptyLibraryColumn(
            context: context,
            localProvider: localProvider,
            palette: palette,
          ),
        ),
      );
    }

    if (song.hasLyrics && !song.isLyricsLoadedInMemory) {
      return SizedBox(
        width: columnWidthSnapped,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: palette.nowPlayingSecondary,
            ),
          ),
        ),
      );
    }

    final lyricsFontPt = localProvider.lyricsFontSize;
    final stagePrefOffset =
        NowPlayingView.computeStageActiveFontPrefOffset(lyricsFontPt);
    final homePrefOffset =
        NowPlayingView.computeHomeActiveFontPrefOffset(lyricsFontPt);
    final homeMinFontSize =
        NowPlayingView.computeHomeActiveMinFontSize(lyricsFontPt);
    final homeSecondaryFontSize = localProvider.secondaryLyricsFontSize;

    // 1. Synced USLT Lyrics Mode (3-line view: previous, active/upcoming, next)
    if (localProvider.lyricsDisplayMode == EmbeddedLyricsDisplayMode.synced &&
        song.hasSyncedLyrics) {
      final entries = localProvider.syncedLyricsFor(song);
      if (entries.isNotEmpty) {
        // Pre-compute and cache final active typography & wrapped slot heights
        // for every line of the song BEFORE any transition starts.
        _ensureSongLyricMetricsCached(
          song: song,
          entries: entries,
          columnWidth: columnWidthSnapped,
          preferredOffset: homePrefOffset,
          minFontSize: homeMinFontSize,
          secondaryFontSize: homeSecondaryFontSize,
          devicePixelRatio: dpr,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final zoneHeight = constraints.maxHeight;

            return AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                localProvider.activeLyricIndexNotifier,
                localProvider.progressNotifier,
                _rowGlideTickVersion,
                _lyricSlideProgress,
              ]),
              builder: (context, _) {
                final rawActiveIdx =
                    NowPlayingView.resolveActiveSyncedLyricIndex(
                  entries,
                  localProvider.positionMs,
                );
                final int effectiveIdx;
                if (localProvider.autoScrollLyrics) {
                  effectiveIdx = rawActiveIdx >= 0
                      ? rawActiveIdx.clamp(0, entries.length - 1)
                      : -1;
                  _frozenLyricIndex = effectiveIdx;
                } else {
                  effectiveIdx = _frozenLyricIndex >= 0
                      ? _frozenLyricIndex.clamp(0, entries.length - 1)
                      : -1;
                }

                final emptySlotMetrics = _cachedEmptySecondarySlotMetrics ??
                    NowPlayingView.measureSecondaryLyricSlot(
                      '',
                      columnWidth: columnWidthSnapped,
                      fontSize: homeSecondaryFontSize,
                      devicePixelRatio: dpr,
                    );

                _syncSharedLineChangeAnimation(
                  song: song,
                  entries: entries,
                  effectiveIdx: effectiveIdx,
                  autoScrollLyrics: localProvider.autoScrollLyrics,
                  currentT: 0.0,
                  containerWidth: columnWidthSnapped,
                  homeWidth: columnWidthSnapped,
                  zoneHeight: zoneHeight,
                  preferredOffset: stagePrefOffset,
                  homePreferredOffset: homePrefOffset,
                  homeMinFontSize: homeMinFontSize,
                  homeSecondaryFontSize: homeSecondaryFontSize,
                  stageScrollDelta: 0.0,
                  dpr: dpr,
                  emptySlotHeight: emptySlotMetrics.slotHeight,
                  isInFluidMorph: false,
                );

                // Section C: Intro stack on Home (`effectiveIdx == -1`, including Demotion `0 -> -1`)
                if (effectiveIdx < 0) {
                  final has0 = entries.isNotEmpty;
                  final has1 = entries.length > 1;
                  final has2 = entries.length > 2;
                  final text0 = has0
                      ? (entries[0].text.trim().isEmpty
                          ? '♪'
                          : entries[0].text.trim())
                      : '';
                  final text1 = has1
                      ? (entries[1].text.trim().isEmpty
                          ? '♪'
                          : entries[1].text.trim())
                      : '';
                  final text2 = has2
                      ? (entries[2].text.trim().isEmpty
                          ? '♪'
                          : entries[2].text.trim())
                      : '';
                  final activeRoleFontSize0 =
                      _cachedActiveLineMetrics[0]?.fontSize ??
                          NowPlayingView.computeActiveLyricFontSize(
                            text0,
                            maxWidth: columnWidthSnapped,
                            preferredOffset: homePrefOffset,
                            minFontSize: homeMinFontSize,
                          );

                  final secLayout0 = has0
                      ? _resolveLineMorphMetricsAndGlide(
                          songPath: song.filePath,
                          centerIdx: 0,
                          lineIndex: 0,
                          rawText: text0,
                          containerWidth: columnWidthSnapped,
                          fontSize: homeSecondaryFontSize,
                          isActiveRole: false,
                          hysteresisMarginPx:
                              NowPlayingView.wrapHysteresisMarginPx,
                          devicePixelRatio: dpr,
                        )
                      : _ResolvedLineRowLayout(
                          metrics: emptySlotMetrics,
                          animatedSlotHeight: emptySlotMetrics.slotHeight,
                          animatedRowTops:
                              _canonicalRowTopsForMetrics(emptySlotMetrics),
                          isGliding: false,
                        );
                  final actLayout0 = has0
                      ? _resolveLineMorphMetricsAndGlide(
                          songPath: song.filePath,
                          centerIdx: 0,
                          lineIndex: 0,
                          rawText: text0,
                          containerWidth: columnWidthSnapped,
                          fontSize: activeRoleFontSize0,
                          isActiveRole: true,
                          hysteresisMarginPx:
                              NowPlayingView.wrapHysteresisMarginPx,
                          devicePixelRatio: dpr,
                          recordAsRenderedState: false,
                        )
                      : secLayout0;
                  final secLayout1 = has1
                      ? _resolveLineMorphMetricsAndGlide(
                          songPath: song.filePath,
                          centerIdx: 0,
                          lineIndex: 1,
                          rawText: text1,
                          containerWidth: columnWidthSnapped,
                          fontSize: homeSecondaryFontSize,
                          isActiveRole: false,
                          hysteresisMarginPx:
                              NowPlayingView.wrapHysteresisMarginPx,
                          devicePixelRatio: dpr,
                        )
                      : _ResolvedLineRowLayout(
                          metrics: emptySlotMetrics,
                          animatedSlotHeight: emptySlotMetrics.slotHeight,
                          animatedRowTops:
                              _canonicalRowTopsForMetrics(emptySlotMetrics),
                          isGliding: false,
                        );
                  final secLayout2 = has2
                      ? _resolveLineMorphMetricsAndGlide(
                          songPath: song.filePath,
                          centerIdx: 0,
                          lineIndex: 2,
                          rawText: text2,
                          containerWidth: columnWidthSnapped,
                          fontSize: homeSecondaryFontSize,
                          isActiveRole: false,
                          hysteresisMarginPx:
                              NowPlayingView.wrapHysteresisMarginPx,
                          devicePixelRatio: dpr,
                        )
                      : _ResolvedLineRowLayout(
                          metrics: emptySlotMetrics,
                          animatedSlotHeight: emptySlotMetrics.slotHeight,
                          animatedRowTops:
                              _canonicalRowTopsForMetrics(emptySlotMetrics),
                          isGliding: false,
                        );

                  final isDemotionStep = _slideAnimatedLyricIndex == -1 &&
                      _lyricSlideController.value < 1.0;
                  final slideT =
                      isDemotionStep ? _lyricSlideProgress.value : 1.0;
                  final snapPositions = !isRowGlideAnimating && !isDemotionStep;

                  final h0 = snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(
                          secLayout0.animatedSlotHeight,
                          dpr,
                        )
                      : secLayout0.animatedSlotHeight;
                  final h1 = snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(
                          secLayout1.animatedSlotHeight,
                          dpr,
                        )
                      : secLayout1.animatedSlotHeight;
                  final h2 = snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(
                          secLayout2.animatedSlotHeight,
                          dpr,
                        )
                      : secLayout2.animatedSlotHeight;

                  final liveSnaps = _resolveInterpolatedLineSnapshots(
                    entries: entries,
                    centerIdx: -1,
                    t: 0.0,
                    u: slideT,
                    containerWidth: columnWidthSnapped,
                    homeWidth: columnWidthSnapped,
                    zoneHeight: zoneHeight,
                    preferredOffset: stagePrefOffset,
                    homePreferredOffset: homePrefOffset,
                    homeMinFontSize: homeMinFontSize,
                    homeSecondaryFontSize: homeSecondaryFontSize,
                    stageScrollDelta: 0.0,
                    dpr: dpr,
                    emptySlotHeight: emptySlotMetrics.slotHeight,
                    resolvedPrevSlotH: h0,
                    resolvedCenterSlotH: h1,
                    resolvedNextSlotH: h2,
                  );

                  const gap = NowPlayingView.lyricSlotVerticalGap;
                  final snap0 = liveSnaps[0]!;
                  final snap1 = liveSnaps[1];
                  final snap2 = liveSnaps[2];

                  final top0 = snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(snap0.top, dpr)
                      : snap0.top;
                  final slotH0 = snapPositions
                      ? NowPlayingView.snapToPhysicalPixel(
                          snap0.slotHeight,
                          dpr,
                        )
                      : snap0.slotHeight;
                  final color0 = Color.lerp(
                        palette.nowPlayingSecondary,
                        palette.nowPlayingPrimary,
                        snap0.colorBlend,
                      ) ??
                      palette.nowPlayingSecondary;

                  CachedLyricLineMetrics metrics0 = secLayout0.metrics;
                  List<double>? rowTops0 = secLayout0.animatedRowTops;
                  double? fontOverride0 =
                      isDemotionStep ? snap0.fontSize : null;
                  if (isDemotionStep &&
                      secLayout0.metrics.wrappedLineCount !=
                          actLayout0.metrics.wrappedLineCount) {
                    metrics0 = snap0.colorBlend >= 0.5
                        ? actLayout0.metrics
                        : secLayout0.metrics;
                    rowTops0 = null;
                    final maxSafeFont0 = slotH0 /
                        (math.max(1, metrics0.wrappedLineCount) *
                            MusEveePalette.lyricLineHeight);
                    fontOverride0 = math.min(snap0.fontSize, maxSafeFont0);
                  }

                  final top1 = snap1 != null
                      ? (snapPositions
                          ? NowPlayingView.snapToPhysicalPixel(snap1.top, dpr)
                          : snap1.top)
                      : (top0 + slotH0 + gap);
                  final slotH1 = snap1 != null
                      ? (snapPositions
                          ? NowPlayingView.snapToPhysicalPixel(
                              snap1.slotHeight,
                              dpr,
                            )
                          : snap1.slotHeight)
                      : h1;
                  final op1 =
                      snap1?.opacity ?? MusEveePalette.homeIntroLine1Opacity;

                  final top2 = snap2 != null
                      ? (snapPositions
                          ? NowPlayingView.snapToPhysicalPixel(snap2.top, dpr)
                          : snap2.top)
                      : (top1 + slotH1 + gap);
                  final slotH2 = snap2 != null
                      ? (snapPositions
                          ? NowPlayingView.snapToPhysicalPixel(
                              snap2.slotHeight,
                              dpr,
                            )
                          : snap2.slotHeight)
                      : h2;
                  final op2 =
                      snap2?.opacity ?? MusEveePalette.homeIntroLine2Opacity;

                  return SizedBox(
                    width: columnWidthSnapped,
                    height: zoneHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showFullLyricsSheet(
                        context: context,
                        localProvider: localProvider,
                        song: song,
                      ),
                      onLongPress: () => _showFullLyricsSheet(
                        context: context,
                        localProvider: localProvider,
                        song: song,
                      ),
                      child: ClipRect(
                        child: SizedBox(
                          width: columnWidthSnapped,
                          height: zoneHeight,
                          child: Transform.translate(
                            key: const ValueKey<String>(
                              'now_playing_three_line_slide_transform',
                            ),
                            offset: Offset.zero,
                            child: SizedBox(
                              width: columnWidthSnapped,
                              height: zoneHeight,
                              child: Stack(
                                key: const ValueKey<String>(
                                  'now_playing_three_line_lyrics',
                                ),
                                clipBehavior: Clip.none,
                                fit: StackFit.expand,
                                children: [
                                  // Top slot: Line 0 in secondary styling (opacity 1.0)
                                  Positioned(
                                    left: 0,
                                    top: top0,
                                    width: columnWidthSnapped,
                                    height: slotH0,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _showFullLyricsSheet(
                                        context: context,
                                        localProvider: localProvider,
                                        song: song,
                                      ),
                                      child: Opacity(
                                        opacity: snap0.opacity.clamp(0.0, 1.0),
                                        child: SizedBox(
                                          key: const ValueKey<String>(
                                            'lyric_slot_previous',
                                          ),
                                          width: columnWidthSnapped,
                                          height: slotH0,
                                          child: _buildLyricRowBlock(
                                            metrics: metrics0,
                                            containerWidth: columnWidthSnapped,
                                            centeringT: 0.0,
                                            textColor: color0,
                                            devicePixelRatio: dpr,
                                            animatedRowTops: rowTops0,
                                            snapRowPositions: snapPositions,
                                            rowKeyPrefix: 'home_lyric_prev',
                                            firstRowTextKey: ValueKey<String>(
                                              'lyric_line_upcoming_0_$text0',
                                            ),
                                            fontSizeOverride: fontOverride0,
                                            slotHeightOverride:
                                                isDemotionStep ? slotH0 : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Middle slot: Line 1 in secondary styling (opacity 0.72)
                                  Positioned(
                                    left: 0,
                                    top: top1,
                                    width: columnWidthSnapped,
                                    height: slotH1,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _showFullLyricsSheet(
                                        context: context,
                                        localProvider: localProvider,
                                        song: song,
                                      ),
                                      child: Opacity(
                                        opacity: op1.clamp(0.0, 1.0),
                                        child: SizedBox(
                                          key: const ValueKey<String>(
                                            'lyric_slot_active',
                                          ),
                                          width: columnWidthSnapped,
                                          height: slotH1,
                                          child: _buildLyricRowBlock(
                                            metrics: secLayout1.metrics,
                                            containerWidth: columnWidthSnapped,
                                            centeringT: 0.0,
                                            textColor:
                                                palette.nowPlayingSecondary,
                                            devicePixelRatio: dpr,
                                            animatedRowTops:
                                                secLayout1.animatedRowTops,
                                            snapRowPositions: snapPositions,
                                            rowKeyPrefix: 'home_lyric_active',
                                            firstRowTextKey: ValueKey<String>(
                                              'lyric_line_upcoming_1_$text1',
                                            ),
                                            fontSizeOverride: isDemotionStep
                                                ? snap1?.fontSize
                                                : null,
                                            slotHeightOverride:
                                                isDemotionStep ? slotH1 : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Bottom slot: Line 2 in secondary styling (opacity 0.48)
                                  Positioned(
                                    left: 0,
                                    top: top2,
                                    width: columnWidthSnapped,
                                    height: slotH2,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _showFullLyricsSheet(
                                        context: context,
                                        localProvider: localProvider,
                                        song: song,
                                      ),
                                      child: Opacity(
                                        opacity: op2.clamp(0.0, 1.0),
                                        child: SizedBox(
                                          key: const ValueKey<String>(
                                            'lyric_slot_next',
                                          ),
                                          width: columnWidthSnapped,
                                          height: slotH2,
                                          child: _buildLyricRowBlock(
                                            metrics: secLayout2.metrics,
                                            containerWidth: columnWidthSnapped,
                                            centeringT: 0.0,
                                            textColor:
                                                palette.nowPlayingSecondary,
                                            devicePixelRatio: dpr,
                                            animatedRowTops:
                                                secLayout2.animatedRowTops,
                                            snapRowPositions: snapPositions,
                                            rowKeyPrefix: 'home_lyric_next',
                                            firstRowTextKey: ValueKey<String>(
                                              'lyric_line_upcoming_2_$text2',
                                            ),
                                            fontSizeOverride: isDemotionStep
                                                ? snap2?.fontSize
                                                : null,
                                            slotHeightOverride:
                                                isDemotionStep ? slotH2 : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final centerIdx = effectiveIdx;
                const isCenterActive = true;
                final prevIdx = centerIdx - 1;
                final nextIdx = centerIdx + 1;
                final hasPrev = prevIdx >= 0;
                final hasNext = nextIdx < entries.length;

                final prevEntry = hasPrev ? entries[prevIdx] : null;
                final activeEntry = entries[centerIdx];
                final nextEntry = hasNext ? entries[nextIdx] : null;

                final prevText = prevEntry == null
                    ? ''
                    : (prevEntry.text.trim().isEmpty
                        ? '♪'
                        : prevEntry.text.trim());
                final activeText = activeEntry.text.trim().isEmpty
                    ? '♪'
                    : activeEntry.text.trim();
                final nextText = nextEntry == null
                    ? ''
                    : (nextEntry.text.trim().isEmpty
                        ? '♪'
                        : nextEntry.text.trim());

                final activeRoleFontSize =
                    _cachedActiveLineMetrics[centerIdx]?.fontSize ??
                        NowPlayingView.computeActiveLyricFontSize(
                          activeText,
                          maxWidth: columnWidthSnapped,
                          preferredOffset: homePrefOffset,
                          minFontSize: homeMinFontSize,
                        );

                final prevLayout = hasPrev
                    ? _resolveLineMorphMetricsAndGlide(
                        songPath: song.filePath,
                        centerIdx: centerIdx,
                        lineIndex: prevIdx,
                        rawText: prevText,
                        containerWidth: columnWidthSnapped,
                        fontSize: homeSecondaryFontSize,
                        isActiveRole: false,
                        hysteresisMarginPx:
                            NowPlayingView.wrapHysteresisMarginPx,
                        devicePixelRatio: dpr,
                      )
                    : _ResolvedLineRowLayout(
                        metrics: emptySlotMetrics,
                        animatedSlotHeight: emptySlotMetrics.slotHeight,
                        animatedRowTops: _canonicalRowTopsForMetrics(
                          emptySlotMetrics,
                        ),
                        isGliding: false,
                      );
                final centerActiveRoleLayout = _resolveLineMorphMetricsAndGlide(
                  songPath: song.filePath,
                  centerIdx: centerIdx,
                  lineIndex: centerIdx,
                  rawText: activeText,
                  containerWidth: columnWidthSnapped,
                  fontSize: activeRoleFontSize,
                  isActiveRole: true,
                  hysteresisMarginPx: NowPlayingView.wrapHysteresisMarginPx,
                  devicePixelRatio: dpr,
                  recordAsRenderedState: isCenterActive,
                );
                final centerRenderLayout = centerActiveRoleLayout;
                final nextLayout = hasNext
                    ? _resolveLineMorphMetricsAndGlide(
                        songPath: song.filePath,
                        centerIdx: centerIdx,
                        lineIndex: nextIdx,
                        rawText: nextText,
                        containerWidth: columnWidthSnapped,
                        fontSize: homeSecondaryFontSize,
                        isActiveRole: false,
                        hysteresisMarginPx:
                            NowPlayingView.wrapHysteresisMarginPx,
                        devicePixelRatio: dpr,
                      )
                    : _ResolvedLineRowLayout(
                        metrics: emptySlotMetrics,
                        animatedSlotHeight: emptySlotMetrics.slotHeight,
                        animatedRowTops: _canonicalRowTopsForMetrics(
                          emptySlotMetrics,
                        ),
                        isGliding: false,
                      );
                final outgoingTopMetrics = (_outgoingTopLyricIndex >= 0 &&
                        _cachedSecondaryLineMetrics
                            .containsKey(_outgoingTopLyricIndex))
                    ? _cachedSecondaryLineMetrics[_outgoingTopLyricIndex]!
                    : emptySlotMetrics;

                final isAnimatingStep = isCenterActive &&
                    _slideAnimatedLyricIndex == effectiveIdx &&
                    _lyricSlideController.value < 1.0;
                final slideT =
                    isAnimatingStep ? _lyricSlideProgress.value : 1.0;
                final useMorphHandoverSlide =
                    isAnimatingStep && _slideInterpolateRoleSize;

                final snapPositions =
                    !isRowGlideAnimating && !useMorphHandoverSlide;
                final basePrevSlotH = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(
                        prevLayout.animatedSlotHeight,
                        dpr,
                      )
                    : prevLayout.animatedSlotHeight;
                final baseCenterSlotH = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(
                        centerActiveRoleLayout.animatedSlotHeight,
                        dpr,
                      )
                    : centerActiveRoleLayout.animatedSlotHeight;
                final baseNextSlotH = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(
                        nextLayout.animatedSlotHeight,
                        dpr,
                      )
                    : nextLayout.animatedSlotHeight;

                final liveSnaps = _resolveInterpolatedLineSnapshots(
                  entries: entries,
                  centerIdx: centerIdx,
                  t: 0.0,
                  u: slideT,
                  containerWidth: columnWidthSnapped,
                  homeWidth: columnWidthSnapped,
                  zoneHeight: zoneHeight,
                  preferredOffset: stagePrefOffset,
                  homePreferredOffset: homePrefOffset,
                  homeMinFontSize: homeMinFontSize,
                  homeSecondaryFontSize: homeSecondaryFontSize,
                  stageScrollDelta: 0.0,
                  dpr: dpr,
                  emptySlotHeight: emptySlotMetrics.slotHeight,
                  resolvedPrevSlotH: basePrevSlotH,
                  resolvedCenterSlotH: baseCenterSlotH,
                  resolvedNextSlotH: baseNextSlotH,
                );

                const gap = NowPlayingView.lyricSlotVerticalGap;
                final restHomeCenterTop = NowPlayingView.snapToPhysicalPixel(
                  (zoneHeight -
                          baseCenterSlotH +
                          basePrevSlotH -
                          baseNextSlotH) /
                      2.0,
                  dpr,
                );
                final restPrevTop = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(
                        restHomeCenterTop - gap - basePrevSlotH,
                        dpr,
                      )
                    : (restHomeCenterTop - gap - basePrevSlotH);
                final restNextTop = snapPositions
                    ? NowPlayingView.snapToPhysicalPixel(
                        restHomeCenterTop + baseCenterSlotH + gap,
                        dpr,
                      )
                    : (restHomeCenterTop + baseCenterSlotH + gap);

                final prevSnap = hasPrev ? liveSnaps[prevIdx] : null;
                final centerSnap = liveSnaps[centerIdx];
                final nextSnap = hasNext ? liveSnaps[nextIdx] : null;
                final outSnap = _outgoingTopLyricIndex >= 0
                    ? liveSnaps[_outgoingTopLyricIndex]
                    : null;

                final prevTop = (useMorphHandoverSlide && prevSnap != null)
                    ? prevSnap.top
                    : restPrevTop;
                final prevSlotH = (useMorphHandoverSlide && prevSnap != null)
                    ? prevSnap.slotHeight
                    : basePrevSlotH;
                final prevFontSizeOverride =
                    (useMorphHandoverSlide && prevSnap != null)
                        ? prevSnap.fontSize
                        : null;

                final homeCenterTop =
                    (useMorphHandoverSlide && centerSnap != null)
                        ? centerSnap.top
                        : restHomeCenterTop;
                final centerSlotH =
                    (useMorphHandoverSlide && centerSnap != null)
                        ? centerSnap.slotHeight
                        : baseCenterSlotH;
                final centerFontSizeOverride =
                    (useMorphHandoverSlide && centerSnap != null)
                        ? centerSnap.fontSize
                        : null;
                final centerMetricsToRender = centerRenderLayout.metrics;
                final centerRowTopsToRender =
                    centerRenderLayout.animatedRowTops;

                final nextTop = (useMorphHandoverSlide && nextSnap != null)
                    ? nextSnap.top
                    : restNextTop;
                final nextSlotH = (useMorphHandoverSlide && nextSnap != null)
                    ? nextSnap.slotHeight
                    : baseNextSlotH;
                final nextFontSizeOverride =
                    (useMorphHandoverSlide && nextSnap != null)
                        ? nextSnap.fontSize
                        : null;

                final dyShift =
                    useMorphHandoverSlide ? 0.0 : ((1.0 - slideT) * 28.0);

                final prevColor = isAnimatingStep
                    ? (Color.lerp(
                          palette.nowPlayingPrimary,
                          palette.nowPlayingSecondary,
                          slideT,
                        ) ??
                        palette.nowPlayingSecondary)
                    : palette.nowPlayingSecondary;

                final activeColor = isAnimatingStep
                    ? (Color.lerp(
                          palette.nowPlayingSecondary,
                          palette.nowPlayingPrimary,
                          slideT,
                        ) ??
                        palette.nowPlayingPrimary)
                    : palette.nowPlayingPrimary;
                final activeOpacity = useMorphHandoverSlide
                    ? (centerSnap?.opacity ?? 1.0)
                    : (isAnimatingStep ? (0.78 + 0.22 * slideT) : 1.0);
                final nextOpacity = useMorphHandoverSlide
                    ? (nextSnap?.opacity ?? 1.0)
                    : (isAnimatingStep ? (0.18 + 0.82 * slideT) : 1.0);

                final hasPromotionOutgoingBottom = useMorphHandoverSlide &&
                    _slideFromCenterIdx == -1 &&
                    centerIdx == 0 &&
                    entries.length > 2 &&
                    liveSnaps.containsKey(2);
                final outBotSnap =
                    hasPromotionOutgoingBottom ? liveSnaps[2] : null;
                final outBotMetrics = hasPromotionOutgoingBottom
                    ? (_cachedSecondaryLineMetrics[2] ?? emptySlotMetrics)
                    : emptySlotMetrics;

                return SizedBox(
                  width: columnWidthSnapped,
                  height: zoneHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showFullLyricsSheet(
                      context: context,
                      localProvider: localProvider,
                      song: song,
                    ),
                    onLongPress: () => _showFullLyricsSheet(
                      context: context,
                      localProvider: localProvider,
                      song: song,
                    ),
                    child: ClipRect(
                      child: SizedBox(
                        width: columnWidthSnapped,
                        height: zoneHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          fit: StackFit.expand,
                          children: [
                            if (isAnimatingStep &&
                                _outgoingTopLyricText.isNotEmpty)
                              Positioned(
                                left: 0,
                                width: columnWidthSnapped,
                                top: (useMorphHandoverSlide && outSnap != null)
                                    ? outSnap.top
                                    : (prevTop -
                                        gap -
                                        outgoingTopMetrics.slotHeight),
                                height:
                                    (useMorphHandoverSlide && outSnap != null)
                                        ? outSnap.slotHeight
                                        : outgoingTopMetrics.slotHeight,
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: (useMorphHandoverSlide &&
                                            outSnap != null)
                                        ? outSnap.opacity.clamp(0.0, 1.0)
                                        : (1.0 - slideT * 1.35).clamp(0.0, 1.0),
                                    child: Transform.translate(
                                      offset: Offset(
                                        0.0,
                                        useMorphHandoverSlide
                                            ? 0.0
                                            : (-28.0 * slideT),
                                      ),
                                      child: _buildLyricRowBlock(
                                        metrics: outgoingTopMetrics,
                                        containerWidth: columnWidthSnapped,
                                        centeringT: 0.0,
                                        textColor: palette.nowPlayingSecondary,
                                        devicePixelRatio: dpr,
                                        snapRowPositions: snapPositions,
                                        fontSizeOverride:
                                            (useMorphHandoverSlide &&
                                                    outSnap != null)
                                                ? outSnap.fontSize
                                                : null,
                                        slotHeightOverride:
                                            (useMorphHandoverSlide &&
                                                    outSnap != null)
                                                ? outSnap.slotHeight
                                                : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (hasPromotionOutgoingBottom &&
                                outBotSnap != null)
                              Positioned(
                                key: const ValueKey<String>(
                                  'lyric_slot_outgoing_intro_2',
                                ),
                                left: 0,
                                width: columnWidthSnapped,
                                top: outBotSnap.top,
                                height: outBotSnap.slotHeight,
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: outBotSnap.opacity.clamp(0.0, 1.0),
                                    child: _buildLyricRowBlock(
                                      metrics: outBotMetrics,
                                      containerWidth: columnWidthSnapped,
                                      centeringT: 0.0,
                                      textColor: palette.nowPlayingSecondary,
                                      devicePixelRatio: dpr,
                                      snapRowPositions: snapPositions,
                                      fontSizeOverride: outBotSnap.fontSize,
                                      slotHeightOverride: outBotSnap.slotHeight,
                                    ),
                                  ),
                                ),
                              ),
                            Transform.translate(
                              key: const ValueKey<String>(
                                'now_playing_three_line_slide_transform',
                              ),
                              offset: Offset(0.0, dyShift),
                              child: SizedBox(
                                width: columnWidthSnapped,
                                height: zoneHeight,
                                child: Stack(
                                  key: const ValueKey<String>(
                                    'now_playing_three_line_lyrics',
                                  ),
                                  clipBehavior: Clip.none,
                                  fit: StackFit.expand,
                                  children: [
                                    // Previous line slot (always reserves slotHeight & columnWidth even when empty)
                                    Positioned(
                                      left: 0,
                                      top: prevTop,
                                      width: columnWidthSnapped,
                                      height: prevSlotH,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _showFullLyricsSheet(
                                          context: context,
                                          localProvider: localProvider,
                                          song: song,
                                        ),
                                        child: SizedBox(
                                          key: const ValueKey<String>(
                                            'lyric_slot_previous',
                                          ),
                                          width: columnWidthSnapped,
                                          height: prevSlotH,
                                          child: _buildLyricRowBlock(
                                            metrics: prevLayout.metrics,
                                            containerWidth: columnWidthSnapped,
                                            centeringT: 0.0,
                                            textColor: prevColor,
                                            devicePixelRatio: dpr,
                                            animatedRowTops:
                                                prevLayout.animatedRowTops,
                                            snapRowPositions: snapPositions,
                                            rowKeyPrefix: 'home_lyric_prev',
                                            firstRowTextKey:
                                                const ValueKey<String>(
                                              'lyric_line_previous',
                                            ),
                                            fontSizeOverride:
                                                prevFontSizeOverride,
                                            slotHeightOverride:
                                                useMorphHandoverSlide
                                                    ? prevSlotH
                                                    : null,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Active line slot (locked to final active slotHeight from first frame)
                                    Positioned(
                                      left: 0,
                                      top: homeCenterTop,
                                      width: columnWidthSnapped,
                                      height: centerSlotH,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _showFullLyricsSheet(
                                          context: context,
                                          localProvider: localProvider,
                                          song: song,
                                        ),
                                        child: Opacity(
                                          opacity: activeOpacity,
                                          child: SizedBox(
                                            key: const ValueKey<String>(
                                              'lyric_slot_active',
                                            ),
                                            width: columnWidthSnapped,
                                            height: centerSlotH,
                                            child: _buildLyricRowBlock(
                                              metrics: centerMetricsToRender,
                                              containerWidth:
                                                  columnWidthSnapped,
                                              centeringT: 0.0,
                                              textColor: activeColor,
                                              devicePixelRatio: dpr,
                                              animatedRowTops:
                                                  centerRowTopsToRender,
                                              snapRowPositions: snapPositions,
                                              rowKeyPrefix: 'home_lyric_active',
                                              firstRowTextKey: ValueKey<String>(
                                                'lyric_line_active_${effectiveIdx}_$activeText',
                                              ),
                                              fontSizeOverride:
                                                  centerFontSizeOverride,
                                              slotHeightOverride:
                                                  useMorphHandoverSlide
                                                      ? centerSlotH
                                                      : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Next line slot (always reserves slotHeight & columnWidth even when empty)
                                    Positioned(
                                      left: 0,
                                      top: nextTop,
                                      width: columnWidthSnapped,
                                      height: nextSlotH,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _showFullLyricsSheet(
                                          context: context,
                                          localProvider: localProvider,
                                          song: song,
                                        ),
                                        child: Opacity(
                                          opacity: nextOpacity,
                                          child: SizedBox(
                                            key: const ValueKey<String>(
                                              'lyric_slot_next',
                                            ),
                                            width: columnWidthSnapped,
                                            height: nextSlotH,
                                            child: _buildLyricRowBlock(
                                              metrics: nextLayout.metrics,
                                              containerWidth:
                                                  columnWidthSnapped,
                                              centeringT: 0.0,
                                              textColor:
                                                  palette.nowPlayingSecondary,
                                              devicePixelRatio: dpr,
                                              animatedRowTops:
                                                  nextLayout.animatedRowTops,
                                              snapRowPositions: snapPositions,
                                              rowKeyPrefix: 'home_lyric_next',
                                              firstRowTextKey:
                                                  const ValueKey<String>(
                                                'lyric_line_next',
                                              ),
                                              fontSizeOverride:
                                                  nextFontSizeOverride,
                                              slotHeightOverride:
                                                  useMorphHandoverSlide
                                                      ? nextSlotH
                                                      : null,
                                            ),
                                          ),
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
                  ),
                );
              },
            );
          },
        );
      }
    }

    // 2. Plain (untimed) USLT Lyrics Mode — Section D: permanent Section C intro stack
    // (first 3 lines in top / middle / bottom slots, all secondary 13.5pt with 1.0 / 0.72 / 0.48 opacity)
    if (song.hasLyrics) {
      final nonEmpty = localProvider
          .plainLyricLinesFor(song)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (nonEmpty.isNotEmpty) {
        final line0 = nonEmpty[0];
        final line1 = nonEmpty.length > 1 ? nonEmpty[1] : '';
        final line2 = nonEmpty.length > 2 ? nonEmpty[2] : '';

        final m0 = NowPlayingView.measureSecondaryLyricSlot(
          line0,
          columnWidth: columnWidthSnapped,
          fontSize: homeSecondaryFontSize,
          devicePixelRatio: dpr,
        );
        final m1 = NowPlayingView.measureSecondaryLyricSlot(
          line1,
          columnWidth: columnWidthSnapped,
          fontSize: homeSecondaryFontSize,
          devicePixelRatio: dpr,
        );
        final m2 = NowPlayingView.measureSecondaryLyricSlot(
          line2,
          columnWidth: columnWidthSnapped,
          fontSize: homeSecondaryFontSize,
          devicePixelRatio: dpr,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final zoneHeight = constraints.maxHeight;
            const gap = NowPlayingView.lyricSlotVerticalGap;
            final h0 = m0.slotHeight;
            final h1 = m1.slotHeight;
            final h2 = m2.slotHeight;
            final homeMidTop = NowPlayingView.snapToPhysicalPixel(
              (zoneHeight - h1 + h0 - h2) / 2.0,
              dpr,
            );
            final homeTopTop = NowPlayingView.snapToPhysicalPixel(
              homeMidTop - gap - h0,
              dpr,
            );
            final homeBotTop = NowPlayingView.snapToPhysicalPixel(
              homeMidTop + h1 + gap,
              dpr,
            );

            return SizedBox(
              width: columnWidthSnapped,
              height: zoneHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showFullLyricsSheet(
                  context: context,
                  localProvider: localProvider,
                  song: song,
                ),
                onLongPress: () => _showFullLyricsSheet(
                  context: context,
                  localProvider: localProvider,
                  song: song,
                ),
                child: ClipRect(
                  child: SizedBox(
                    key: const ValueKey<String>(
                      'now_playing_plain_lyrics_column',
                    ),
                    width: columnWidthSnapped,
                    height: zoneHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          left: 0,
                          top: homeTopTop,
                          width: columnWidthSnapped,
                          height: h0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showFullLyricsSheet(
                              context: context,
                              localProvider: localProvider,
                              song: song,
                            ),
                            child: Opacity(
                              opacity: MusEveePalette.homeIntroLine0Opacity,
                              child: SizedBox(
                                key: const ValueKey<String>(
                                  'lyric_slot_previous',
                                ),
                                width: columnWidthSnapped,
                                height: h0,
                                child: _buildLyricRowBlock(
                                  metrics: m0,
                                  containerWidth: columnWidthSnapped,
                                  centeringT: 0.0,
                                  textColor: palette.nowPlayingSecondary,
                                  devicePixelRatio: dpr,
                                  snapRowPositions: true,
                                  rowKeyPrefix: 'home_lyric_prev',
                                  firstRowTextKey: ValueKey<String>(
                                    'lyric_line_upcoming_0_$line0',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: homeMidTop,
                          width: columnWidthSnapped,
                          height: h1,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showFullLyricsSheet(
                              context: context,
                              localProvider: localProvider,
                              song: song,
                            ),
                            child: Opacity(
                              opacity: MusEveePalette.homeIntroLine1Opacity,
                              child: SizedBox(
                                key: const ValueKey<String>(
                                  'lyric_slot_active',
                                ),
                                width: columnWidthSnapped,
                                height: h1,
                                child: _buildLyricRowBlock(
                                  metrics: m1,
                                  containerWidth: columnWidthSnapped,
                                  centeringT: 0.0,
                                  textColor: palette.nowPlayingSecondary,
                                  devicePixelRatio: dpr,
                                  snapRowPositions: true,
                                  rowKeyPrefix: 'home_lyric_active',
                                  firstRowTextKey: ValueKey<String>(
                                    'lyric_line_upcoming_1_$line1',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: homeBotTop,
                          width: columnWidthSnapped,
                          height: h2,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _showFullLyricsSheet(
                              context: context,
                              localProvider: localProvider,
                              song: song,
                            ),
                            child: Opacity(
                              opacity: MusEveePalette.homeIntroLine2Opacity,
                              child: SizedBox(
                                key: const ValueKey<String>(
                                  'lyric_slot_next',
                                ),
                                width: columnWidthSnapped,
                                height: h2,
                                child: _buildLyricRowBlock(
                                  metrics: m2,
                                  containerWidth: columnWidthSnapped,
                                  centeringT: 0.0,
                                  textColor: palette.nowPlayingSecondary,
                                  devicePixelRatio: dpr,
                                  snapRowPositions: true,
                                  rowKeyPrefix: 'home_lyric_next',
                                  firstRowTextKey: ValueKey<String>(
                                    'lyric_line_upcoming_2_$line2',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }
    }

    // 3. No USLT Lyrics Yet — small pale text in left column; tapping opens Search LRCLIB / Enter Manually
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: columnWidthSnapped,
        child: GestureDetector(
          key: const ValueKey<String>('now_playing_no_lyrics_prompt'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _showNoLyricsActionSheet(
            context: context,
            localProvider: localProvider,
            downloaderProvider: downloaderProvider,
            song: song,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.tr(
                    'Belum ada lirik tertanam pada file ${song.audioFormatLabel} ini.',
                    'No embedded lyrics in this ${song.audioFormatLabel} file yet.',
                    context,
                  ),
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: palette.nowPlayingSecondary,
                    fontSize: MusEveePalette.lyricSecondaryFontSize,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.tr(
                    'Ketuk untuk Cari Lirik LRCLIB atau Isi Manual',
                    'Tap to Search LRCLIB Lyrics or Enter Manually',
                    context,
                  ),
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: palette.nowPlayingPrimary.withValues(alpha: 0.72),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLibraryColumn({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required MusEveePalette palette,
  }) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.tr(
              'Belum ada lagu yang sedang diputar',
              'No song is currently playing',
              context,
            ),
            textAlign: TextAlign.left,
            style: TextStyle(
              color: palette.nowPlayingPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            localProvider.isLoadingLibrary
                ? AppStrings.tr(
                    'Memindai folder musik di perangkat...',
                    'Scanning music folders on device...',
                    context,
                  )
                : AppStrings.tr(
                    'Pilih lagu dari tab Folders atau unduh lagu baru di tab Downloader.',
                    'Pick a song from Folders or download new tracks in Downloader.',
                    context,
                  ),
            textAlign: TextAlign.left,
            style: TextStyle(
              color: palette.nowPlayingSecondary,
              fontSize: 13.0,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.nowPlayingPrimary,
                  side: BorderSide(color: palette.hairline, width: 0.8),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: widget.onNavigateToFolders,
                child: Text(
                  AppStrings.tr('Buka Folder', 'Open Folder', context),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.nowPlayingPrimary,
                  foregroundColor: palette.nowPlayingOnPrimary,
                  elevation: 0,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: widget.onNavigateToDownloader,
                child: Text(
                  AppStrings.tr(
                    'Cari & Unduh Lagu',
                    'Search & Download',
                    context,
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedTrackDisc({
    required LocalMusicProvider localProvider,
    required LocalSong? song,
    required MusEveePalette palette,
    required double discDiameter,
    bool slideInOnTrackChange = true,
  }) {
    final holeDiameter = discDiameter * MusEveePalette.discCenterHoleFactor;

    return AnimatedSwitcher(
      duration: const Duration(
        milliseconds: MusEveePalette.discTrackChangeDurationMs,
      ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        if (!slideInOnTrackChange) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        }
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.18, 0.0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<String>(song?.filePath ?? '__empty_disc__'),
        width: discDiameter,
        height: discDiameter,
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.nowPlayingBg,
          border: Border.all(
            color: palette.discRingBorder,
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: palette.discShadow,
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(-2, 6),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // Rotating Cover Art inside ClipOval + RepaintBoundary
            ClipOval(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _discAngleRad,
                  builder: (context, angleRad, child) {
                    return Transform.rotate(
                      angle: angleRad,
                      child: child,
                    );
                  },
                  child: _buildDiscCoverArt(localProvider, song, palette),
                ),
              ),
            ),

            // Stationary center hole (matches reference vinyl/CD center cutout)
            Center(
              child: IgnorePointer(
                child: Container(
                  width: holeDiameter,
                  height: holeDiameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.nowPlayingBg,
                    border: Border.all(
                      color: palette.discRingBorder.withValues(alpha: 0.75),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscCoverArt(
    LocalMusicProvider localProvider,
    LocalSong? song,
    MusEveePalette palette,
  ) {
    if (song == null) {
      return _buildDefaultDiscSurface(palette);
    }

    final fullBytes = localProvider.currentFullCoverBytes;
    if (fullBytes != null && fullBytes.isNotEmpty) {
      return Image.memory(
        fullBytes,
        fit: BoxFit.cover,
        cacheWidth: 960,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildThumbnailOrDefaultDiscArt(song, palette),
      );
    }
    return _buildThumbnailOrDefaultDiscArt(song, palette);
  }

  Widget _buildThumbnailOrDefaultDiscArt(
    LocalSong song,
    MusEveePalette palette,
  ) {
    if (song.hasCover) {
      return Image.file(
        File(song.coverFilePath!),
        fit: BoxFit.cover,
        cacheWidth: 960,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _buildDefaultDiscSurface(palette),
      );
    }
    return _buildDefaultDiscSurface(palette);
  }

  Widget _buildDefaultDiscSurface(MusEveePalette palette) {
    return Container(
      color: palette.surfaceSubtle,
      alignment: Alignment.center,
      child: Align(
        alignment: const Alignment(-0.45, 0.0),
        child: Icon(
          Icons.music_note_rounded,
          size: 48,
          color: palette.nowPlayingSecondary.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. SONG INFO (CENTERED TITLE IN BOLD BLACK + ARTIST IN GRAY)
  // ===========================================================================
  Widget _buildSongInfoSection({
    required LocalSong? song,
    required MusEveePalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: Column(
          key: ValueKey<String>(song?.filePath ?? '__empty_info__'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              song?.title ?? 'MusEvee Player',
              key: const ValueKey<String>('now_playing_song_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.nowPlayingPrimary,
                fontSize: MusEveePalette.songTitleFontSize,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              song?.artist ??
                  AppStrings.tr(
                    'Pilih atau unduh lagu untuk mulai memutar',
                    'Pick or download a song to start playing',
                    context,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.nowPlayingArtist,
                fontSize: MusEveePalette.songArtistFontSize,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. THIN SEEKBAR (2.5 PX LINE, TIMESTAMPS BELOW ENDS)
  // ===========================================================================
  Widget _buildSeekbarSection({
    required LocalMusicProvider localProvider,
    required LocalSong? song,
    required MusEveePalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ValueListenableBuilder<PlaybackProgress>(
        valueListenable: localProvider.progressNotifier,
        builder: (context, progress, _) {
          final rawTotal = progress.durationMs > 0
              ? progress.durationMs
              : localProvider.durationMs;
          final totalMs = rawTotal > 0 ? rawTotal : 1;
          final currentMs = (_dragSeekMs ?? progress.positionMs.toDouble())
              .clamp(0.0, totalMs.toDouble());

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 22,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: MusEveePalette.seekbarTrackHeight,
                    trackShape: const _FullWidthSeekbarTrackShape(),
                    activeTrackColor: palette.nowPlayingPrimary,
                    inactiveTrackColor: palette.seekbarInactive,
                    thumbColor: palette.nowPlayingPrimary,
                    overlayColor:
                        palette.nowPlayingPrimary.withValues(alpha: 0.10),
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: _dragSeekMs != null ? 5.0 : 0.0,
                      disabledThumbRadius: 0.0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 11,
                    ),
                  ),
                  // Isolate Slider's semantic boundary from ancestor IndexedStack
                  // geometry walks when NowPlayingView updates while offstage.
                  child: Semantics(
                    container: true,
                    child: Slider(
                      min: 0.0,
                      max: totalMs.toDouble(),
                      value: song == null ? 0.0 : currentMs,
                      onChangeStart: song == null
                          ? null
                          : (val) {
                              setState(() => _dragSeekMs = val);
                            },
                      onChanged: song == null
                          ? null
                          : (val) {
                              setState(() => _dragSeekMs = val);
                            },
                      onChangeEnd: song == null
                          ? null
                          : (val) {
                              _seekFromUserGesture(localProvider, val.round());
                              setState(() => _dragSeekMs = null);
                            },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatSeekbarTime(currentMs.round()),
                    style: TextStyle(
                      color: palette.nowPlayingSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    song != null ? _formatSeekbarTime(rawTotal) : '00:00',
                    style: TextStyle(
                      color: palette.nowPlayingSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _formatSeekbarTime(int millis) {
    if (millis <= 0) return '00:00';
    final totalSeconds = (millis / 1000).floor();
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  // ===========================================================================
  // 5. TRANSPORT ROW (ONLY 5 ELEMENTS: SHUFFLE, PREV, PLAY/PAUSE, NEXT, REPEAT)
  // ===========================================================================
  Widget _buildTransportRow({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required LocalSong? song,
    required MusEveePalette palette,
  }) {
    final isShuffle = localProvider.isShuffle;
    final playMode = localProvider.playMode;
    final isPlayModeActive = playMode != MusicoletPlayMode.playQueueOnce;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1. Shuffle (left)
            _buildTransportSideButton(
              key: const ValueKey<String>('transport_shuffle_button'),
              tooltip: isShuffle
                  ? AppStrings.tr('Shuffle Aktif', 'Shuffle On', context)
                  : AppStrings.tr('Shuffle Nonaktif', 'Shuffle Off', context),
              isActive: isShuffle,
              palette: palette,
              tapRotationRad: 0.20,
              onTap: localProvider.toggleShuffle,
              child: MographStatePop(
                stateKey: isShuffle,
                scaleBoost: 0.22,
                rotationKickRad: -0.36,
                child: Image.asset(
                  'assets/icons/arrow.png',
                  width: 22,
                  height: 22,
                  fit: BoxFit.contain,
                  color: isShuffle
                      ? palette.nowPlayingPrimary
                      : palette.nowPlayingInactiveIcon,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),

            // 2. Previous (center-left — mirrored `assets/icons/play.png`, ~26px glyph, >=48x48 touch target)
            Tooltip(
              message: AppStrings.tr(
                'Lagu Sebelumnya',
                'Previous Track',
                context,
              ),
              child: MographSpringTap(
                pressedScale: 0.82,
                tapOffsetKick: const Offset(-5.5, 0.0),
                enabled: song != null,
                child: InkWell(
                  key: const ValueKey<String>('transport_prev_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap:
                      song == null ? null : () => localProvider.playPrevious(),
                  child: SizedBox(
                    width: MusEveePalette.minTouchTargetSize,
                    height: MusEveePalette.minTouchTargetSize,
                    child: Padding(
                      padding: const EdgeInsets.all(11.0),
                      child: Center(
                        child: Transform.scale(
                          scaleX: -1,
                          child: Image.asset(
                            'assets/icons/play.png',
                            width: MusEveePalette.prevNextIconSize,
                            height: MusEveePalette.prevNextIconSize,
                            fit: BoxFit.contain,
                            color: song == null
                                ? palette.nowPlayingInactiveIcon
                                : palette.nowPlayingPrimary,
                            colorBlendMode: BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Play / Pause (center — 56px solid circle with ~26px white/onPrimary icon)
            Tooltip(
              message: localProvider.isPlaying
                  ? AppStrings.tr('Jeda', 'Pause', context)
                  : AppStrings.tr('Putar', 'Play', context),
              child: MographSpringTap(
                pressedScale: 0.84,
                child: InkWell(
                  key: const ValueKey<String>('transport_play_pause_button'),
                  customBorder: const CircleBorder(),
                  onTap: localProvider.allSongs.isEmpty && song == null
                      ? widget.onNavigateToDownloader
                      : () => localProvider.togglePlayPause(),
                  child: MographStatePop(
                    stateKey: localProvider.isPlaying,
                    scaleBoost: 0.16,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      width: MusEveePalette.playPauseButtonSize,
                      height: MusEveePalette.playPauseButtonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.nowPlayingPrimary,
                      ),
                      alignment: Alignment.center,
                      child: MographAnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        reverseDuration: const Duration(milliseconds: 120),
                        beginScale: 0.62,
                        rotationTurns: -0.14,
                        child: Icon(
                          localProvider.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(localProvider.isPlaying),
                          size: MusEveePalette.playPauseIconSize,
                          color: palette.nowPlayingOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. Next (center-right — `assets/icons/play.png`, ~26px glyph, >=48x48 touch target)
            Tooltip(
              message: AppStrings.tr(
                'Lagu Berikutnya',
                'Next Track',
                context,
              ),
              child: MographSpringTap(
                pressedScale: 0.82,
                tapOffsetKick: const Offset(5.5, 0.0),
                enabled: song != null,
                child: InkWell(
                  key: const ValueKey<String>('transport_next_button'),
                  borderRadius: BorderRadius.circular(24),
                  onTap: song == null ? null : () => localProvider.playNext(),
                  child: SizedBox(
                    width: MusEveePalette.minTouchTargetSize,
                    height: MusEveePalette.minTouchTargetSize,
                    child: Padding(
                      padding: const EdgeInsets.all(11.0),
                      child: Center(
                        child: Image.asset(
                          'assets/icons/play.png',
                          width: MusEveePalette.prevNextIconSize,
                          height: MusEveePalette.prevNextIconSize,
                          fit: BoxFit.contain,
                          color: song == null
                              ? palette.nowPlayingInactiveIcon
                              : palette.nowPlayingPrimary,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 5. Repeat / Play Mode (right — `assets/icons/repeat.png`)
            _buildTransportSideButton(
              key: const ValueKey<String>('transport_play_mode_button'),
              tooltip: _playModeTooltip(playMode, context),
              isActive: isPlayModeActive,
              palette: palette,
              tapRotationRad: 0.18,
              onTap: localProvider.cyclePlayMode,
              child: MographStatePop(
                stateKey: playMode,
                scaleBoost: 0.20,
                rotationKickRad: -0.45,
                child: MographAnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 120),
                  beginScale: 0.72,
                  rotationTurns: -0.12,
                  child: KeyedSubtree(
                    key: ValueKey<MusicoletPlayMode>(playMode),
                    child: _buildPlayModeIcon(playMode, palette),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportSideButton({
    required Key key,
    required String tooltip,
    required bool isActive,
    required MusEveePalette palette,
    double tapRotationRad = 0.0,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Tooltip(
      message: tooltip,
      child: MographSpringTap(
        pressedScale: 0.82,
        tapRotationRad: tapRotationRad,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: SizedBox(
            width: MusEveePalette.minTouchTargetSize,
            height: MusEveePalette.minTouchTargetSize,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                child,
                const SizedBox(height: 3),
                AnimatedScale(
                  scale: isActive ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 240),
                  curve: isActive ? Curves.easeOutBack : Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? palette.nowPlayingPrimary
                          : Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayModeIcon(
    MusicoletPlayMode mode,
    MusEveePalette palette,
  ) {
    final isActive = mode != MusicoletPlayMode.playQueueOnce;
    final tint =
        isActive ? palette.nowPlayingPrimary : palette.nowPlayingInactiveIcon;

    if (mode == MusicoletPlayMode.playSingleStop) {
      return SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: Text(
            '1→',
            style: TextStyle(
              color: tint,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
      );
    }

    final baseRepeat = Image.asset(
      'assets/icons/repeat.png',
      width: 22,
      height: 22,
      fit: BoxFit.contain,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );

    if (mode == MusicoletPlayMode.repeatOne) {
      return SizedBox(
        width: 24,
        height: 22,
        child: Stack(
          alignment: Alignment.center,
          children: [
            baseRepeat,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2.2),
              color: palette.nowPlayingBg,
              child: Text(
                '1',
                style: TextStyle(
                  color: tint,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return baseRepeat;
  }

  String _playModeTooltip(MusicoletPlayMode mode, BuildContext context) {
    switch (mode) {
      case MusicoletPlayMode.repeatAll:
        return AppStrings.tr(
          'Repeat All (Ulangi Antrean)',
          'Repeat All (Loop Queue)',
          context,
        );
      case MusicoletPlayMode.repeatOne:
        return AppStrings.tr(
          'Repeat One (Ulangi 1 Lagu)',
          'Repeat One (Loop Track)',
          context,
        );
      case MusicoletPlayMode.playSingleStop:
        return AppStrings.tr(
          '1→ (Putar 1 Lagu lalu Berhenti)',
          '1→ (Play Track Once & Stop)',
          context,
        );
      case MusicoletPlayMode.playQueueOnce:
        return AppStrings.tr(
          'Putar Antrean Sekali lalu Berhenti',
          'Play Queue Once & Stop',
          context,
        );
    }
  }

  // ===========================================================================
  // SECTION 4: THE `...` OVERFLOW MENU BOTTOM SHEET (ALL 3 REQUIRED GROUPS)
  // ===========================================================================
  void _showOverflowMenuSheet({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong? song,
  }) {
    final palette = context.palette;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return Consumer<LocalMusicProvider>(
          builder: (ctx, lp, _) {
            final currentSong = lp.currentSong ?? song;
            final hasSong = currentSong != null;
            final pct = (lp.volume * 100).round();
            final boostDb = lp.preAmpGainDb;
            final isSyncedMode =
                lp.lyricsDisplayMode == EmbeddedLyricsDisplayMode.synced;

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.86,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.nowPlayingInactiveIcon,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (currentSong != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentSong.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.nowPlayingPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${currentSong.artist} • ${currentSong.folderName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.nowPlayingSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Divider(color: palette.hairline, height: 1),
                    ],
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // -------------------------------------------------
                            // GROUP 1: SONG / FILE GROUP
                            // -------------------------------------------------
                            _buildMenuGroupHeader(
                              palette: palette,
                              title: AppStrings.tr(
                                'Lagu & File',
                                'Song / File',
                                ctx,
                              ),
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.playlist_play_rounded,
                              title: AppStrings.tr(
                                'Tambah ke Antrean',
                                'Add to Queue',
                                ctx,
                              ),
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      lp.addToQueue(
                                        currentSong,
                                        playNext: true,
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppStrings.tr(
                                              'Ditambahkan ke urutan berikutnya: ${currentSong.title}',
                                              'Added to play next: ${currentSong.title}',
                                              context,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.playlist_add_rounded,
                              title: AppStrings.tr(
                                'Tambah ke Playlist',
                                'Add to Playlist',
                                ctx,
                              ),
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      showAddToPlaylistSheet(
                                        context,
                                        localProvider: lp,
                                        song: currentSong,
                                      );
                                    },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.info_outline_rounded,
                              title: AppStrings.tr(
                                'Info File & Path Folder',
                                'File Info & Folder Path',
                                ctx,
                              ),
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      _showSongInfoDialog(context, currentSong);
                                    },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.folder_open_rounded,
                              title: AppStrings.tr(
                                'Buka Folder',
                                'Open Folder',
                                ctx,
                              ),
                              enabled: true,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                widget.onNavigateToFolders();
                              },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.drive_file_move_outlined,
                              title: AppStrings.tr(
                                'Pindah Folder',
                                'Move to Folder',
                                ctx,
                              ),
                              subtitle: hasSong
                                  ? AppStrings.tr(
                                      'Saat ini di ${currentSong.folderName}',
                                      'Currently in ${currentSong.folderName}',
                                      ctx,
                                    )
                                  : null,
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      widget.onMoveLocalSongFolder(currentSong);
                                    },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.edit_outlined,
                              title: AppStrings.tr(
                                'Edit Tag & Embedded Lyrics',
                                'Edit Tags & Lyrics',
                                ctx,
                              ),
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      TagEditorSheet.showForLocalSong(
                                        context,
                                        downloaderProvider: downloaderProvider,
                                        localProvider: lp,
                                        song: currentSong,
                                      );
                                    },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.delete_outline_rounded,
                              title: AppStrings.tr(
                                'Hapus File Lagu',
                                'Delete Song File',
                                ctx,
                              ),
                              isDestructive: true,
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      _confirmDeleteSong(
                                        context,
                                        lp,
                                        currentSong,
                                      );
                                    },
                            ),

                            Divider(color: palette.hairline, height: 16),

                            // -------------------------------------------------
                            // GROUP 2: LYRICS GROUP
                            // -------------------------------------------------
                            _buildMenuGroupHeader(
                              palette: palette,
                              title: AppStrings.tr('Lirik', 'Lyrics', ctx),
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.cloud_download_outlined,
                              title: AppStrings.tr(
                                'Ganti Lirik dari LRCLIB',
                                'Change Lyrics from LRCLIB',
                                ctx,
                              ),
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      _showLrclibCandidatesSheet(
                                        context,
                                        lp,
                                        currentSong,
                                      );
                                    },
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.auto_awesome_outlined,
                              title: AppStrings.tr(
                                'Auto-Romaji Lirik & Judul Jepang',
                                'Auto-Romaji Lyrics & Title',
                                ctx,
                              ),
                              trailing: hasSong
                                  ? Switch.adaptive(
                                      value: lp.isRomajiEnabledForSong(
                                        currentSong.filePath,
                                      ),
                                      activeTrackColor:
                                          palette.nowPlayingPrimary,
                                      activeThumbColor:
                                          palette.nowPlayingOnPrimary,
                                      onChanged: (nextVal) async {
                                        Navigator.of(ctx).pop();
                                        final ok = await lp.setRomajiForSong(
                                          currentSong,
                                          nextVal,
                                          includeMetadata: true,
                                          persistToFile: true,
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                ok
                                                    ? (nextVal
                                                        ? AppStrings.tr(
                                                            'Tag & lirik berhasil dikonversi ke Romaji.',
                                                            'Tags & lyrics converted to Romaji.',
                                                            context,
                                                          )
                                                        : AppStrings.tr(
                                                            'Lirik dikembalikan ke teks asli.',
                                                            'Lyrics restored to original script.',
                                                            context,
                                                          ))
                                                    : AppStrings.tr(
                                                        'Gagal menyimpan perubahan Romaji ke file ${currentSong.audioFormatLabel}.',
                                                        'Failed to save Romaji changes to ${currentSong.audioFormatLabel} file.',
                                                        context,
                                                      ),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    )
                                  : null,
                              enabled: hasSong,
                              onTap: !hasSong
                                  ? null
                                  : () async {
                                      final wasRomaji =
                                          lp.isRomajiEnabledForSong(
                                        currentSong.filePath,
                                      );
                                      final nextVal = !wasRomaji;
                                      Navigator.of(ctx).pop();
                                      final ok = await lp.setRomajiForSong(
                                        currentSong,
                                        nextVal,
                                        includeMetadata: true,
                                        persistToFile: true,
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? (nextVal
                                                      ? AppStrings.tr(
                                                          'Tag & lirik berhasil dikonversi ke Romaji.',
                                                          'Tags & lyrics converted to Romaji.',
                                                          context,
                                                        )
                                                      : AppStrings.tr(
                                                          'Lirik dikembalikan ke teks asli.',
                                                          'Lyrics restored to original script.',
                                                          context,
                                                        ))
                                                  : AppStrings.tr(
                                                      'Gagal menyimpan perubahan Romaji ke file ${currentSong.audioFormatLabel}.',
                                                      'Failed to save Romaji changes to ${currentSong.audioFormatLabel} file.',
                                                      context,
                                                    ),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                            ),
                            _buildFontSizeStepperTile(
                              palette: palette,
                              icon: Icons.text_fields_rounded,
                              title: AppStrings.tr(
                                'Ukuran Font Lirik Aktif',
                                'Active Lyrics Font Size',
                                ctx,
                              ),
                              valuePt: lp.lyricsFontSize,
                              canDecrease: lp.canDecreaseLyricsFontSize,
                              canIncrease: lp.canIncreaseLyricsFontSize,
                              onDecrease: lp.decreaseLyricsFontSize,
                              onIncrease: lp.increaseLyricsFontSize,
                              minusButtonKey: const ValueKey<String>(
                                'lyrics_active_font_minus',
                              ),
                              plusButtonKey: const ValueKey<String>(
                                'lyrics_active_font_plus',
                              ),
                              valueTextKey: const ValueKey<String>(
                                'lyrics_active_font_value',
                              ),
                            ),
                            _buildFontSizeStepperTile(
                              palette: palette,
                              icon: Icons.format_size_rounded,
                              title: AppStrings.tr(
                                'Ukuran Font Lirik Redup',
                                'Dimmed Lyrics Font Size',
                                ctx,
                              ),
                              subtitle: AppStrings.tr(
                                'Khusus layar Home',
                                'Home screen only',
                                ctx,
                              ),
                              valuePt: lp.secondaryLyricsFontSize,
                              canDecrease:
                                  lp.canDecreaseSecondaryLyricsFontSize,
                              canIncrease:
                                  lp.canIncreaseSecondaryLyricsFontSize,
                              onDecrease: lp.decreaseSecondaryLyricsFontSize,
                              onIncrease: lp.increaseSecondaryLyricsFontSize,
                              minusButtonKey: const ValueKey<String>(
                                'lyrics_secondary_font_minus',
                              ),
                              plusButtonKey: const ValueKey<String>(
                                'lyrics_secondary_font_plus',
                              ),
                              valueTextKey: const ValueKey<String>(
                                'lyrics_secondary_font_value',
                              ),
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.sync_rounded,
                              title: AppStrings.tr(
                                'Sinkronisasi Waktu Lirik',
                                'Lyrics Auto-Sync',
                                ctx,
                              ),
                              trailing: Switch.adaptive(
                                value: lp.autoScrollLyrics,
                                activeTrackColor: palette.nowPlayingPrimary,
                                activeThumbColor: palette.nowPlayingOnPrimary,
                                onChanged: (_) => lp.toggleAutoScrollLyrics(),
                              ),
                              enabled: true,
                              onTap: lp.toggleAutoScrollLyrics,
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.lyrics_outlined,
                              title: AppStrings.tr(
                                'Mode & Sumber Lirik',
                                'Lyrics Mode & Source',
                                ctx,
                              ),
                              subtitle: isSyncedMode
                                  ? AppStrings.tr(
                                      'Mode: Lirik Berjalan (Synced) • Ketuk untuk ganti / lihat penuh',
                                      'Mode: Synced Lyrics • Tap to switch or view full lyrics',
                                      ctx,
                                    )
                                  : AppStrings.tr(
                                      'Mode: Lirik Polos (Plain) • Ketuk untuk ganti / lihat penuh',
                                      'Mode: Plain Lyrics • Tap to switch or view full lyrics',
                                      ctx,
                                    ),
                              enabled: true,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _showLyricsModeAndSourceSheet(
                                  context: context,
                                  localProvider: lp,
                                  song: currentSong,
                                );
                              },
                            ),

                            Divider(color: palette.hairline, height: 16),

                            // -------------------------------------------------
                            // GROUP 3: AUDIO GROUP
                            // -------------------------------------------------
                            _buildMenuGroupHeader(
                              palette: palette,
                              title: 'Audio',
                            ),
                            _buildMenuTile(
                              palette: palette,
                              icon: Icons.equalizer_rounded,
                              title: AppStrings.tr(
                                'Equalizer Sistem Android',
                                'Android System Equalizer',
                                ctx,
                              ),
                              enabled: true,
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                final opened = await lp.openSystemEqualizer();
                                if (!opened && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppStrings.tr(
                                          'Equalizer bawaan sistem tidak ditemukan di perangkat ini.',
                                          'Built-in system equalizer was not found on this device.',
                                          context,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),

                            // Inline Volume & Pre-Amp Slider inside the `...` sheet
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        AppStrings.tr(
                                          'Volume & Pre-Amp Audio',
                                          'Volume & Pre-Amp',
                                          ctx,
                                        ),
                                        style: TextStyle(
                                          color: palette.nowPlayingPrimary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (lp.volume < 1.0 || boostDb > 0.0)
                                        MographSpringTap(
                                          pressedScale: 0.88,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  palette.nowPlayingPrimary,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            onPressed: () {
                                              lp.setVolume(1.0);
                                              lp.setPreAmpGainDb(0.0);
                                            },
                                            child: const Text(
                                              'Reset 100% (0 dB)',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      MographSpringTap(
                                        pressedScale: 0.80,
                                        child: MographStatePop(
                                          stateKey: lp.volume <= 0.01,
                                          scaleBoost: 0.18,
                                          child: IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => lp.setVolume(
                                              lp.volume > 0 ? 0.0 : 1.0,
                                            ),
                                            icon: Icon(
                                              lp.volume <= 0.01
                                                  ? Icons.volume_off_rounded
                                                  : Icons.volume_up_rounded,
                                              size: 20,
                                              color: palette.nowPlayingPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(ctx).copyWith(
                                            trackHeight: 2.5,
                                            activeTrackColor:
                                                palette.nowPlayingPrimary,
                                            inactiveTrackColor:
                                                palette.seekbarInactive,
                                            thumbColor:
                                                palette.nowPlayingPrimary,
                                          ),
                                          child: Slider(
                                            key: const ValueKey<String>(
                                              'overflow_volume_slider',
                                            ),
                                            min: 0.0,
                                            max: 1.0,
                                            value: lp.volume,
                                            onChanged: lp.setVolume,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 44,
                                        child: Text(
                                          '$pct%',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: palette.nowPlayingPrimary,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Icon(
                                          Icons.graphic_eq_rounded,
                                          size: 20,
                                          color: palette.nowPlayingSecondary,
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(ctx).copyWith(
                                            trackHeight: 2.5,
                                            activeTrackColor:
                                                palette.nowPlayingPrimary,
                                            inactiveTrackColor:
                                                palette.seekbarInactive,
                                            thumbColor:
                                                palette.nowPlayingPrimary,
                                          ),
                                          child: Slider(
                                            key: const ValueKey<String>(
                                              'overflow_preamp_slider',
                                            ),
                                            min: 0.0,
                                            max: 6.0,
                                            divisions: 12,
                                            value: boostDb,
                                            onChanged: lp.setPreAmpGainDb,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 44,
                                        child: Text(
                                          '+${boostDb.toStringAsFixed(1)}dB',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: palette.nowPlayingSecondary,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMenuGroupHeader({
    required MusEveePalette palette,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: palette.nowPlayingSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildFontSizeStepperTile({
    required MusEveePalette palette,
    required IconData icon,
    required String title,
    String? subtitle,
    required double valuePt,
    required bool canDecrease,
    required bool canIncrease,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
    required Key minusButtonKey,
    required Key plusButtonKey,
    Key? valueTextKey,
  }) {
    Widget buildStepButton({
      required Key key,
      required IconData buttonIcon,
      required bool enabled,
      required VoidCallback onPressed,
    }) {
      return MographSpringTap(
        enabled: enabled,
        pressedScale: 0.88,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: palette.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.hairline, width: 0.8),
            ),
            alignment: Alignment.center,
            child: Icon(
              buttonIcon,
              size: 16,
              color: enabled
                  ? palette.nowPlayingPrimary
                  : palette.nowPlayingInactiveIcon,
            ),
          ),
        ),
      );
    }

    return _buildMenuTile(
      palette: palette,
      icon: icon,
      title: title,
      subtitle: subtitle,
      squashOnTap: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildStepButton(
            key: minusButtonKey,
            buttonIcon: Icons.remove_rounded,
            enabled: canDecrease,
            onPressed: onDecrease,
          ),
          SizedBox(
            width: 54,
            child: Text(
              '${valuePt.toStringAsFixed(1)} pt',
              key: valueTextKey,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.nowPlayingPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          buildStepButton(
            key: plusButtonKey,
            buttonIcon: Icons.add_rounded,
            enabled: canIncrease,
            onPressed: onIncrease,
          ),
        ],
      ),
      enabled: true,
    );
  }

  Widget _buildMenuTile({
    required MusEveePalette palette,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool isDestructive = false,
    bool enabled = true,
    bool squashOnTap = true,
    VoidCallback? onTap,
  }) {
    final fgColor = isDestructive
        ? MusEveePalette.error
        : (enabled
            ? palette.nowPlayingPrimary
            : palette.nowPlayingInactiveIcon);

    return MographSpringTap(
      enabled: enabled && squashOnTap,
      pressedScale: 0.975,
      child: ListTile(
        dense: true,
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        leading: Icon(icon, size: 20, color: fgColor),
        title: Text(
          title,
          style: TextStyle(
            color: fgColor,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(
                  color: palette.nowPlayingSecondary,
                  fontSize: 11.5,
                ),
              )
            : null,
        trailing: trailing,
        onTap: enabled ? onTap : null,
      ),
    );
  }

  // ===========================================================================
  // SUPPORTING SHEETS: NO-LYRICS FLOW, LYRICS MODE & SOURCE, FULL LYRICS, INFO
  // ===========================================================================
  void _showNoLyricsActionSheet({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required DownloaderProvider downloaderProvider,
    required LocalSong song,
  }) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.nowPlayingInactiveIcon,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    AppStrings.tr(
                      'Belum Ada Lirik Tertanam',
                      'No Embedded Lyrics Yet',
                      ctx,
                    ),
                    style: TextStyle(
                      color: palette.nowPlayingPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: palette.hairline, height: 1),
                ListTile(
                  leading: Icon(
                    Icons.search_rounded,
                    color: palette.nowPlayingPrimary,
                  ),
                  title: Text(
                    AppStrings.tr(
                      'Cari Lirik LRCLIB',
                      'Search LRCLIB Lyrics',
                      ctx,
                    ),
                    style: TextStyle(
                      color: palette.nowPlayingPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showLrclibCandidatesSheet(context, localProvider, song);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.edit_outlined,
                    color: palette.nowPlayingPrimary,
                  ),
                  title: Text(
                    AppStrings.tr(
                      'Isi Manual',
                      'Enter Manually',
                      ctx,
                    ),
                    style: TextStyle(
                      color: palette.nowPlayingPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    TagEditorSheet.showForLocalSong(
                      context,
                      downloaderProvider: downloaderProvider,
                      localProvider: localProvider,
                      song: song,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLyricsModeAndSourceSheet({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required LocalSong? song,
  }) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Consumer<LocalMusicProvider>(
          builder: (ctx, lp, _) {
            final isSynced =
                lp.lyricsDisplayMode == EmbeddedLyricsDisplayMode.synced;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.nowPlayingInactiveIcon,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        AppStrings.tr(
                          'Mode & Sumber Lirik',
                          'Lyrics Mode & Source',
                          ctx,
                        ),
                        style: TextStyle(
                          color: palette.nowPlayingPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Divider(color: palette.hairline, height: 1),
                    ListTile(
                      leading: Icon(
                        isSynced
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: palette.nowPlayingPrimary,
                        size: 20,
                      ),
                      title: Text(
                        AppStrings.tr(
                          'Lirik Berjalan (Synced)',
                          'Synced Lyrics (LRC)',
                          ctx,
                        ),
                        style: TextStyle(
                          color: palette.nowPlayingPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        lp.setLyricsDisplayMode(
                          EmbeddedLyricsDisplayMode.synced,
                        );
                        Navigator.of(ctx).pop();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        !isSynced
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: palette.nowPlayingPrimary,
                        size: 20,
                      ),
                      title: Text(
                        AppStrings.tr(
                          'Lirik Polos (Plain)',
                          'Plain Lyrics',
                          ctx,
                        ),
                        style: TextStyle(
                          color: palette.nowPlayingPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        lp.setLyricsDisplayMode(
                          EmbeddedLyricsDisplayMode.plain,
                        );
                        Navigator.of(ctx).pop();
                      },
                    ),
                    if (song != null && song.hasLyrics) ...[
                      Divider(color: palette.hairline, height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.subject_rounded,
                          color: palette.nowPlayingPrimary,
                          size: 20,
                        ),
                        title: Text(
                          AppStrings.tr(
                            'Lihat Daftar Lirik Penuh',
                            'View Full Lyrics List',
                            ctx,
                          ),
                          style: TextStyle(
                            color: palette.nowPlayingPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showFullLyricsSheet(
                            context: context,
                            localProvider: lp,
                            song: song,
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFullLyricsSheet({
    required BuildContext context,
    required LocalMusicProvider localProvider,
    required LocalSong song,
  }) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.nowPlayingBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.nowPlayingInactiveIcon,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.nowPlayingPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.nowPlayingSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: palette.hairline, height: 1),
                  Expanded(
                    child: Consumer<LocalMusicProvider>(
                      builder: (ctx, lp, _) {
                        final liveSong =
                            lp.currentSong?.filePath == song.filePath
                                ? lp.currentSong!
                                : song;
                        if (liveSong.hasSyncedLyrics &&
                            lp.lyricsDisplayMode ==
                                EmbeddedLyricsDisplayMode.synced) {
                          return ValueListenableBuilder<int>(
                            valueListenable: lp.activeLyricIndexNotifier,
                            builder: (ctx, activeIdx, _) {
                              final entries = lp.syncedLyricsFor(liveSong);
                              final sheetWidth = math.max(
                                140.0,
                                MediaQuery.of(ctx).size.width - 44.0,
                              );
                              final prefOffset = NowPlayingView
                                  .computeStageActiveFontPrefOffset(
                                lp.lyricsFontSize,
                              );
                              return ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                itemCount: entries.length,
                                itemBuilder: (ctx, idx) {
                                  final entry = entries[idx];
                                  final isActive = idx == activeIdx;
                                  final line = entry.text.trim().isEmpty
                                      ? '♪'
                                      : entry.text.trim();
                                  final activeSize = isActive
                                      ? NowPlayingView
                                          .computeActiveLyricFontSize(
                                          line,
                                          maxWidth: sheetWidth,
                                          preferredOffset: prefOffset,
                                        )
                                      : MusEveePalette
                                          .lyricPanelSecondaryFontSize;
                                  return InkWell(
                                    onTap: () {
                                      _seekFromUserGesture(
                                        lp,
                                        entry.timeMs,
                                      );
                                      Navigator.of(ctx).pop();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        line,
                                        style: TextStyle(
                                          color: isActive
                                              ? palette.nowPlayingPrimary
                                              : palette.nowPlayingSecondary,
                                          fontSize: activeSize,
                                          fontWeight: FontWeight.w400,
                                          height:
                                              MusEveePalette.lyricLineHeight,
                                        ),
                                        strutStyle: StrutStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: activeSize,
                                          fontWeight: FontWeight.w400,
                                          height:
                                              MusEveePalette.lyricLineHeight,
                                          forceStrutHeight: true,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }
                        final plainLines = lp.plainLyricLinesFor(liveSong);
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemCount: plainLines.length,
                          itemBuilder: (ctx, idx) {
                            final line = plainLines[idx];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                line,
                                style: TextStyle(
                                  color: palette.nowPlayingPrimary,
                                  fontSize: MusEveePalette
                                      .lyricPanelSecondaryFontSize,
                                  fontWeight: FontWeight.w400,
                                  height: MusEveePalette.lyricLineHeight,
                                ),
                                strutStyle: const StrutStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: MusEveePalette
                                      .lyricPanelSecondaryFontSize,
                                  fontWeight: FontWeight.w400,
                                  height: MusEveePalette.lyricLineHeight,
                                  forceStrutHeight: true,
                                ),
                              ),
                            );
                          },
                        );
                      },
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

  void _showSongInfoDialog(BuildContext context, LocalSong song) {
    final palette = context.palette;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.nowPlayingBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: palette.hairline,
              width: 0.8,
            ),
          ),
          title: Text(
            AppStrings.tr(
              'Informasi File & Tag Audio',
              'File & Audio Tag Information',
              ctx,
            ),
            style: TextStyle(
              color: palette.nowPlayingPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow(
                  palette,
                  AppStrings.tr('Judul', 'Title', ctx),
                  song.title,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Artis', 'Artist', ctx),
                  song.artist,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Album', 'Album', ctx),
                  song.album,
                ),
                if (song.year.isNotEmpty)
                  _infoRow(
                    palette,
                    AppStrings.tr('Tahun', 'Year', ctx),
                    song.year,
                  ),
                _infoRow(
                  palette,
                  AppStrings.tr('Folder', 'Folder', ctx),
                  song.folderName,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Path File', 'File Path', ctx),
                  song.filePath,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Durasi', 'Duration', ctx),
                  song.formattedDuration,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Ukuran', 'Size', ctx),
                  song.formattedFileSize,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Format Audio', 'Audio Format', ctx),
                  song.audioFormatLabel,
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Kualitas Audio', 'Audio Quality', ctx),
                  '${song.bitrateKbps} kbps • ${song.sampleRateHz} Hz',
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Cover Tertanam', 'Embedded Cover', ctx),
                  song.hasCover
                      ? AppStrings.tr(
                          'Tersedia (Embedded)',
                          'Available (Embedded)',
                          ctx,
                        )
                      : AppStrings.tr('Tidak ada', 'None', ctx),
                ),
                _infoRow(
                  palette,
                  AppStrings.tr('Lirik Tertanam', 'Embedded Lyrics', ctx),
                  song.hasSyncedLyrics
                      ? AppStrings.tr(
                          'LRC Berjalan [mm:ss.xx]',
                          'Synced LRC [mm:ss.xx]',
                          ctx,
                        )
                      : (song.hasLyrics
                          ? AppStrings.tr('Lirik Biasa', 'Plain Lyrics', ctx)
                          : AppStrings.tr('Tidak ada', 'None', ctx)),
                ),
              ],
            ),
          ),
          actions: [
            MographSpringTap(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  AppStrings.tr('Tutup', 'Close', ctx),
                  style: TextStyle(
                    color: palette.nowPlayingPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(MusEveePalette palette, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.nowPlayingSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1.5),
          SelectableText(
            value,
            style: TextStyle(
              color: palette.nowPlayingPrimary,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLrclibCandidatesSheet(
    BuildContext context,
    LocalMusicProvider localProvider,
    LocalSong song,
  ) async {
    final palette = context.palette;
    localProvider.loadLyricsCandidatesForSong(song);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.nowPlayingBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Consumer<LocalMusicProvider>(
          builder: (ctx, lp, _) {
            final cands = lp.localLyricsCandidates;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.nowPlayingInactiveIcon,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      AppStrings.tr(
                        'Pilih Kandidat Lirik (LRCLIB)',
                        'Select Lyrics Candidate (LRCLIB)',
                        ctx,
                      ),
                      style: TextStyle(
                        color: palette.nowPlayingPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${song.artist} — ${song.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.nowPlayingSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (lp.isLoadingLyricsCandidates)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: palette.nowPlayingPrimary,
                          ),
                        ),
                      )
                    else if (cands.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          AppStrings.tr(
                            'Kandidat lirik tidak ditemukan di LRCLIB untuk lagu ini.',
                            'No lyrics candidates found on LRCLIB for this song.',
                            ctx,
                          ),
                          style: TextStyle(
                            color: palette.nowPlayingSecondary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: cands.length,
                          separatorBuilder: (ctx, idx) =>
                              Divider(color: palette.hairline, height: 1),
                          itemBuilder: (ctx, idx) {
                            final cand = cands[idx];
                            return InkWell(
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                try {
                                  await lp.applyLyricsCandidateToSong(
                                    song,
                                    cand,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppStrings.tr(
                                            'Lirik ${AppStrings.formatLyricsLanguageTag(cand.languageTag)} berhasil ditanamkan ke ${song.audioFormatLabel}.',
                                            'Lyrics ${AppStrings.formatLyricsLanguageTag(cand.languageTag)} embedded into ${song.audioFormatLabel}.',
                                            context,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppStrings.tr(
                                            'Gagal menanamkan lirik ke ${song.audioFormatLabel}: $e',
                                            'Failed to embed lyrics into ${song.audioFormatLabel}: $e',
                                            context,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          AppStrings.formatLyricsLanguageTag(
                                            cand.languageTag,
                                          ),
                                          style: TextStyle(
                                            color: palette.nowPlayingPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${cand.hasSynced ? AppStrings.tr('LRC Berjalan', 'Synced LRC', ctx) : AppStrings.tr('Biasa', 'Plain', ctx)} • ${cand.formattedDuration}',
                                          style: TextStyle(
                                            color: palette.nowPlayingSecondary,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      cand.previewTwoLines,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.nowPlayingPrimary,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteSong(
    BuildContext context,
    LocalMusicProvider localProvider,
    LocalSong song,
  ) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: palette.nowPlayingBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.hairline, width: 0.8),
          ),
          title: Text(
            AppStrings.tr('Hapus File Lagu?', 'Delete Song File?', ctx),
            style: TextStyle(
              color: palette.nowPlayingPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            AppStrings.tr(
              'Hapus permanen "${song.title}" dari folder ${song.folderName}?',
              'Permanently delete "${song.title}" from ${song.folderName}?',
              ctx,
            ),
            style: TextStyle(color: palette.nowPlayingSecondary, fontSize: 13),
          ),
          actions: [
            MographSpringTap(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  AppStrings.tr('Batal', 'Cancel', ctx),
                  style: TextStyle(color: palette.nowPlayingSecondary),
                ),
              ),
            ),
            MographSpringTap(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MusEveePalette.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(AppStrings.tr('Hapus', 'Delete', ctx)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      final ok = await localProvider.deleteLocalSong(song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? AppStrings.tr(
                      'File lagu berhasil dihapus.',
                      'Song file deleted.',
                      context,
                    )
                  : AppStrings.tr(
                      'Gagal menghapus file lagu.',
                      'Failed to delete song file.',
                      context,
                    ),
            ),
          ),
        );
      }
    }
  }
}
