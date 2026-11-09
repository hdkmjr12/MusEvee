import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

/// Minimalist Musicolet-styled Settings tab (`index 5`).
/// Intentionally contains only the Download Audio Quality section and version footer.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  static const Color _kBg = Color(0xFF0E1014);
  static const Color _kCard = Color(0xFF17191E);
  static const Color _kSubtle = Color(0xFF22252D);
  static const Color _kAccent = Color(0xFF3898EC);
  static const Color _kText = Color(0xFFF2F4F7);
  static const Color _kMuted = Color(0xFF98A2B3);

  @override
  Widget build(BuildContext context) {
    final hairline = Colors.white.withValues(alpha: 0.08);

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final selectedQuality = settingsProvider.downloadQuality;

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
          color: _kBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Musicolet Sub-Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: _kCard,
                  border: Border(
                    bottom: BorderSide(color: hairline, width: 0.8),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.settingsHeaderTitle,
                      style: const TextStyle(
                        color: _kText,
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
                    // Section Header: "Unduhan" / "Downloads"
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        AppStrings.settingsDownloadsSection,
                        style: const TextStyle(
                          color: _kAccent,
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
                        color: _kCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: hairline, width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.settingsDownloadQualityTitle,
                            style: const TextStyle(
                              color: _kText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (int i = 0; i < options.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            _buildQualityOptionTile(
                              quality: options[i].quality,
                              title: options[i].title,
                              subtitle: options[i].subtitle,
                              isSelected:
                                  selectedQuality == options[i].quality,
                              hairline: hairline,
                              onSelect: () => settingsProvider
                                  .setDownloadQuality(options[i].quality),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            AppStrings.settingsDownloadQualityNote,
                            style: const TextStyle(
                              color: _kMuted,
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

              // Plain text footer at the bottom: "MusEvee v4.7"
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 14),
                child: Text(
                  AppStrings.appVersionFooter,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kMuted,
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

  Widget _buildQualityOptionTile({
    required DownloadQuality quality,
    required String title,
    required String subtitle,
    required bool isSelected,
    required Color hairline,
    required VoidCallback onSelect,
  }) {
    return PressableScale(
      pressedScale: 0.985,
      child: Material(
        key: ValueKey('download_quality_${quality.name}'),
        color: isSelected ? _kAccent.withValues(alpha: 0.14) : _kSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected ? _kAccent.withValues(alpha: 0.75) : hairline,
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
                  color: isSelected ? _kAccent : _kMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? Colors.white : _kText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _kMuted,
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
