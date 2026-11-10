import 'package:flutter/material.dart';

/// Centralized color and layout tokens for MusEvee (Dark & Light themes).
@immutable
class MusEveePalette extends ThemeExtension<MusEveePalette> {
  final Color bgCanvas;
  final Color bottomBar;
  final Color surfaceCard;
  final Color surfaceSubtle;
  final Color accent;
  final Color textPrimary;
  final Color textMuted;
  final Color hairline;
  final Color appBar;

  // Phase 1 Redesign tokens (Now Playing + Bottom Strip + Mini Player)
  final Color nowPlayingBg;
  final Color nowPlayingPrimary;
  final Color nowPlayingOnPrimary;
  final Color nowPlayingSecondary;
  final Color nowPlayingArtist;
  final Color nowPlayingInactiveIcon;
  final Color seekbarInactive;
  final Color discRingBorder;
  final Color discShadow;
  final Color favoriteActive;

  const MusEveePalette({
    required this.bgCanvas,
    required this.bottomBar,
    required this.surfaceCard,
    required this.surfaceSubtle,
    required this.accent,
    required this.textPrimary,
    required this.textMuted,
    required this.hairline,
    required this.appBar,
    this.nowPlayingBg = const Color(0xFFFFFFFF),
    this.nowPlayingPrimary = const Color(0xFF000000),
    this.nowPlayingOnPrimary = const Color(0xFFFFFFFF),
    this.nowPlayingSecondary = const Color(0xFF88888D),
    this.nowPlayingArtist = const Color(0xFF333336),
    this.nowPlayingInactiveIcon = const Color(0xFFD0D0D5),
    this.seekbarInactive = const Color(0xFFE4E4E8),
    this.discRingBorder = const Color(0xFFDADADE),
    this.discShadow = const Color(0x16000000),
    this.favoriteActive = const Color(0xFFEC504D),
  });

  /// Semantic colors that remain constant across both Dark and Light modes.
  static const Color emerald = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color error = Color(0xFFF04438);
  static const Color snackBarBg = Color(0xFF1F242F);

  /// Phase 1 Now Playing & Navigation dimension/motion tokens.
  static const double discDiameterFactor = 0.95;
  static const double discLeftEdgeFactor = 0.60;
  static const double discCenterHoleFactor = 0.21;
  static const double discRotationPeriodSeconds = 25.0;
  static const int discSpinDownDurationMs = 800;
  static const int discTrackChangeDurationMs = 300;
  static const double lyricActiveMaxFontSize = 22.0;
  static const double lyricActiveMidFontSize = 20.0;
  static const double lyricActiveMinFontSize = 18.0;
  static const double lyricSecondaryFontSize = 13.5;
  static const double lyricPanelSecondaryFontSize = 14.5;
  static const double lyricLineHeight = 1.2;
  static const double homeIntroLine0Opacity = 1.0;
  static const double homeIntroLine1Opacity = 0.72;
  static const double homeIntroLine2Opacity = 0.48;
  static const double songTitleFontSize = 15.5;
  static const double songArtistFontSize = 13.0;
  static const double seekbarTrackHeight = 2.5;
  static const double playPauseButtonSize = 56.0;
  static const double playPauseIconSize = 26.0;
  static const double prevNextIconSize = 26.0;
  static const double minTouchTargetSize = 48.0;
  static const double navStripHeight = 60.0;
  static const double navIconSize = 23.0;
  static const double navActivePlayCircleSize = 44.0;
  static const int navSlideDurationMs = 280;
  static const int lyricSlideDurationMs = 400;

  // Phase 1.5 Now Playing 3-Panel Pager & Disguised Lyrics Panel tokens
  static const double pagerDotSize = 6.0;
  static const double pagerDotSpacing = 6.0;
  static const int pagerSettleDurationMs = 300;
  static const int lyricsAutoScrollDurationMs = 300;
  static const int lyricsManualScrollResumeDelaySeconds = 4;
  static const double lyricsPanelOpacityDistance0 = 1.0;
  static const double lyricsPanelOpacityDistance1 = 0.90;
  static const double lyricsPanelOpacityDistance2 = 0.65;
  static const double lyricsPanelOpacityDistance3Plus = 0.45;
  static const double lyricsPanelEdgeFadeHeightFactor = 0.08;

  /// Dark Surface palette (with Phase 1 Now Playing dark tokens).
  static const MusEveePalette dark = MusEveePalette(
    bgCanvas: Color(0xFF0E1014),
    bottomBar: Color(0xFF0A0C10),
    surfaceCard: Color(0xFF17191E),
    surfaceSubtle: Color(0xFF22252D),
    accent: Color(0xFF3898EC),
    textPrimary: Color(0xFFF2F4F7),
    textMuted: Color(0xFF98A2B3),
    hairline: Color(0x17FFFFFF), // Colors.white.withValues(alpha: 0.09)
    appBar: Color(0xFF12151C),
    nowPlayingBg: Color(0xFF0E1014),
    nowPlayingPrimary: Color(0xFFF2F4F7),
    nowPlayingOnPrimary: Color(0xFF0E1014),
    nowPlayingSecondary: Color(0xFF8A93A2),
    nowPlayingArtist: Color(0xFFB8C0CC),
    nowPlayingInactiveIcon: Color(0xFF4C5361),
    seekbarInactive: Color(0xFF262A34),
    discRingBorder: Color(0xFF282D38),
    discShadow: Color(0x55000000),
    favoriteActive: Color(0xFFEC504D),
  );

