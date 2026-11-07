class LocalPlaylist {
  final String id;
  final String name;
  final String description;
  final String? customCoverPath;
  final List<String> songPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.customCoverPath,
    required this.songPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  int get songCount => songPaths.length;

  LocalPlaylist copyWith({
    String? id,
    String? name,
    String? description,
    String? customCoverPath,
    bool clearCustomCoverPath = false,
    List<String>? songPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LocalPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      customCoverPath: clearCustomCoverPath
          ? null
          : (customCoverPath ?? this.customCoverPath),
      songPaths: songPaths != null
          ? List<String>.unmodifiable(songPaths)
          : this.songPaths,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'customCoverPath': customCoverPath,
        'songPaths': songPaths,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) {
    final rawPaths = json['songPaths'];
    final paths = <String>[];
    final seen = <String>{};
    if (rawPaths is List) {
      for (final item in rawPaths) {
        final str = item?.toString().trim() ?? '';
        if (str.isNotEmpty && seen.add(str)) {
          paths.add(str);
        }
      }
    }

    final createdStr = json['createdAt']?.toString() ?? '';
    final updatedStr = json['updatedAt']?.toString() ?? '';
    final now = DateTime.now();

    return LocalPlaylist(
      id: (json['id']?.toString().trim().isNotEmpty == true)
          ? json['id'].toString().trim()
          : 'pl_${now.microsecondsSinceEpoch}',
      name: (json['name']?.toString().trim().isNotEmpty == true)
          ? json['name'].toString().trim()
          : 'Playlist',
      description: json['description']?.toString().trim() ?? '',
      customCoverPath:
          (json['customCoverPath']?.toString().trim().isNotEmpty == true)
              ? json['customCoverPath'].toString().trim()
              : null,
      songPaths: List<String>.unmodifiable(paths),
      createdAt: DateTime.tryParse(createdStr) ?? now,
      updatedAt: DateTime.tryParse(updatedStr) ?? now,
    );
  }
}

