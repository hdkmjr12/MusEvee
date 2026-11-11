import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Audio quality presets for newly downloaded tracks:
/// - [hiResFlac]: 16/24-bit Lossless `.flac` via active Hi-Res Add-on sources
///   (with automatic fallback to `320 kbps` MP3 if unavailable).
/// - [best]: `320 kbps` MP3
/// - [balanced]: `192 kbps` MP3
/// - [efficient]: `128 kbps` MP3
enum DownloadQuality {
  hiResFlac(320),
  best(320),
  balanced(192),
  efficient(128);

  /// Target MP3 bitrate in kbps (for [hiResFlac], represents the fallback MP3 bitrate `320`).
  final int bitrateKbps;
  const DownloadQuality(this.bitrateKbps);

  /// Whether this quality mode requests Lossless `.flac` audio first.
  bool get isLosslessFlac => this == DownloadQuality.hiResFlac;

  /// Parses a serialized [raw] value (enum name or integer kbps) with a safe
  /// fallback to [DownloadQuality.best] (`320 kbps`).
  static DownloadQuality fromJsonValue(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'hiresflac' ||
          normalized == 'hi_res_flac' ||
          normalized == 'hires' ||
          normalized == 'flac' ||
          normalized == 'lossless') {
        return DownloadQuality.hiResFlac;
      }
      for (final value in DownloadQuality.values) {
        if (value.name.toLowerCase() == normalized) {
          return value;
        }
      }
      final asInt = int.tryParse(normalized);
      if (asInt != null) {
        return _fromBitrateInt(asInt);
      }
    } else if (raw is num) {
      return _fromBitrateInt(raw.toInt());
    }
    return DownloadQuality.best;
  }

  static DownloadQuality _fromBitrateInt(int kbps) {
    switch (kbps) {
      case 320:
        return DownloadQuality.best;
      case 192:
        return DownloadQuality.balanced;
      case 128:
        return DownloadQuality.efficient;
      default:
        return DownloadQuality.best;
    }
  }
}

/// Persistent configuration model for a single Hi-Res Lossless Add-on source.
class HiResAddonSource {
  final String id;
  final String url;
  final String name;
  final String version;
  final List<String> capabilities;
  final bool downloadsAllowed;
  final bool enabled;
  final bool? isHealthy;

  const HiResAddonSource({
    required this.id,
    required this.url,
    required this.name,
    this.version = '1.0.0',
    this.capabilities = const <String>['FLAC', 'Lossless', 'Hi-Res'],
    this.downloadsAllowed = true,
    this.enabled = true,
    this.isHealthy,
  });

  HiResAddonSource copyWith({
    String? id,
    String? url,
    String? name,
    String? version,
    List<String>? capabilities,
    bool? downloadsAllowed,
    bool? enabled,
    bool? isHealthy,
    bool clearHealth = false,
  }) {
    return HiResAddonSource(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      version: version ?? this.version,
      capabilities: capabilities ?? this.capabilities,
      downloadsAllowed: downloadsAllowed ?? this.downloadsAllowed,
      enabled: enabled ?? this.enabled,
      isHealthy: clearHealth ? null : (isHealthy ?? this.isHealthy),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'url': url,
        'name': name,
        'version': version,
        'capabilities': capabilities,
        'downloadsAllowed': downloadsAllowed,
        'enabled': enabled,
        if (isHealthy != null) 'isHealthy': isHealthy,
      };

  factory HiResAddonSource.fromJson(Map<dynamic, dynamic> json) {
    final rawUrl = (json['url'] ?? '').toString().trim();
    final rawId = (json['id'] ?? '').toString().trim();
    final rawName = (json['name'] ?? '').toString().trim();
    final rawVersion = (json['version'] ?? '1.0.0').toString().trim();
    final rawCaps = json['capabilities'];
    final caps = <String>[];
    if (rawCaps is List) {
      for (final item in rawCaps) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty) caps.add(s);
      }
    }
    if (caps.isEmpty) {
      caps.addAll(const <String>['FLAC', 'Lossless', 'Hi-Res']);
    }
    return HiResAddonSource(
      id: rawId.isNotEmpty ? rawId : SettingsProvider.addonIdFromUrl(rawUrl),
      url: rawUrl,
      name: rawName.isNotEmpty
          ? rawName
          : SettingsProvider.inferAddonDisplayName(rawUrl),
      version: rawVersion.isNotEmpty ? rawVersion : '1.0.0',
      capabilities: List<String>.unmodifiable(caps),
      downloadsAllowed: json['downloadsAllowed'] != false,
      enabled: json['enabled'] != false,
      isHealthy: json['isHealthy'] is bool ? json['isHealthy'] as bool : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiResAddonSource &&
          id == other.id &&
          url == other.url &&
          name == other.name &&
          version == other.version &&
          downloadsAllowed == other.downloadsAllowed &&
          enabled == other.enabled &&
          isHealthy == other.isHealthy;

  @override
  int get hashCode => Object.hash(
        id,
        url,
        name,
        version,
        downloadsAllowed,
        enabled,
        isHealthy,
      );
}

/// Persistent application settings stored in `musevee_settings_v1.json` inside
/// the application documents directory (and mirrored to
/// `/storage/emulated/0/Music/.musevee_state/musevee_settings_v1.json` on Android).
class SettingsProvider extends ChangeNotifier {
  static const String settingsFileName = 'musevee_settings_v1.json';
  static const String _externalBackupDirPath =
      '/storage/emulated/0/Music/.musevee_state';

