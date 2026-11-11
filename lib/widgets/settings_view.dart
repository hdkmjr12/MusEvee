import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/hires_addon_service.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'pressable_scale.dart';

/// Minimalist Musicolet-styled Settings tab (`index 5`).
/// Contains Appearance (Dark/Light Theme), Download Audio Quality (including
/// Hi-Res Lossless FLAC + Add-on Source Manager), and version footer.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final selectedQuality = settingsProvider.downloadQuality;
        final selectedTheme = settingsProvider.themeMode;
        final activeAddonsCount = settingsProvider.enabledHiResAddonsCount;

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
          bool isHiRes,
        })>[
          (
            quality: DownloadQuality.hiResFlac,
            title: AppStrings.qualityHiResTitle,
            subtitle: AppStrings.qualityHiResSubtitle,
            isHiRes: true,
          ),
          (
            quality: DownloadQuality.best,
            title: AppStrings.qualityBestTitle,
            subtitle: AppStrings.qualityBestSubtitle,
            isHiRes: false,
          ),
          (
            quality: DownloadQuality.balanced,
            title: AppStrings.qualityBalancedTitle,
            subtitle: AppStrings.qualityBalancedSubtitle,
            isHiRes: false,
          ),
          (
            quality: DownloadQuality.efficient,
            title: AppStrings.qualityEfficientTitle,
            subtitle: AppStrings.qualityEfficientSubtitle,
            isHiRes: false,
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

                    // Card: Kualitas Audio Unduhan + Progressive Disclosure Add-on Card
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
                              isHiRes: options[i].isHiRes,
                              isSelected:
                                  selectedQuality == options[i].quality,
                              onSelect: () => settingsProvider
                                  .setDownloadQuality(options[i].quality),
                            ),
                          ],
                          const SizedBox(height: 10),
                          _buildHiResAddonManageShortcutCard(
                            context: context,
                            palette: palette,
                            activeAddonsCount: activeAddonsCount,
                          ),
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

              // Plain text footer at the bottom: "MusEvee v4.9"
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

  Widget _buildHiResAddonManageShortcutCard({
    required BuildContext context,
    required MusEveePalette palette,
    required int activeAddonsCount,
  }) {
    return PressableScale(
      pressedScale: 0.985,
      child: Material(
        key: const ValueKey('hires_addon_manage_card'),
        color: palette.surfaceSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: palette.hairline,
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showHiResAddonManagerSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 19,
                  color: palette.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.hiResAddonCardTitle(activeAddonsCount),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        AppStrings.hiResAddonCardSubtitle,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.hiResAddonManageButton,
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: palette.accent,
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

  static Future<void> showHiResAddonManagerSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => const _HiResAddonManagerSheet(),
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
    required bool isHiRes,
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isHiRes) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5.5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: MusEveePalette.amber.withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: MusEveePalette.amber.withValues(
                                    alpha: 0.55,
                                  ),
                                  width: 0.7,
                                ),
                              ),
                              child: const Text(
                                'FLAC',
                                style: TextStyle(
                                  color: MusEveePalette.amber,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
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

class _HiResAddonManagerSheet extends StatefulWidget {
  const _HiResAddonManagerSheet();

  @override
  State<_HiResAddonManagerSheet> createState() =>
      _HiResAddonManagerSheetState();
}

class _HiResAddonManagerSheetState extends State<_HiResAddonManagerSheet> {
  final HiResAddonService _addonService = HiResAddonService();
  bool _isRefreshing = false;

  Future<void> _refreshHealth(SettingsProvider settingsProvider) async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final updated = await _addonService.refreshAddonsHealth(
        settingsProvider.hiResAddons,
      );
      if (!mounted) return;
      await settingsProvider.replaceAllAddons(updated);
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _showAddAddonUrlDialog(
    BuildContext context,
    SettingsProvider settingsProvider,
  ) async {
    final controller = TextEditingController();
    final palette = context.palette;

    final enteredUrl = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: palette.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: palette.hairline, width: 0.8),
          ),
          title: Text(
            AppStrings.hiResAddonAddDialogTitle,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            key: const ValueKey('hires_addon_url_input'),
            controller: controller,
            autofocus: true,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: AppStrings.hiResAddonAddDialogHint,
              hintStyle: TextStyle(color: palette.textMuted, fontSize: 12),
              filled: true,
              fillColor: palette.surfaceSubtle,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: palette.hairline, width: 0.8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                AppStrings.hiResAddonCancelButton,
                style: TextStyle(color: palette.textMuted, fontSize: 12.5),
              ),
            ),
            FilledButton(
              key: const ValueKey('hires_addon_url_submit_btn'),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
              ),
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(controller.text.trim()),
              child: Text(
                AppStrings.hiResAddonSaveButton,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (enteredUrl == null || enteredUrl.trim().isEmpty) return;
    final added = await settingsProvider.addAddonUrl(enteredUrl);
    if (added == null) return;

    // Best-effort async manifest/index inspection
    try {
      final inspected = await _addonService.inspectAddonEndpoint(added);
      if (mounted) {
        await settingsProvider.updateAddonSource(inspected.updatedSource);
        if (inspected.expandedSubModules.isNotEmpty) {
          await settingsProvider.addOrMergeAddons(inspected.expandedSubModules);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.84;

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final addons = settingsProvider.hiResAddons;

        return Container(
          key: const ValueKey('hires_addon_manager_sheet'),
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          decoration: BoxDecoration(
            color: palette.bgCanvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(
              top: BorderSide(color: palette.hairline, width: 0.8),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag Pill
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStrings.hiResAddonModalTitle,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey('hires_addon_refresh_btn'),
                            onPressed: _isRefreshing
                                ? null
                                : () => _refreshHealth(settingsProvider),
                            icon: _isRefreshing
                                ? SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: palette.accent,
                                    ),
                                  )
                                : Icon(
                                    Icons.sync_rounded,
                                    size: 15,
                                    color: palette.accent,
                                  ),
                            label: Text(
                              AppStrings.hiResAddonRefreshStatus,
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey('hires_addon_reset_btn'),
                            onPressed: () => settingsProvider
                                .resetAddonsToDefaultPresets(),
                            icon: Icon(
                              Icons.restart_alt_rounded,
                              size: 15,
                              color: palette.textMuted,
                            ),
                            label: Text(
                              AppStrings.hiResAddonResetPresets,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppStrings.hiResAddonModalSubtitle.toUpperCase(),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),

                Divider(height: 1, thickness: 0.8, color: palette.hairline),

                // Reorderable List of Add-ons
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      color: palette.surfaceCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: palette.hairline,
                        width: 0.8,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      itemCount: addons.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        settingsProvider.reorderAddons(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final addon = addons[index];
                        final capabilitiesText = addon.capabilities.join(' · ');
                        final subtitleLine =
                            '${addon.name} v${addon.version} · $capabilitiesText';

                        return Container(
                          key: ValueKey('hires_addon_row_${addon.id}'),
                          decoration: BoxDecoration(
                            color: palette.surfaceCard,
                            border: index < addons.length - 1
                                ? Border(
                                    bottom: BorderSide(
                                      color: palette.hairline,
                                      width: 0.7,
                                    ),
                                  )
                                : null,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Priority Number (1, 2, 3...)
                              SizedBox(
                                width: 20,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Puzzle / Extension Icon
                              Icon(
                                Icons.extension_outlined,
                                size: 20,
                                color: addon.enabled
                                    ? palette.textPrimary
                                    : palette.textMuted,
                              ),
                              const SizedBox(width: 12),

                              // Module Name, Version + Capabilities, & Status Row
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      addon.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitleLine,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textMuted,
                                        fontSize: 11.5,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          addon.downloadsAllowed
                                              ? Icons
                                                  .arrow_circle_down_outlined
                                              : Icons.cloud_off_outlined,
                                          size: 13.5,
                                          color: palette.textMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            addon.downloadsAllowed
                                                ? AppStrings
                                                    .hiResAddonDownloadsAllowed
                                                : AppStrings
                                                    .hiResAddonStreamingOnly,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: palette.textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        if (addon.isHealthy != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            width: 6.5,
                                            height: 6.5,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: addon.isHealthy == true
                                                  ? MusEveePalette.emerald
                                                  : MusEveePalette.error,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Emerald Switch ON/OFF
                              Switch(
                                key: ValueKey('hires_addon_switch_${addon.id}'),
                                value: addon.enabled,
                                activeThumbColor: Colors.white,
                                activeTrackColor: MusEveePalette.emerald,
                                onChanged: (val) {
                                  settingsProvider.toggleAddonEnabled(
                                    addon.id,
                                    val,
                                  );
                                },
                              ),
                              const SizedBox(width: 4),

                              // Drag Handle `≡`
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    size: 20,
                                    color: palette.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // "+ Tambah URL Add-on" Button at Bottom
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: OutlinedButton.icon(
                    key: const ValueKey('hires_addon_add_url_btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(
                        color: palette.accent.withValues(alpha: 0.65),
                        width: 0.9,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        _showAddAddonUrlDialog(context, settingsProvider),
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: Text(
                      AppStrings.hiResAddonAddUrlButton,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