  /// High-contrast Light Surface palette (matches Figma reference 1:1 on Now Playing).
  static const MusEveePalette light = MusEveePalette(
    bgCanvas: Color(0xFFF6F7F9),
    bottomBar: Color(0xFFFFFFFF),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFECEEF1),
    accent: Color(0xFF1D74C6),
    textPrimary: Color(0xFF181A1F),
    textMuted: Color(0xFF667085),
    hairline: Color(0x17000000), // Colors.black.withValues(alpha: 0.09)
    appBar: Color(0xFFFFFFFF),
    nowPlayingBg: Color(0xFFFFFFFF),
    nowPlayingPrimary: Color(0xFF000000),
    nowPlayingOnPrimary: Color(0xFFFFFFFF),
    nowPlayingSecondary: Color(0xFF88888D),
    nowPlayingArtist: Color(0xFF333336),
    nowPlayingInactiveIcon: Color(0xFFD0D0D5),
    seekbarInactive: Color(0xFFE4E4E8),
    discRingBorder: Color(0xFFDADADE),
    discShadow: Color(0x16000000),
    favoriteActive: Color(0xFFEC504D),
  );

  @override
  MusEveePalette copyWith({
    Color? bgCanvas,
    Color? bottomBar,
    Color? surfaceCard,
    Color? surfaceSubtle,
    Color? accent,
    Color? textPrimary,
    Color? textMuted,
    Color? hairline,
    Color? appBar,
    Color? nowPlayingBg,
    Color? nowPlayingPrimary,
    Color? nowPlayingOnPrimary,
    Color? nowPlayingSecondary,
    Color? nowPlayingArtist,
    Color? nowPlayingInactiveIcon,
    Color? seekbarInactive,
    Color? discRingBorder,
    Color? discShadow,
    Color? favoriteActive,
  }) {
    return MusEveePalette(
      bgCanvas: bgCanvas ?? this.bgCanvas,
      bottomBar: bottomBar ?? this.bottomBar,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      hairline: hairline ?? this.hairline,
      appBar: appBar ?? this.appBar,
      nowPlayingBg: nowPlayingBg ?? this.nowPlayingBg,
      nowPlayingPrimary: nowPlayingPrimary ?? this.nowPlayingPrimary,
      nowPlayingOnPrimary: nowPlayingOnPrimary ?? this.nowPlayingOnPrimary,
      nowPlayingSecondary: nowPlayingSecondary ?? this.nowPlayingSecondary,
      nowPlayingArtist: nowPlayingArtist ?? this.nowPlayingArtist,
      nowPlayingInactiveIcon:
          nowPlayingInactiveIcon ?? this.nowPlayingInactiveIcon,
      seekbarInactive: seekbarInactive ?? this.seekbarInactive,
      discRingBorder: discRingBorder ?? this.discRingBorder,
      discShadow: discShadow ?? this.discShadow,
      favoriteActive: favoriteActive ?? this.favoriteActive,
    );
  }

  @override
  MusEveePalette lerp(covariant ThemeExtension<MusEveePalette>? other, double t) {
    if (other is! MusEveePalette) return this;
    return MusEveePalette(
      bgCanvas: Color.lerp(bgCanvas, other.bgCanvas, t) ?? bgCanvas,
      bottomBar: Color.lerp(bottomBar, other.bottomBar, t) ?? bottomBar,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t) ?? surfaceCard,
      surfaceSubtle:
          Color.lerp(surfaceSubtle, other.surfaceSubtle, t) ?? surfaceSubtle,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      hairline: Color.lerp(hairline, other.hairline, t) ?? hairline,
      appBar: Color.lerp(appBar, other.appBar, t) ?? appBar,
      nowPlayingBg:
          Color.lerp(nowPlayingBg, other.nowPlayingBg, t) ?? nowPlayingBg,
      nowPlayingPrimary:
          Color.lerp(nowPlayingPrimary, other.nowPlayingPrimary, t) ??
              nowPlayingPrimary,
      nowPlayingOnPrimary:
          Color.lerp(nowPlayingOnPrimary, other.nowPlayingOnPrimary, t) ??
              nowPlayingOnPrimary,
      nowPlayingSecondary:
          Color.lerp(nowPlayingSecondary, other.nowPlayingSecondary, t) ??
              nowPlayingSecondary,
      nowPlayingArtist:
          Color.lerp(nowPlayingArtist, other.nowPlayingArtist, t) ??
              nowPlayingArtist,
      nowPlayingInactiveIcon:
          Color.lerp(nowPlayingInactiveIcon, other.nowPlayingInactiveIcon, t) ??
              nowPlayingInactiveIcon,
      seekbarInactive:
          Color.lerp(seekbarInactive, other.seekbarInactive, t) ??
              seekbarInactive,
      discRingBorder:
          Color.lerp(discRingBorder, other.discRingBorder, t) ?? discRingBorder,
      discShadow: Color.lerp(discShadow, other.discShadow, t) ?? discShadow,
      favoriteActive:
          Color.lerp(favoriteActive, other.favoriteActive, t) ?? favoriteActive,
    );
  }
}

extension MusEveePaletteBuildContext on BuildContext {
  MusEveePalette get palette =>
      Theme.of(this).extension<MusEveePalette>() ?? MusEveePalette.dark;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