  /// Built-in default Hi-Res Add-on presets (all enabled by default).
  /// Includes the active Monochrome Lossless API (`https://tracks.monochrome.st`)
  /// at priority #1 alongside the 7 community BitChord add-on URLs.
  static const List<HiResAddonSource> defaultHiResAddonPresets =
      <HiResAddonSource>[
    HiResAddonSource(
      id: 'preset_monochrome_tracks',
      url: 'https://tracks.monochrome.st',
      name: 'Monochrome [Qobuz · Tidal]',
      version: '2.10',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_bitchord_vercel',
      url: 'https://bit-chord-addon.vercel.app',
      name: 'Qobuz [Heisenbergg]',
      version: '1.0.0-de',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_aurix_auto',
      url: 'https://addon-2.aurix.dpdns.org/free_rLnRPnC6oZF5gvAx',
      name: 'Aurix · Auto',
      version: '1.9.18',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: false,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_eljohnzc_addon',
      url: 'https://eljohnzc-addon.de.deplexo.com/59efe06a96',
      name: 'Eljohnzc Addon',
      version: '5.5.5',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_bitchord_hires_deplexo',
      url: 'https://bitchord-hires-addon.de.deplexo.com',
      name: 'juanjob hi res',
      version: '1.2.1',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_soundfean_musics',
      url: 'https://soundfean-musics.onrender.com/a',
      name: 'Soundfean Musics',
      version: '1.0.0',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_eljohnzc_mono',
      url: 'https://eljohnzc-mono.de.deplexo.com',
      name: 'Eljohnzc Mono',
      version: '1.0.0',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
    HiResAddonSource(
      id: 'preset_8spine_modules',
      url: 'https://8spine-modules.vercel.app/index.json',
      name: '8spine Modules Index',
      version: '1.0.0',
      capabilities: <String>['FLAC', 'Lossless', 'Hi-Res'],
      downloadsAllowed: true,
      enabled: true,
    ),
  ];

  static String normalizeAddonUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    while (trimmed.endsWith('/') && !trimmed.endsWith('://')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String addonIdFromUrl(String rawUrl) {
    final norm = normalizeAddonUrl(rawUrl).toLowerCase();
    for (final preset in defaultHiResAddonPresets) {
      if (normalizeAddonUrl(preset.url).toLowerCase() == norm) {
        return preset.id;
      }
    }
    final sanitized = norm.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'addon_${sanitized.isNotEmpty ? sanitized : norm.hashCode.abs()}';
  }

  static String inferAddonDisplayName(String rawUrl) {
    final norm = normalizeAddonUrl(rawUrl).toLowerCase();
    for (final preset in defaultHiResAddonPresets) {
      if (normalizeAddonUrl(preset.url).toLowerCase() == norm) {
        return preset.name;
      }
    }
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri != null && uri.host.isNotEmpty) {
      final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      final firstLabel = host.split('.').first;
      if (firstLabel.isNotEmpty) {
        return firstLabel[0].toUpperCase() + firstLabel.substring(1);
      }
      return host;
    }
    return 'Custom Add-on';
  }

  final Directory? _storageDirectory;
  final Future<Directory> Function()? _directoryResolver;
  final File? _settingsFileOverride;

  DownloadQuality _downloadQuality = DownloadQuality.best;
  ThemeMode _themeMode = ThemeMode.dark;
  List<HiResAddonSource> _hiResAddons = List<HiResAddonSource>.from(
    defaultHiResAddonPresets,
  );
  bool _hasUserModifiedQuality = false;
  bool _hasUserModifiedTheme = false;
  bool _hasUserModifiedAddons = false;
  bool _isDisposed = false;
  late final Future<void> _initFuture;

  SettingsProvider({
    Directory? storageDirectory,
    Future<Directory> Function()? directoryResolver,
    File? settingsFile,
    ThemeMode initialThemeMode = ThemeMode.dark,
  })  : _storageDirectory = storageDirectory,
        _directoryResolver = directoryResolver,
        _settingsFileOverride = settingsFile,
        _themeMode =
            initialThemeMode == ThemeMode.light
                ? ThemeMode.light
                : ThemeMode.dark {
    _initFuture = _loadFromDisk();
  }

  /// Active download quality setting (defaults to [DownloadQuality.best] = 320 kbps).
  DownloadQuality get downloadQuality => _downloadQuality;

  /// Active theme mode (`ThemeMode.dark` or `ThemeMode.light`, defaults to `ThemeMode.dark`).
  ThemeMode get themeMode => _themeMode;

  /// Whether the active theme is Dark Mode.
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  /// Convenience getter for the active MP3 encoding bitrate in kbps (`320`, `192`, or `128`).
  int get downloadBitrateKbps => _downloadQuality.bitrateKbps;

  /// Ordered list of configured Hi-Res Add-on sources (tried from top to bottom).
  List<HiResAddonSource> get hiResAddons =>
      List<HiResAddonSource>.unmodifiable(_hiResAddons);

  /// Ordered list of currently enabled Hi-Res Add-on sources.
  List<HiResAddonSource> get enabledHiResAddons =>
      List<HiResAddonSource>.unmodifiable(
        _hiResAddons.where((addon) => addon.enabled),
      );

  /// Count of currently enabled Hi-Res Add-on sources.
  int get enabledHiResAddonsCount =>
      _hiResAddons.where((addon) => addon.enabled).length;

  /// Completes once the initial asynchronous load from `musevee_settings_v1.json` finishes.
  Future<void> get initialized => _initFuture;

  set downloadQuality(DownloadQuality quality) {
    unawaited(setDownloadQuality(quality));
  }

  set themeMode(ThemeMode mode) {
    unawaited(setThemeMode(mode));
  }

  static ThemeMode parseThemeMode(Object? raw) {
    if (raw is String && raw.trim().toLowerCase() == 'light') {
      return ThemeMode.light;
    }
    return ThemeMode.dark;
  }

  /// Updates [downloadQuality], notifies listeners immediately, and persists
  /// the choice to `musevee_settings_v1.json`.
  Future<void> setDownloadQuality(DownloadQuality quality) async {
    _hasUserModifiedQuality = true;
    final changed = _downloadQuality != quality;
    _downloadQuality = quality;
    if (changed) {
      _safeNotifyListeners();
    }
    await _saveToDisk();
  }

  /// Updates [themeMode] (`ThemeMode.dark` or `ThemeMode.light`), notifies
  /// listeners immediately, and persists the choice to `musevee_settings_v1.json`.
  Future<void> setThemeMode(ThemeMode mode) async {
    final resolved =
        mode == ThemeMode.light ? ThemeMode.light : ThemeMode.dark;
    _hasUserModifiedTheme = true;
    final changed = _themeMode != resolved;
    _themeMode = resolved;
    if (changed) {
      _safeNotifyListeners();
    }
    await _saveToDisk();
  }

  /// Toggles the [enabled] state of an add-on identified by [idOrUrl].
  Future<void> toggleAddonEnabled(String idOrUrl, [bool? enabled]) async {
    final key = idOrUrl.trim().toLowerCase();
    final normUrl = normalizeAddonUrl(idOrUrl).toLowerCase();
    var changed = false;
    final updated = <HiResAddonSource>[];
    for (final addon in _hiResAddons) {
      if (addon.id.toLowerCase() == key ||
          normalizeAddonUrl(addon.url).toLowerCase() == normUrl) {
        final targetEnabled = enabled ?? !addon.enabled;
        if (addon.enabled != targetEnabled) {
          changed = true;
        }
        updated.add(addon.copyWith(enabled: targetEnabled));
      } else {
        updated.add(addon);
      }
    }
    if (!changed) return;
    _hasUserModifiedAddons = true;
    _hiResAddons = updated;
    _safeNotifyListeners();
    await _saveToDisk();
  }

  /// Reorders the priority of add-on sources (`ReorderableListView` convention:
  /// if `newIndex > oldIndex`, `newIndex` is decremented by 1 unless [rawIndex] is true).
  Future<void> reorderAddons(
    int oldIndex,
    int newIndex, {
    bool rawIndex = false,
  }) async {
    if (oldIndex < 0 || oldIndex >= _hiResAddons.length) return;
    var targetIndex = newIndex;
    if (!rawIndex && targetIndex > oldIndex) {
      targetIndex -= 1;
    }
    targetIndex = targetIndex.clamp(0, _hiResAddons.length - 1);
    if (oldIndex == targetIndex) return;

    _hasUserModifiedAddons = true;
    final next = List<HiResAddonSource>.from(_hiResAddons);
    final moved = next.removeAt(oldIndex);
    next.insert(targetIndex, moved);
    _hiResAddons = next;
    _safeNotifyListeners();
    await _saveToDisk();
  }

  /// Adds a new add-on URL (or updates its metadata if the URL is already present).
  /// Returns the added/updated [HiResAddonSource], or `null` if [rawUrl] is invalid.
  Future<HiResAddonSource?> addAddonUrl(
    String rawUrl, {
    HiResAddonSource? resolvedSource,
  }) async {
    final cleaned = normalizeAddonUrl(rawUrl);
    if (cleaned.isEmpty) return null;
    final uri = Uri.tryParse(cleaned);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }

    _hasUserModifiedAddons = true;
    final normTarget = cleaned.toLowerCase();
    final existingIdx = _hiResAddons.indexWhere(
      (a) => normalizeAddonUrl(a.url).toLowerCase() == normTarget,
    );

    final entry = resolvedSource?.copyWith(url: cleaned) ??
        HiResAddonSource(
          id: addonIdFromUrl(cleaned),
          url: cleaned,
          name: inferAddonDisplayName(cleaned),
          version: '1.0.0',
          capabilities: const <String>['FLAC', 'Lossless', 'Hi-Res'],
          downloadsAllowed: true,
          enabled: true,
        );

    final next = List<HiResAddonSource>.from(_hiResAddons);
    if (existingIdx != -1) {
      next[existingIdx] = entry.copyWith(enabled: true);
    } else {
      next.add(entry);
    }
    _hiResAddons = next;
    _safeNotifyListeners();
    await _saveToDisk();
    return entry;
  }

