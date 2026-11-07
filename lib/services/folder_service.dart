import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
              if (name.isEmpty || name.startsWith('.')) continue;
              if (!seenLower.contains(name.toLowerCase())) {
                seenLower.add(name.toLowerCase());
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
        if (await exactFile.exists() && await exactFile.length() > 0) {
          return folder;
        }

        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            final name = entity.path
                .split(Platform.pathSeparator)
                .last
                .toLowerCase();
            if (name == targetLower ||
                (name.endsWith('.mp3') &&
                    name.startsWith('$baseWithoutExt ('))) {
              return folder;
            }
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
                entity.path.toLowerCase().endsWith('.mp3')) {
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
      await destFile.delete();
    }

    final bytes = await sourceFile.readAsBytes();
    await destFile.writeAsBytes(bytes, flush: true);

    try {
      await sourceFile.delete();
    } catch (_) {}

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

  String sanitizeFolderName(String raw) {
    return raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

