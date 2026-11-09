import 'package:flutter/material.dart';

/// Centralized color tokens for MusEvee (Dark & Light Musicolet themes).
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
  });

  /// Semantic colors that remain constant across both Dark and Light modes.
  static const Color emerald = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color error = Color(0xFFF04438);
  static const Color snackBarBg = Color(0xFF1F242F);

  /// Signature Musicolet Dark Surface palette.
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
  );

  /// High-contrast Musicolet Light Surface palette (`primaryAccentDark` for contrast on white).
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
    );
  }
}

extension MusEveePaletteBuildContext on BuildContext {
  MusEveePalette get palette =>
      Theme.of(this).extension<MusEveePalette>() ?? MusEveePalette.dark;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