  /// Merges discovered sub-modules (e.g. from an `index.json` catalog) without
  /// duplicating existing URLs.
  Future<void> addOrMergeAddons(List<HiResAddonSource> discovered) async {
    if (discovered.isEmpty) return;
    _hasUserModifiedAddons = true;
    final next = List<HiResAddonSource>.from(_hiResAddons);
    var changed = false;

    for (final candidate in discovered) {
      final cleanedUrl = normalizeAddonUrl(candidate.url);
      if (cleanedUrl.isEmpty) continue;
      final normUrl = cleanedUrl.toLowerCase();
      final idx = next.indexWhere(
        (a) => normalizeAddonUrl(a.url).toLowerCase() == normUrl,
      );
      if (idx != -1) {
        final prev = next[idx];
        final updated = prev.copyWith(
          name: candidate.name.isNotEmpty ? candidate.name : prev.name,
          version:
              candidate.version.isNotEmpty ? candidate.version : prev.version,
          capabilities: candidate.capabilities.isNotEmpty
              ? candidate.capabilities
              : prev.capabilities,
          downloadsAllowed: candidate.downloadsAllowed,
          isHealthy: candidate.isHealthy ?? prev.isHealthy,
        );
        if (updated != prev) {
          next[idx] = updated;
          changed = true;
        }
      } else {
        next.add(candidate.copyWith(url: cleanedUrl));
        changed = true;
      }
    }

    if (!changed) return;
    _hiResAddons = next;
    _safeNotifyListeners();
    await _saveToDisk();
  }

