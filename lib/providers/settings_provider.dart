import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Audio bitrate presets for newly downloaded MP3 files.
enum DownloadQuality {
  best(320),
  balanced(192),
  efficient(128);

  final int bitrateKbps;
  const DownloadQuality(this.bitrateKbps);

  /// Parses a serialized [raw] value (enum name or integer kbps) with a safe
  /// fallback to [DownloadQuality.best] (`320 kbps`).
  static DownloadQuality fromJsonValue(Object? raw) {
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      for (final value in DownloadQuality.values) {
        if (value.name.toLowerCase() == normalized) {
          return value;
        }
      }
    } else if (raw is num) {
      final kbps = raw.toInt();
      for (final value in DownloadQuality.values) {
        if (value.bitrateKbps == kbps) {
          return value;
        }
      }
    }
    return DownloadQuality.best;
  }
}

/// Persistent application settings stored in `musevee_settings_v1.json` inside
/// the application documents directory (following MusEvee's JSON state pattern
/// without adding external preferences dependencies).
class SettingsProvider extends ChangeNotifier {
  static const String settingsFileName = 'musevee_settings_v1.json';

  final Directory? _storageDirectory;
  final Future<Directory> Function()? _directoryResolver;
  final File? _settingsFileOverride;

  DownloadQuality _downloadQuality = DownloadQuality.best;
  ThemeMode _themeMode = ThemeMode.dark;
  bool _hasUserModifiedQuality = false;
  bool _hasUserModifiedTheme = false;
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
      final file = await _resolveSettingsFile();
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
        if (changed) {
          _safeNotifyListeners();
        }
      }
    } catch (_) {
      // Corrupted or inaccessible file -> safely retain default (DownloadQuality.best, ThemeMode.dark)
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _resolveSettingsFile();
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final payload = <String, dynamic>{
        'version': 1,
        'downloadQuality': _downloadQuality.name,
        'bitrateKbps': _downloadQuality.bitrateKbps,
        'themeMode': _themeMode == ThemeMode.light ? 'light' : 'dark',
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
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
