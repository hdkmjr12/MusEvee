import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

/// Minimalist Musicolet-styled Settings tab (`index 5`).
/// Contains Appearance (Dark/Light Theme) and Download Audio Quality sections plus version footer.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final selectedQuality = settingsProvider.downloadQuality;
        final selectedTheme = settingsProvider.themeMode;

        final themeOptions = <({
          ThemeMode mode,
          String keyName,
          IconData icon,
          String title,
          String subtitle,
        })>[
          (
            mode: ThemeMode.dark,
            keyName: 'theme_mode_dark',
            icon: Icons.dark_mode_rounded,
            title: AppStrings.themeDarkTitle,
            subtitle: AppStrings.themeDarkSubtitle,
          ),
          (
            mode: ThemeMode.light,
            keyName: 'theme_mode_light',
            icon: Icons.light_mode_rounded,
            title: AppStrings.themeLightTitle,
            subtitle: AppStrings.themeLightSubtitle,
          ),
        ];

        final options = <({
          DownloadQuality quality,
          String title,
          String subtitle,
        })>[
          (
            quality: DownloadQuality.best,
            title: AppStrings.qualityBestTitle,
            subtitle: AppStrings.qualityBestSubtitle,
          ),
          (
            quality: DownloadQuality.balanced,
            title: AppStrings.qualityBalancedTitle,
            subtitle: AppStrings.qualityBalancedSubtitle,
          ),
          (
            quality: DownloadQuality.efficient,
            title: AppStrings.qualityEfficientTitle,
            subtitle: AppStrings.qualityEfficientSubtitle,
          ),
        ];

        return Container(
          color: palette.bgCanvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Musicolet Sub-Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: palette.surfaceCard,
                  border: Border(
                    bottom: BorderSide(color: palette.hairline, width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_rounded,
                      color: palette.textPrimary,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.settingsHeaderTitle,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                  children: [
                    // Section Header: "Tampilan" / "Appearance"
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        AppStrings.settingsAppearanceSection,
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Card: Tema Aplikasi (Dark / Light)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: palette.hairline,
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.settingsThemeTitle,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (int i = 0; i < themeOptions.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _buildThemeOptionTile(
                              palette: palette,
                              keyName: themeOptions[i].keyName,
                              icon: themeOptions[i].icon,
                              title: themeOptions[i].title,
                              subtitle: themeOptions[i].subtitle,
                              isSelected:
                                  selectedTheme == themeOptions[i].mode,
                              onSelect: () => settingsProvider.setThemeMode(
                                themeOptions[i].mode,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section Header: "Unduhan" / "Downloads"
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        AppStrings.settingsDownloadsSection,
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Card: Kualitas Audio Unduhan
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surfaceCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: palette.hairline,
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.settingsDownloadQualityTitle,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (int i = 0; i < options.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _buildQualityOptionTile(
                              palette: palette,
                              quality: options[i].quality,
                              title: options[i].title,
                              subtitle: options[i].subtitle,
                              isSelected:
                                  selectedQuality == options[i].quality,
                              onSelect: () => settingsProvider
                                  .setDownloadQuality(options[i].quality),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            AppStrings.settingsDownloadQualityNote,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 11.5,
                              height: 1.38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Plain text footer at the bottom: "MusEvee v4.8"
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 14),
                child: Text(
                  AppStrings.appVersionFooter,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeOptionTile({
    required MusEveePalette palette,
    required String keyName,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return PressableScale(
      pressedScale: 0.985,
      child: Material(
        key: ValueKey(keyName),
        color: isSelected
            ? palette.accent.withValues(alpha: 0.14)
            : palette.surfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? palette.accent.withValues(alpha: 0.75)
                : palette.hairline,
            width: isSelected ? 1.1 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: isSelected ? palette.accent : palette.textMuted,
                ),
                const SizedBox(width: 10),
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? palette.accent : palette.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOptionTile({
    required MusEveePalette palette,
    required DownloadQuality quality,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onSelect,
  }) {
    return PressableScale(
      pressedScale: 0.985,
      child: Material(
        key: ValueKey('download_quality_${quality.name}'),
        color: isSelected
            ? palette.accent.withValues(alpha: 0.14)
            : palette.surfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? palette.accent.withValues(alpha: 0.75)
                : palette.hairline,
            width: isSelected ? 1.1 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: isSelected ? palette.accent : palette.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
