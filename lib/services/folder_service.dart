import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track_metadata.dart';
import '../utils/app_strings.dart';

class BrowsedDirectoryEntry {
  final String name;
  final String path;
  final int audioCount;

  const BrowsedDirectoryEntry({
    required this.name,
    required this.path,
    required this.audioCount,
  });

  int get mp3Count => audioCount;
}

class FolderService {
  static const String baseStorageRoot = '/storage/emulated/0';
  static const String baseMusicRoot = '/storage/emulated/0/Music';
  static const String fallbackDownloadRoot = '/storage/emulated/0/Download';
  static const String defaultNeutralFolder = 'MusEvee';
  static const String customFoldersFileName = 'musevee_custom_folders_v1.json';

  static const List<String> defaultFolders = [
    'Music Barat',
    'Music Japan',
    'Music Random',
  ];

  static const MethodChannel _systemChannel =
      MethodChannel('com.spotmeta.downloader/system');

  /// Checks whether the app currently holds `MANAGE_EXTERNAL_STORAGE` on Android 11+.
  Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'hasAllFilesAccess',
      );
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "All files access" page for MusEvee on Android 11–15 and awaits return.
  Future<bool> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'requestAllFilesAccess',
      );
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether `POST_NOTIFICATIONS` / system notifications are enabled for MusEvee.
  Future<bool> hasNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'hasNotificationPermission',
      );
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Requests `POST_NOTIFICATIONS` (Android 13+) or opens the app notification settings page.
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system App Notification Settings page for MusEvee.
  Future<bool> openNotificationSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _systemChannel.invokeMethod<bool>(
        'openNotificationSettings',
      );
      return granted == true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches combined permission status (`hasAllFilesAccess`, `hasNotificationPermission`, `packageName`, `sdkInt`).
  Future<Map<String, dynamic>> getPermissionsStatus() async {
    if (!Platform.isAndroid) {
      return const {
        'hasAllFilesAccess': true,
        'hasNotificationPermission': true,
        'packageName': 'com.zte.as.music',
        'sdkInt': 35,
      };
    }
    try {
      final raw = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getPermissionsStatus',
      );
      if (raw != null) {
        return {
          'hasAllFilesAccess': raw['hasAllFilesAccess'] == true,
          'hasNotificationPermission': raw['hasNotificationPermission'] == true,
          'packageName': raw['packageName']?.toString() ?? 'com.zte.as.music',
          'sdkInt': (raw['sdkInt'] as num?)?.toInt() ?? 35,
        };
      }
    } catch (_) {}
    final allFiles = await hasAllFilesAccess();
    final notif = await hasNotificationPermission();
    return {
      'hasAllFilesAccess': allFiles,
      'hasNotificationPermission': notif,
      'packageName': 'com.zte.as.music',
      'sdkInt': 35,
    };
  }

  static const Set<String> _excludedSystemFolderNames = {
    'ringtones_music',
    'ringtones',
    'alarms',
    'notifications',
    'ui',
    '.thumbnails',
    '.musevee_state',
    'whatsapp audio',
    'voice notes',
    'recordings',
    'callrecord',
    'soundrecorder',
  };

  static const int _minValidMusicBytes = 16384;

  /// Lists existing target folders under `/storage/emulated/0/Music/` WITHOUT
  /// forcibly creating empty `Music Barat`, `Music Japan`, or `Music Random` folders.
  /// - If `Music Barat`, `Music Japan`, or `Music Random` already exist on the device,
  ///   they appear first in their familiar order, followed by any other existing subdirectories.
  /// - If a new user's device has no subdirectories in `/storage/emulated/0/Music/` yet,
  ///   returns a single neutral target folder (`MusEvee`).
  Future<List<String>> listAvailableFolders() async {
    if (!Platform.isAndroid) {
      return const [defaultNeutralFolder];
    }

    final discoveredByLower = <String, String>{};
    try {
      final musicDir = Directory(baseMusicRoot);
      if (await musicDir.exists()) {
        final entries = await musicDir.list(followLinks: false).toList();
        for (final entity in entries) {
          if (entity is Directory) {
            final name = entity.path
                .split(Platform.pathSeparator)
                .where((s) => s.isNotEmpty)
                .last
                .trim();
            final lower = name.toLowerCase();
            if (name.isEmpty ||
                name.startsWith('.') ||
                _excludedSystemFolderNames.contains(lower)) {
              continue;
            }
            discoveredByLower.putIfAbsent(lower, () => name);
          }
        }
      }
    } catch (e) {
      debugPrint('[AUTO_E2E] FolderService.listAvailableFolders error: $e');
    }

    if (discoveredByLower.isEmpty) {
      return [defaultNeutralFolder];
    }

    final ordered = <String>[];
    for (final preferred in defaultFolders) {
      final matched = discoveredByLower.remove(preferred.toLowerCase());
      if (matched != null) {
        ordered.add(matched);
      }
    }

    final extraFolders = discoveredByLower.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    ordered.addAll(extraFolders);

    // Merge user-saved custom folders (`musevee_custom_folders_v1.json`)
    try {
      final savedCustom = await loadCustomSavedFolders();
      final existingLower = ordered.map((e) => e.toLowerCase()).toSet();
      for (final custom in savedCustom) {
        if (custom.isNotEmpty && existingLower.add(custom.toLowerCase())) {
          ordered.add(custom);
        }
      }
    } catch (_) {}

    return ordered.isNotEmpty ? ordered : [defaultNeutralFolder];
  }

  /// Resolves a folder target (e.g. `'Music Barat'`, `'Music'`, or a custom path
  /// `'/storage/emulated/0/...'`) to its physical directory path on Android storage.
  String resolveFolderDirectoryPath(String folderTarget) {
    final trimmed = folderTarget.trim().replaceAll('\\', '/');
    if (trimmed.isEmpty) {
      return '$baseMusicRoot/$defaultNeutralFolder';
    }
    var noTrailing = trimmed;
    while (noTrailing.length > 1 && noTrailing.endsWith('/')) {
      noTrailing = noTrailing.substring(0, noTrailing.length - 1);
    }
    if (noTrailing.toLowerCase() == 'music' ||
        noTrailing.toLowerCase() == baseMusicRoot.toLowerCase()) {
      return baseMusicRoot;
    }
    if (noTrailing.startsWith('/storage/')) {
      return noTrailing;
    }
    if (noTrailing.contains('/')) {
      final segments = noTrailing
          .split('/')
          .map(sanitizeFolderName)
          .where((s) => s.isNotEmpty)
          .join('/');
      return '$baseMusicRoot/$segments';
    }
    return '$baseMusicRoot/${sanitizeFolderName(noTrailing)}';
  }

  /// Converts a selected directory path or name into a concise folder token
  /// for the "Simpan ke:" chip bar.
  String normalizePickedFolderTarget(String rawPathOrName) {
    var cleaned = rawPathOrName.trim().replaceAll('\\', '/');
    while (cleaned.length > 1 && cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty) return defaultNeutralFolder;
    final musicPrefix = '${baseMusicRoot.toLowerCase()}/';
    if (cleaned.toLowerCase() == baseMusicRoot.toLowerCase() ||
        cleaned.toLowerCase() == 'music') {
      return 'Music';
    }
    if (cleaned.toLowerCase().startsWith(musicPrefix)) {
      return cleaned.substring(baseMusicRoot.length + 1).trim();
    }
    if (cleaned.startsWith('/storage/')) {
      return cleaned;
    }
    return sanitizeFolderName(cleaned);
  }

  /// Human-friendly label for a folder chip in "Simpan ke:".
  static String displayFolderChipLabel(String folderTarget) {
    final trimmed = folderTarget.trim().replaceAll('\\', '/');
    if (trimmed.toLowerCase() == 'music' ||
        trimmed.toLowerCase() == baseMusicRoot.toLowerCase()) {
      return 'Music (Utama)';
    }
    if (trimmed.toLowerCase().startsWith('${baseStorageRoot.toLowerCase()}/')) {
      return trimmed.substring(baseStorageRoot.length + 1);
    }
    return trimmed;
  }

  /// Launches Android's system directory picker (`Intent.ACTION_OPEN_DOCUMENT_TREE`)
  /// and returns the selected folder target (or `null` if cancelled).
  Future<String?> pickSystemDirectoryTree() async {
    if (!Platform.isAndroid) return null;
    try {
      final pickedPath = await _systemChannel.invokeMethod<String>(
        'pickDirectoryTree',
      );
      if (pickedPath == null || pickedPath.trim().isEmpty) return null;
      final normalized = normalizePickedFolderTarget(pickedPath);
      await saveCustomFolder(normalized);
      return normalized;
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` if [pathOrName] ends with `.mp3` or `.flac` (case-insensitive).
  static bool isSupportedAudioFilePath(String pathOrName) {
    final lower = pathOrName.trim().toLowerCase();
    return lower.endsWith('.mp3') || lower.endsWith('.flac');
  }

  /// Strips `.mp3` or `.flac` extension from [fileName] (case-insensitive).
  static String stripAudioExtension(String fileName) {
    final trimmed = fileName.trim();
    final lower = trimmed.toLowerCase();
    if (lower.endsWith('.flac')) {
      return trimmed.substring(0, trimmed.length - 5);
    }
    if (lower.endsWith('.mp3')) {
      return trimmed.substring(0, trimmed.length - 4);
    }
    return trimmed;
  }

  /// Lists subdirectories inside [parentPath] (defaults to `/storage/emulated/0/Music`)
  /// for the in-app Interactive Folder Picker / Explorer modal.
  Future<List<BrowsedDirectoryEntry>> browseStorageDirectories(
    String parentPath,
  ) async {
    if (!Platform.isAndroid) return const <BrowsedDirectoryEntry>[];
    final entries = <BrowsedDirectoryEntry>[];
    try {
      final dir = Directory(parentPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final rawList = await dir.list(followLinks: false).toList();
      for (final entity in rawList) {
        if (entity is! Directory) continue;
        final name = entity.path
            .replaceAll('\\', '/')
            .split('/')
            .where((s) => s.isNotEmpty)
            .last
            .trim();
        final lower = name.toLowerCase();
        if (name.isEmpty ||
            name.startsWith('.') ||
            lower == 'android' ||
            _excludedSystemFolderNames.contains(lower)) {
          continue;
        }
        int audioCount = 0;
        try {
          await for (final child in entity.list(followLinks: false)) {
            if (child is File && isSupportedAudioFilePath(child.path)) {
              audioCount++;
            }
          }
        } catch (_) {}
        entries.add(
          BrowsedDirectoryEntry(
            name: name,
            path: entity.path.replaceAll('\\', '/'),
            audioCount: audioCount,
          ),
        );
      }
      entries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } catch (_) {}
    return entries;
  }

  Future<List<String>> loadCustomSavedFolders() async {
    if (!Platform.isAndroid) return const <String>[];
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final f = File(
        '${docsDir.path}${Platform.pathSeparator}$customFoldersFileName',
      );
      if (!await f.exists()) return const <String>[];
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<void> saveCustomFolder(String folderTarget) async {
    if (!Platform.isAndroid) return;
    final normalized = normalizePickedFolderTarget(folderTarget);
    if (normalized.isEmpty) return;
    try {
      final current = List<String>.from(await loadCustomSavedFolders());
      if (!current.any((f) => f.toLowerCase() == normalized.toLowerCase())) {
        current.add(normalized);
      }
      final docsDir = await getApplicationDocumentsDirectory();
      final f = File(
        '${docsDir.path}${Platform.pathSeparator}$customFoldersFileName',
      );
      await f.writeAsString(jsonEncode(current), flush: true);
    } catch (_) {}
  }

  /// Creates a new subfolder inside [parentDirPath] (defaults to `/storage/emulated/0/Music`),
  /// persists it in `musevee_custom_folders_v1.json`, and returns its normalized target name.
  Future<String> createCustomFolder(
    String rawName, {
    String? parentDirPath,
  }) async {
    final cleaned = sanitizeFolderName(rawName);
    if (cleaned.isEmpty) {
      throw Exception(AppStrings.svcFolderNameEmpty);
    }

    final baseDir = (parentDirPath != null && parentDirPath.trim().isNotEmpty)
        ? parentDirPath.trim().replaceAll('\\', '/')
        : baseMusicRoot;
    final fullPath = '$baseDir/$cleaned';

    if (Platform.isAndroid) {
      try {
        final dir = Directory(fullPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (e) {
        debugPrint('[AUTO_E2E] Gagal membuat folder di $fullPath: $e');
      }
    }

    final normalized = normalizePickedFolderTarget(fullPath);
    await saveCustomFolder(normalized);
    return normalized;
  }

  /// Reads the last selected folder from local app storage, or returns `''` if none saved yet.
  Future<String> loadLastSelectedFolder() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final prefFile = File(
        '${docsDir.path}${Platform.pathSeparator}last_selected_folder.txt',
      );
      if (await prefFile.exists()) {
        final saved = (await prefFile.readAsString()).trim();
        if (saved.isNotEmpty) {
          return saved;
        }
      }
    } catch (_) {}
    return '';
  }

  /// Saves the selected folder so it persists across sessions.
  Future<void> saveLastSelectedFolder(String folderName) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final prefFile = File(
        '${docsDir.path}${Platform.pathSeparator}last_selected_folder.txt',
      );
      await prefFile.writeAsString(folderName.trim(), flush: true);
    } catch (_) {}
  }

  /// Checks whether [fileName] (e.g. `Artist - Title.mp3` or `.flac`) already exists inside
  /// any of the [folders] under `/storage/emulated/0/Music/`.
  /// Returns the folder name where it was found, or `null` if not found.
  Future<String?> findDuplicateFolder(
    String fileName,
    List<String> folders,
  ) async {
    if (!Platform.isAndroid) return null;
    final batch = await findDuplicateFoldersBatch([fileName], folders);
    return batch[fileName.toLowerCase()];
  }

  /// Scans each folder in [folders] at most once and returns a map of
  /// lowercase filename (`track.sanitizedFileName.toLowerCase()`) -> matching folder.
  Future<Map<String, String>> findDuplicateFoldersBatch(
    List<String> fileNames,
    List<String> folders,
  ) async {
    if (!Platform.isAndroid || fileNames.isEmpty || folders.isEmpty) {
      return const {};
    }
    final dirs = <String, Directory>{
      for (final folder in folders)
        folder: Directory(resolveFolderDirectoryPath(folder)),
    };
    return findDuplicateFoldersBatchInDirectories(fileNames, dirs);
  }

  @visibleForTesting
  Future<Map<String, String>> findDuplicateFoldersBatchInDirectories(
    List<String> fileNames,
    Map<String, Directory> folderDirectories,
  ) async {
    if (fileNames.isEmpty || folderDirectories.isEmpty) {
      return const {};
    }

    // Group target lowercase filenames by their stripped audio base stem so
    // multiple targets with the same stem resolve cleanly in O(1).
    final stemToKeys = <String, List<String>>{};
    final allTargetKeys = <String>{};
    for (final rawName in fileNames) {
      final targetLower = rawName.toLowerCase();
      if (!allTargetKeys.add(targetLower)) continue;
      final baseWithoutExt = stripAudioExtension(targetLower);
      if (baseWithoutExt.isEmpty) continue;
      stemToKeys.putIfAbsent(baseWithoutExt, () => <String>[]).add(targetLower);
    }

    if (allTargetKeys.isEmpty) return const {};

    final results = <String, String>{};

    for (final entry in folderDirectories.entries) {
      if (results.length >= allTargetKeys.length) break;
      final folder = entry.key;
      final dir = entry.value;
      try {
        if (!await dir.exists()) continue;

        await for (final entity in dir.list(followLinks: false)) {
          if (results.length >= allTargetKeys.length) break;
          if (entity is! File) continue;

          final name =
              entity.path.split(Platform.pathSeparator).last.toLowerCase();
          if (!isSupportedAudioFilePath(name)) continue;

          final entityBase = stripAudioExtension(name);
          final matchedKeys = <String>[];

          final exactStemKeys = stemToKeys[entityBase];
          if (exactStemKeys != null) {
            matchedKeys.addAll(exactStemKeys);
          }

          // Match numbered duplicates such as `artist - song (1).mp3`
          // identically to `entityBase.startsWith('$baseWithoutExt (')`.
          var parenIdx = entityBase.indexOf(' (');
          while (parenIdx != -1) {
            final prefix = entityBase.substring(0, parenIdx);
            final prefixKeys = stemToKeys[prefix];
            if (prefixKeys != null) {
              matchedKeys.addAll(prefixKeys);
            }
            parenIdx = entityBase.indexOf(' (', parenIdx + 2);
          }

          if (matchedKeys.isEmpty) continue;

          final unmappedKeys = matchedKeys
              .where((k) => !results.containsKey(k))
              .toList(growable: false);
          if (unmappedKeys.isEmpty) continue;

          if (await entity.length() >= _minValidMusicBytes) {
            for (final key in unmappedKeys) {
              results[key] = folder;
            }
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// Checks across all [folders] (plus any extra subdirectories in `/storage/emulated/0/Music/`)
  /// whether an `.mp3` or `.flac` matching [track] already exists on disk (by exact filename OR
  /// normalized `Artist - Title` stem) and returns its full file path if found.
  Future<String?> checkDuplicateAcrossFolders(
    TrackMetadata track,
    List<String> folders,
  ) async {
    if (!Platform.isAndroid) return null;

    final allFolders = <String>{...folders};
    try {
      final discovered = await listAvailableFolders();
      allFolders.addAll(discovered);
    } catch (_) {}

    final targetFileLower = track.sanitizedFileName.toLowerCase();
    final targetFlacLower = track.sanitizedFlacFileName.toLowerCase();
    final baseWithoutExt = stripAudioExtension(targetFileLower);
    final targetIdentity = TrackMetadata.normalizeTrackIdentity(
      track.title,
      track.artist,
    );
    final targetCombined = TrackMetadata.normalizeTrackSegment(
      '${track.artist} ${track.title}',
    );
    final targetTitleOnly = TrackMetadata.normalizeTrackSegment(
      track.title,
      stripFeat: true,
    );
    final targetArtistOnly = TrackMetadata.normalizeTrackSegment(
      track.artist,
      stripFeat: true,
    );

    for (final folder in allFolders) {
      try {
        final dir = Directory(resolveFolderDirectoryPath(folder));
        if (!await dir.exists()) continue;

        for (final candidateName in <String>[
          track.sanitizedFlacFileName,
          track.sanitizedFileName,
        ]) {
          final exactFile = File('${dir.path}/$candidateName');
          if (await exactFile.exists() &&
              await exactFile.length() >= _minValidMusicBytes) {
            return exactFile.path;
          }
        }

        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final rawName = entity.path.split(Platform.pathSeparator).last;
          final lower = rawName.toLowerCase();
          if (!isSupportedAudioFilePath(lower)) continue;
          if (await entity.length() < _minValidMusicBytes) continue;

          final rawWithoutExt = stripAudioExtension(rawName);
          final lowerWithoutExt = rawWithoutExt.toLowerCase();

          if (lower == targetFileLower ||
              lower == targetFlacLower ||
              lowerWithoutExt == baseWithoutExt ||
              lowerWithoutExt.startsWith('$baseWithoutExt (')) {
            return entity.path;
          }

          final stem = rawWithoutExt.replaceFirst(RegExp(r'\s\(\d+\)$'), '');
          final dashIdx = stem.indexOf(' - ');
          if (dashIdx > 0) {
            final fArtist = stem.substring(0, dashIdx);
            final fTitle = stem.substring(dashIdx + 3);
            if (targetIdentity.isNotEmpty &&
                TrackMetadata.normalizeTrackIdentity(fTitle, fArtist) ==
                    targetIdentity) {
              return entity.path;
            }
          }
          final normStem = TrackMetadata.normalizeTrackSegment(stem);
          if (normStem.isNotEmpty && normStem == targetCombined) {
            return entity.path;
          }
          if (targetTitleOnly.length >= 4 &&
              targetArtistOnly.length >= 2 &&
              normStem.contains(targetTitleOnly) &&
              normStem.contains(targetArtistOnly)) {
            return entity.path;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Counts the number of `.mp3` and `.flac` files inside each folder in [folders].
  Future<Map<String, int>> getFolderSongCounts(List<String> folders) async {
    final counts = <String, int>{};
    if (!Platform.isAndroid) return counts;

    for (final folder in folders) {
      int count = 0;
      try {
        final dir = Directory(resolveFolderDirectoryPath(folder));
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is File &&
                isSupportedAudioFilePath(entity.path) &&
                await entity.length() >= _minValidMusicBytes) {
              count++;
            }
          }
        }
      } catch (_) {}
      counts[folder] = count;
    }
    return counts;
  }

  /// Moves an already downloaded MP3 file to another folder inside `/storage/emulated/0/Music/`
  /// and triggers Android MediaScanner on both paths so Musicolet updates immediately.
  Future<String> moveDownloadedFile({
    required String currentFilePath,
    required String targetFolderName,
  }) async {
    final sourceFile = File(currentFilePath);
    if (!await sourceFile.exists()) {
      throw Exception(AppStrings.svcSourceFileNotFound(currentFilePath));
    }

    final cleanFolder = normalizePickedFolderTarget(targetFolderName);
    final fileName = sourceFile.path.split(Platform.pathSeparator).last;
    final targetDir = Directory(resolveFolderDirectoryPath(cleanFolder));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final destPath = '${targetDir.path}/$fileName';
    if (destPath == sourceFile.path) {
      return destPath;
    }

    final destFile = File(destPath);
    if (await destFile.exists()) {
      await deleteLocalAudioFile(destPath);
    }

    final bytes = await sourceFile.readAsBytes();
    final wroteOk = await writeBytesToMusicFile(destPath, bytes);
    if (!wroteOk) {
      throw Exception(
        AppStrings.svcFolderWriteFailed(cleanFolder),
      );
    }

    // Preserve legacy companion .lrc sidecar if present next to sourceFile
    try {
      final dotIdx = sourceFile.path.lastIndexOf('.');
      if (dotIdx > 0) {
        final srcLrc = File('${sourceFile.path.substring(0, dotIdx)}.lrc');
        if (await srcLrc.exists()) {
          final destDotIdx = destPath.lastIndexOf('.');
          if (destDotIdx > 0) {
            final destLrcPath = '${destPath.substring(0, destDotIdx)}.lrc';
            final lrcBytes = await srcLrc.readAsBytes();
            await writeBytesToMusicFile(destLrcPath, lrcBytes);
          }
        }
      }
    } catch (_) {}

    await deleteLocalAudioFile(currentFilePath);

    await scanMediaFile(currentFilePath);
    await scanMediaFile(destFile.path);
    return destFile.path;
  }

  /// Notifies Android's `MediaScannerConnection` so Musicolet immediately detects
  /// the new or updated MP3 file.
  Future<void> scanMediaFile(String path) async {
    if (!Platform.isAndroid || path.trim().isEmpty) return;
    try {
      await _systemChannel.invokeMethod<bool>(
        'scanMediaFile',
        {'path': path},
      );
    } catch (e) {
      debugPrint('[AUTO_E2E] MediaScanner invoke gagal: $e');
    }
  }

  /// Layered Android 11–15 Scoped Storage audio deletion:
  /// 1. Releases native `MediaPlayer` lock if active
  /// 2. Deletes via `File(path).delete()`
  /// 3. Deletes via `MediaStore` (`_ID` item URI & `DATA = ?`)
  /// 4. Escalates to `MediaStore.createDeleteRequest` / `MANAGE_EXTERNAL_STORAGE` when needed
  /// 5. Verifies physical removal (`!File(path).exists()`) before returning `true`.
  Future<bool> deleteLocalAudioFile(
    String path, {
    bool autoRequestPermission = true,
  }) async {
    if (path.trim().isEmpty) return false;
    if (!Platform.isAndroid) {
      try {
        final f = File(path);
        if (!await f.exists()) return true;
        await f.delete();
        return !await f.exists();
      } catch (_) {
        return false;
      }
    }

    try {
      final res = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'deleteLocalAudioFile',
        {
          'path': path,
          'allowSystemPrompt': true,
        },
      );
      final deleted = res?['deleted'] == true;
      final cancelled = res?['cancelledByUser'] == true;
      final needsAllFiles = res?['needsAllFilesAccess'] == true;

      if (deleted && !await File(path).exists()) {
        return true;
      }
      if (cancelled) {
        return false;
      }
      if (needsAllFiles && autoRequestPermission) {
        final granted = await requestAllFilesAccess();
        if (granted) {
          final retry =
              await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
            'deleteLocalAudioFile',
            {
              'path': path,
              'allowSystemPrompt': false,
            },
          );
          if (retry?['deleted'] == true && !await File(path).exists()) {
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[MusEvee] deleteLocalAudioFile error: $e');
    }

    return !await File(path).exists();
  }

  /// Writes MP3 bytes safely on Android 11–15 Scoped Storage, escalating to
  /// `MediaStore.createWriteRequest` or `MANAGE_EXTERNAL_STORAGE` if overwriting
  /// a non-owned file in `/storage/emulated/0/Music/`.
  Future<bool> writeBytesToMusicFile(
    String path,
    Uint8List bytes, {
    bool autoRequestPermission = true,
  }) async {
    if (path.trim().isEmpty || bytes.isEmpty) return false;
    try {
      final targetFile = File(path);
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }
      await targetFile.writeAsBytes(bytes, flush: true);
      if (await targetFile.exists() && await targetFile.length() > 0) {
        await scanMediaFile(path);
        return true;
      }
    } catch (_) {
      // Fall through to native Scoped Storage handler on Android
    }

    if (!Platform.isAndroid) return false;

    try {
      final res = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
        'writeBytesToMusicFile',
        {
          'path': path,
          'bytes': bytes,
          'allowSystemPrompt': true,
        },
      );
      if (res?['written'] == true) {
        return true;
      }
      final cancelled = res?['cancelledByUser'] == true;
      final needsAllFiles = res?['needsAllFilesAccess'] == true;
      if (!cancelled && needsAllFiles && autoRequestPermission) {
        final granted = await requestAllFilesAccess();
        if (granted) {
          final retry =
              await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
            'writeBytesToMusicFile',
            {
              'path': path,
              'bytes': bytes,
              'allowSystemPrompt': false,
            },
          );
          return retry?['written'] == true;
        }
      }
    } catch (e) {
      debugPrint('[MusEvee] writeBytesToMusicFile error: $e');
    }
    return false;
  }

  /// Non-interactive delete helper used during fresh download deduplication.
  Future<bool> deleteMediaFile(String path) async {
    if (!Platform.isAndroid || path.trim().isEmpty) return false;
    try {
      final f = File(path);
      if (!await f.exists()) return true;
      await f.delete();
      if (!await f.exists()) {
        await _systemChannel.invokeMethod<bool>(
          'deleteMediaFile',
          {'path': path},
        );
        return true;
      }
    } catch (_) {}
    try {
      final res = await _systemChannel.invokeMethod<bool>(
        'deleteMediaFile',
        {'path': path},
      );
      return res == true && !await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  String sanitizeFolderName(String raw) {
    return raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
