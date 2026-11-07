import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track_metadata.dart';

class FolderService {
  static const String baseMusicRoot = '/storage/emulated/0/Music';
  static const String fallbackDownloadRoot = '/storage/emulated/0/Download';

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

  static const Set<String> _excludedSystemFolderNames = {
    'ringtones_music',
    'ringtones',
    'alarms',
    'notifications',
    'ui',
    '.thumbnails',
  };

  static const int _minValidMusicBytes = 16384;

  /// Lists all available target folders under `/storage/emulated/0/Music/`,
  /// always prioritizing `Music Barat`, `Music Japan`, and `Music Random`,
  /// followed by any other existing subdirectories in `/storage/emulated/0/Music/`.
  Future<List<String>> listAvailableFolders() async {
    final ordered = <String>[...defaultFolders];
    final seenLower = ordered.map((e) => e.toLowerCase()).toSet();

    if (Platform.isAndroid) {
      try {
        final musicDir = Directory(baseMusicRoot);
        if (await musicDir.exists()) {
          // Ensure the 3 core folders exist
          for (final core in defaultFolders) {
            try {
              final d = Directory('$baseMusicRoot/$core');
              if (!await d.exists()) {
                await d.create(recursive: true);
              }
            } catch (_) {}
          }

          final entries = await musicDir.list(followLinks: false).toList();
          final extraFolders = <String>[];
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
              if (!seenLower.contains(lower)) {
                seenLower.add(lower);
                extraFolders.add(name);
              }
            }
          }
          extraFolders.sort(
            (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
          );
          ordered.addAll(extraFolders);
        }
      } catch (e) {
        debugPrint('[AUTO_E2E] FolderService.listAvailableFolders error: $e');
      }
    }

    return ordered;
  }

  /// Creates a new subfolder inside `/storage/emulated/0/Music/` and returns its sanitized name.
  Future<String> createCustomFolder(String rawName) async {
    final cleaned = sanitizeFolderName(rawName);
    if (cleaned.isEmpty) {
      throw Exception('Nama folder tidak boleh kosong.');
    }

    if (Platform.isAndroid) {
      try {
        final dir = Directory('$baseMusicRoot/$cleaned');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } catch (e) {
        debugPrint('[AUTO_E2E] Gagal membuat folder di $baseMusicRoot/$cleaned: $e');
      }
    }

    return cleaned;
  }

  /// Reads the last selected folder from local app storage (defaults to `'Music Barat'`).
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
    return defaultFolders.first;
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

  /// Checks whether [fileName] (e.g. `Artist - Title.mp3`) already exists inside
  /// any of the [folders] under `/storage/emulated/0/Music/`.
  /// Returns the folder name where it was found, or `null` if not found.
  Future<String?> findDuplicateFolder(
    String fileName,
    List<String> folders,
  ) async {
    if (!Platform.isAndroid) return null;

    final targetLower = fileName.toLowerCase();
    final baseWithoutExt = targetLower.endsWith('.mp3')
        ? targetLower.substring(0, targetLower.length - 4)
        : targetLower;

    for (final folder in folders) {
      try {
        final dir = Directory('$baseMusicRoot/$folder');
        if (!await dir.exists()) continue;

        final exactFile = File('${dir.path}/$fileName');
        if (await exactFile.exists() &&
            await exactFile.length() >= _minValidMusicBytes) {
          return folder;
        }

        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            final name = entity.path
                .split(Platform.pathSeparator)
                .last
                .toLowerCase();
            if ((name == targetLower ||
                    (name.endsWith('.mp3') &&
                        name.startsWith('$baseWithoutExt ('))) &&
                await entity.length() >= _minValidMusicBytes) {
              return folder;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Checks across all [folders] (plus any extra subdirectories in `/storage/emulated/0/Music/`)
  /// whether an `.mp3` matching [track] already exists on disk (by exact filename OR
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
    final baseWithoutExt = targetFileLower.endsWith('.mp3')
        ? targetFileLower.substring(0, targetFileLower.length - 4)
        : targetFileLower;
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
        final dir = Directory('$baseMusicRoot/$folder');
        if (!await dir.exists()) continue;

        final exactFile = File('${dir.path}/${track.sanitizedFileName}');
        if (await exactFile.exists() &&
            await exactFile.length() >= _minValidMusicBytes) {
          return exactFile.path;
        }

        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final rawName = entity.path.split(Platform.pathSeparator).last;
          final lower = rawName.toLowerCase();
          if (!lower.endsWith('.mp3')) continue;
          if (await entity.length() < _minValidMusicBytes) continue;

          if (lower == targetFileLower ||
              lower.startsWith('$baseWithoutExt (')) {
            return entity.path;
          }

          final stem = rawName
              .substring(0, rawName.length - 4)
              .replaceFirst(RegExp(r'\s\(\d+\)$'), '');
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

  /// Counts the number of `.mp3` files inside each folder in [folders].
  Future<Map<String, int>> getFolderSongCounts(List<String> folders) async {
    final counts = <String, int>{};
    if (!Platform.isAndroid) return counts;

    for (final folder in folders) {
      int count = 0;
      try {
        final dir = Directory('$baseMusicRoot/$folder');
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is File &&
                entity.path.toLowerCase().endsWith('.mp3') &&
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
      throw Exception('File asal tidak ditemukan: $currentFilePath');
    }

    final cleanFolder = sanitizeFolderName(targetFolderName);
    final fileName = sourceFile.path.split(Platform.pathSeparator).last;
    final targetDir = Directory('$baseMusicRoot/$cleanFolder');
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
        'Gagal menulis file ke folder $cleanFolder. Pastikan izin penyimpanan diberikan.',
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
          final retry = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
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
          final retry = await _systemChannel.invokeMethod<Map<dynamic, dynamic>>(
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