  /// Updates a single [HiResAddonSource] in-place (e.g. after health/manifest inspection).
  Future<void> updateAddonSource(HiResAddonSource updated) async {
    final normUrl = normalizeAddonUrl(updated.url).toLowerCase();
    final idx = _hiResAddons.indexWhere(
      (a) =>
          a.id == updated.id ||
          normalizeAddonUrl(a.url).toLowerCase() == normUrl,
    );
    if (idx == -1) return;
    if (_hiResAddons[idx] == updated) return;
    final next = List<HiResAddonSource>.from(_hiResAddons);
    next[idx] = updated;
    _hiResAddons = next;
    _safeNotifyListeners();
    await _saveToDisk();
  }

  /// Replaces the entire add-on list (e.g. after a batch health refresh).
  Future<void> replaceAllAddons(List<HiResAddonSource> next) async {
    _hasUserModifiedAddons = true;
    _hiResAddons = List<HiResAddonSource>.from(next);
    _safeNotifyListeners();
    await _saveToDisk();
  }

  /// Removes an add-on source by [idOrUrl].
  Future<void> removeAddon(String idOrUrl) async {
    final key = idOrUrl.trim().toLowerCase();
    final normUrl = normalizeAddonUrl(idOrUrl).toLowerCase();
    final next = _hiResAddons
        .where(
          (a) =>
              a.id.toLowerCase() != key &&
              normalizeAddonUrl(a.url).toLowerCase() != normUrl,
        )
        .toList();
    if (next.length == _hiResAddons.length) return;
    _hasUserModifiedAddons = true;
    _hiResAddons = next;
    _safeNotifyListeners();
    await _saveToDisk();
  }

