import 'track_metadata.dart';

enum DownloadItemStatus {
  queued,
  downloading,
  tagging,
  completed,
  failed,
}

class DownloadItem {
  final String id;
  final TrackMetadata metadata;
  final String targetFolderName;
  final DownloadItemStatus status;
  final double progress;
  final String statusDetail;
  final String? savedFilePath;
  final String? errorMessage;
  final DateTime createdAt;
  final bool preferSyncedLyrics;

  const DownloadItem({
    required this.id,
    required this.metadata,
    required this.targetFolderName,
    required this.status,
    required this.progress,
    required this.statusDetail,
    required this.createdAt,
    this.savedFilePath,
    this.errorMessage,
    this.preferSyncedLyrics = true,
  });

  bool get isActive =>
      status == DownloadItemStatus.downloading ||
      status == DownloadItemStatus.tagging;

  DownloadItem copyWith({
    TrackMetadata? metadata,
    String? targetFolderName,
    DownloadItemStatus? status,
    double? progress,
    String? statusDetail,
    String? savedFilePath,
    String? errorMessage,
    bool? preferSyncedLyrics,
  }) {
    return DownloadItem(
      id: id,
      metadata: metadata ?? this.metadata,
      targetFolderName: targetFolderName ?? this.targetFolderName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      statusDetail: statusDetail ?? this.statusDetail,
      createdAt: createdAt,
      savedFilePath: savedFilePath ?? this.savedFilePath,
      errorMessage: errorMessage ?? this.errorMessage,
      preferSyncedLyrics: preferSyncedLyrics ?? this.preferSyncedLyrics,
    );
  }
}
