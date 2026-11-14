import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/hires_addon_service.dart';
import '../theme/musevee_palette.dart';
import '../utils/app_strings.dart';
import 'local_library_views.dart'
    show cleanMonochromeHeaderDecoration, statusBarHeaderPadding;
import 'pressable_scale.dart';

/// Minimalist Musicolet-styled Settings tab (`index 5`).
/// Contains Appearance (Auto/Dark/Light Theme dropdown), Download Audio Quality
/// dropdown (including Hi-Res Lossless FLAC + Add-on Source Manager), and version footer.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final effectiveIsDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final selectedQuality = settingsProvider.downloadQuality;
        final selectedTheme = settingsProvider.themeMode;
        final activeAddonsCount = settingsProvider.enabledHiResAddonsCount;

        final themeOptions = <_MonochromeDropdownOption<ThemeMode>>[
          _MonochromeDropdownOption<ThemeMode>(
            value: ThemeMode.system,
            keyName: 'theme_mode_system',
            icon: Icons.brightness_auto_rounded,
            title: AppStrings.themeAutoTitle,
            subtitle: AppStrings.themeAutoSubtitle,
          ),
          _MonochromeDropdownOption<ThemeMode>(
            value: ThemeMode.dark,
            keyName: 'theme_mode_dark',
            icon: Icons.dark_mode_rounded,
            title: AppStrings.themeDarkTitle,
            subtitle: AppStrings.themeDarkSubtitle,
          ),
          _MonochromeDropdownOption<ThemeMode>(
            value: ThemeMode.light,
            keyName: 'theme_mode_light',
            icon: Icons.light_mode_rounded,
            title: AppStrings.themeLightTitle,
            subtitle: AppStrings.themeLightSubtitle,
          ),
        ];

        final qualityOptions = <_MonochromeDropdownOption<DownloadQuality>>[
          _MonochromeDropdownOption<DownloadQuality>(
            value: DownloadQuality.hiResFlac,
            keyName: 'download_quality_${DownloadQuality.hiResFlac.name}',
            icon: Icons.high_quality_rounded,
            title: AppStrings.qualityHiResTitle,
            subtitle: AppStrings.qualityHiResSubtitle,
            badgeText: 'FLAC',
          ),
          _MonochromeDropdownOption<DownloadQuality>(
            value: DownloadQuality.best,
            keyName: 'download_quality_${DownloadQuality.best.name}',
            icon: Icons.graphic_eq_rounded,
            title: AppStrings.qualityBestTitle,
            subtitle: AppStrings.qualityBestSubtitle,
          ),
          _MonochromeDropdownOption<DownloadQuality>(
            value: DownloadQuality.balanced,
            keyName: 'download_quality_${DownloadQuality.balanced.name}',
            icon: Icons.audiotrack_rounded,
            title: AppStrings.qualityBalancedTitle,
            subtitle: AppStrings.qualityBalancedSubtitle,
          ),
          _MonochromeDropdownOption<DownloadQuality>(
            value: DownloadQuality.efficient,
            keyName: 'download_quality_${DownloadQuality.efficient.name}',
            icon: Icons.audiotrack_rounded,
            title: AppStrings.qualityEfficientTitle,
            subtitle: AppStrings.qualityEfficientSubtitle,
          ),
        ];

        return Container(
          color: palette.bgCanvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clean Monochrome Header matching Folders & Playlists
              Container(
                padding: statusBarHeaderPadding(context),
                decoration: cleanMonochromeHeaderDecoration(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/icons/settings.png',
                        width: 19,
                        height: 19,
                        fit: BoxFit.contain,
                        color: palette.textPrimary,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppStrings.settingsHeaderTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                          color: palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Card: Tema Aplikasi (Dropdown: Auto / Gelap / Terang)
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
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _MonochromeDropdownField<ThemeMode>(
                            dropdownKey: const ValueKey('theme_mode_dropdown'),
                            selectedValue: selectedTheme,
                            selectedSubtitleOverride:
                                selectedTheme == ThemeMode.system
                                    ? AppStrings.themeAutoResolvedSubtitle(
                                        isDark: effectiveIsDark,
                                      )
                                    : null,
                            options: themeOptions,
                            onSelected: settingsProvider.setThemeMode,
                          ),
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
                          color: palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Card: Kualitas Audio Unduhan (Dropdown) + Add-on Shortcut Card
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
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _MonochromeDropdownField<DownloadQuality>(
                            dropdownKey:
                                const ValueKey('download_quality_dropdown'),
                            selectedValue: selectedQuality,
                            options: qualityOptions,
                            onSelected: settingsProvider.setDownloadQuality,
                          ),
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
                  color: palette.nowPlayingPrimary,
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
                    horizontal: 9,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.nowPlayingPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.hiResAddonManageButton,
                        style: TextStyle(
                          color: palette.nowPlayingOnPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: palette.nowPlayingOnPrimary,
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
}

class _MonochromeDropdownOption<T> {
  final T value;
  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badgeText;

  const _MonochromeDropdownOption({
    required this.value,
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeText,
  });
}

class _MonochromeDropdownField<T> extends StatefulWidget {
  final Key dropdownKey;
  final T selectedValue;
  final String? selectedSubtitleOverride;
  final List<_MonochromeDropdownOption<T>> options;
  final ValueChanged<T> onSelected;

  const _MonochromeDropdownField({
    required this.dropdownKey,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
    this.selectedSubtitleOverride,
  });

  @override
  State<_MonochromeDropdownField<T>> createState() =>
      _MonochromeDropdownFieldState<T>();
}

class _MonochromeDropdownFieldState<T>
    extends State<_MonochromeDropdownField<T>> {
  bool _isOpen = false;

  _MonochromeDropdownOption<T> get _selectedOption {
    for (final option in widget.options) {
      if (option.value == widget.selectedValue) {
        return option;
      }
    }
    return widget.options.first;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = _selectedOption;
    final displaySubtitle =
        widget.selectedSubtitleOverride ?? selected.subtitle;

    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : 280.0;

        return Theme(
          data: Theme.of(context).copyWith(
            highlightColor: palette.nowPlayingPrimary.withValues(alpha: 0.06),
            splashColor: palette.nowPlayingPrimary.withValues(alpha: 0.08),
          ),
          child: PopupMenuButton<T>(
            key: widget.dropdownKey,
            initialValue: selected.value,
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            color: palette.surfaceCard,
            surfaceTintColor: Colors.transparent,
            elevation: 8,
            shadowColor: Colors.black.withValues(
              alpha: context.isDarkMode ? 0.55 : 0.14,
            ),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: menuWidth,
            ),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: palette.hairline, width: 0.9),
            ),
            onOpened: () => setState(() => _isOpen = true),
            onCanceled: () => setState(() => _isOpen = false),
            onSelected: (value) {
              setState(() => _isOpen = false);
              widget.onSelected(value);
            },
            itemBuilder: (menuCtx) {
              return widget.options.map((option) {
                final isSelected = option.value == selected.value;
                return PopupMenuItem<T>(
                  key: ValueKey<String>(option.keyName),
                  value: option.value,
                  height: 48,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.surfaceSubtle
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          option.icon,
                          size: 18,
                          color: isSelected
                              ? palette.nowPlayingPrimary
                              : palette.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      option.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textPrimary,
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (option.badgeText != null) ...[
                                    const SizedBox(width: 6),
                                    _buildFormatPill(
                                      palette,
                                      option.badgeText!,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 1.5),
                              Text(
                                option.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 11,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: palette.nowPlayingPrimary,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(growable: false);
            },
            child: MographSpringTap(
              pressedScale: 0.985,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isOpen
                        ? palette.nowPlayingPrimary.withValues(alpha: 0.55)
                        : palette.hairline,
                    width: _isOpen ? 1.1 : 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected.icon,
                      size: 19,
                      color: palette.nowPlayingPrimary,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  selected.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (selected.badgeText != null) ...[
                                const SizedBox(width: 6),
                                _buildFormatPill(palette, selected.badgeText!),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displaySubtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _isOpen ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: _isOpen
                            ? palette.nowPlayingPrimary
                            : palette.textMuted,
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

  Widget _buildFormatPill(MusEveePalette palette, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: palette.nowPlayingPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: palette.nowPlayingPrimary.withValues(alpha: 0.35),
          width: 0.7,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: palette.nowPlayingPrimary,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
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
          backgroundColor: palette.nowPlayingBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.hairline, width: 0.8),
          ),
          title: Text(
            AppStrings.hiResAddonAddDialogTitle,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: TextField(
            key: const ValueKey('hires_addon_url_input'),
            controller: controller,
            autofocus: true,
            cursorColor: palette.nowPlayingPrimary,
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
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: palette.hairline, width: 0.8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: palette.nowPlayingPrimary,
                  width: 1.2,
                ),
              ),
            ),
          ),
          actions: [
            MographSpringTap(
              pressedScale: 0.90,
              child: TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: Text(
                  AppStrings.hiResAddonCancelButton,
                  style: TextStyle(color: palette.textMuted, fontSize: 12.5),
                ),
              ),
            ),
            MographSpringTap(
              pressedScale: 0.94,
              child: FilledButton(
                key: const ValueKey('hires_addon_url_submit_btn'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.nowPlayingPrimary,
                  foregroundColor: palette.nowPlayingOnPrimary,
                ),
                onPressed: () =>
                    Navigator.of(dialogCtx).pop(controller.text.trim()),
                child: Text(
                  AppStrings.hiResAddonSaveButton,
                  style: TextStyle(
                    color: palette.nowPlayingOnPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
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
    SystemLocaleScope.watch(context);
    final palette = context.palette;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.84;

    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final addons = settingsProvider.hiResAddons;

        return Container(
          key: const ValueKey('hires_addon_manager_sheet'),
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          decoration: BoxDecoration(
            color: palette.nowPlayingBg,
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.hiResAddonModalTitle,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          MographSpringTap(
                            pressedScale: 0.94,
                            enabled: !_isRefreshing,
                            child: OutlinedButton.icon(
                              key: const ValueKey('hires_addon_refresh_btn'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: palette.surfaceSubtle,
                                foregroundColor: palette.nowPlayingPrimary,
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                side: BorderSide(
                                  color: palette.hairline,
                                  width: 0.8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _isRefreshing
                                  ? null
                                  : () => _refreshHealth(settingsProvider),
                              icon: _isRefreshing
                                  ? SizedBox(
                                      width: 13,
                                      height: 13,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.8,
                                        color: palette.nowPlayingPrimary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.sync_rounded,
                                      size: 15,
                                      color: palette.nowPlayingPrimary,
                                    ),
                              label: Text(
                                AppStrings.hiResAddonRefreshStatus,
                                style: TextStyle(
                                  color: palette.nowPlayingPrimary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          MographSpringTap(
                            pressedScale: 0.94,
                            child: OutlinedButton.icon(
                              key: const ValueKey('hires_addon_reset_btn'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: palette.surfaceSubtle,
                                foregroundColor: palette.textMuted,
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                side: BorderSide(
                                  color: palette.hairline,
                                  width: 0.8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () =>
                                  settingsProvider.resetAddonsToDefaultPresets(),
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
                          ),
                        ],
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
                                              ? Icons.arrow_circle_down_outlined
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

                              // Monochrome Adaptive Switch ON/OFF
                              Switch.adaptive(
                                key: ValueKey('hires_addon_switch_${addon.id}'),
                                value: addon.enabled,
                                activeThumbColor: palette.nowPlayingOnPrimary,
                                activeTrackColor: palette.nowPlayingPrimary,
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
                  child: MographSpringTap(
                    pressedScale: 0.96,
                    child: FilledButton.icon(
                      key: const ValueKey('hires_addon_add_url_btn'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.nowPlayingPrimary,
                        foregroundColor: palette.nowPlayingOnPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