  /// Resets the add-on sources list back to [defaultHiResAddonPresets] (all enabled).
  Future<void> resetAddonsToDefaultPresets() async {
    _hasUserModifiedAddons = true;
    _hiResAddons = List<HiResAddonSource>.from(defaultHiResAddonPresets);
    _safeNotifyListeners();
    await _saveToDisk();
  }

  bool get _canUseExternalBackup =>
      Platform.isAndroid &&
      _settingsFileOverride == null &&
      _storageDirectory == null &&
      _directoryResolver == null;

  Future<File> _resolveSettingsFile() async {
    final overrideFile = _settingsFileOverride;
    if (overrideFile != null) {
      return overrideFile;
    }
    final storageDir = _storageDirectory;
    if (storageDir != null) {
      return File(
        '${storageDir.path}${Platform.pathSeparator}$settingsFileName',
      );
    }
    final resolver = _directoryResolver;
    if (resolver != null) {
      final dir = await resolver();
      return File('${dir.path}${Platform.pathSeparator}$settingsFileName');
    }
    final docsDir = await getApplicationDocumentsDirectory();
    return File('${docsDir.path}${Platform.pathSeparator}$settingsFileName');
  }

  Future<void> _loadFromDisk() async {
    try {
      var file = await _resolveSettingsFile();
      if (!await file.exists() && _canUseExternalBackup) {
        final backupFile = File(
          '$_externalBackupDirPath${Platform.pathSeparator}$settingsFileName',
        );
        if (await backupFile.exists()) {
          file = backupFile;
        }
      }
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        var changed = false;
        if (!_hasUserModifiedQuality) {
          final parsed = DownloadQuality.fromJsonValue(
            decoded['downloadQuality'] ?? decoded['bitrateKbps'],
          );
          if (_downloadQuality != parsed) {
            _downloadQuality = parsed;
            changed = true;
          }
        }
        if (!_hasUserModifiedTheme) {
          final parsedTheme = parseThemeMode(decoded['themeMode']);
          if (_themeMode != parsedTheme) {
            _themeMode = parsedTheme;
            changed = true;
          }
        }
        if (!_hasUserModifiedAddons && decoded['hiResAddons'] is List) {
          final rawList = decoded['hiResAddons'] as List;
          final parsedAddons = <HiResAddonSource>[];
          final seenUrls = <String>{};
          for (final item in rawList) {
            if (item is Map) {
              final src = HiResAddonSource.fromJson(item);
              final norm = normalizeAddonUrl(src.url).toLowerCase();
              if (norm.isNotEmpty && seenUrls.add(norm)) {
                parsedAddons.add(src);
              }
            }
          }
          if (parsedAddons.isNotEmpty) {
            _hiResAddons = parsedAddons;
            changed = true;
          }
        }
        if (changed) {
          _safeNotifyListeners();
        }
      }
    } catch (_) {
      // Corrupted or inaccessible file -> safely retain default settings
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _resolveSettingsFile();
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final payload = <String, dynamic>{
        'version': 2,
        'downloadQuality': _downloadQuality.name,
        'bitrateKbps': _downloadQuality.bitrateKbps,
        'themeMode': _themeMode == ThemeMode.light ? 'light' : 'dark',
        'hiResAddons': _hiResAddons.map((a) => a.toJson()).toList(),
      };
      final encoded = jsonEncode(payload);
      await file.writeAsString(encoded, flush: true);

      if (_canUseExternalBackup) {
        try {
          final backupDir = Directory(_externalBackupDirPath);
          if (!await backupDir.exists()) {
            await backupDir.create(recursive: true);
          }
          final backupFile = File(
            '$_externalBackupDirPath${Platform.pathSeparator}$settingsFileName',
          );
          await backupFile.writeAsString(encoded, flush: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
