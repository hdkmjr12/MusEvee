import 'package:flutter/foundation.dart';

import 'track_metadata.dart';

@immutable
class CuratedPlaylist {
  final String id;
  final String deezerPlaylistId;
  final String title;
  final int songCount;
  final String spotifyUrl;
  final String? coverUrl;
  final List<String> sampleCovers;
  final List<TrackMetadata> preloadedTracks;

  const CuratedPlaylist({
    required this.id,
    this.deezerPlaylistId = '',
    required this.title,
    required this.songCount,
    required this.spotifyUrl,
    this.coverUrl,
    this.sampleCovers = const [],
    this.preloadedTracks = const [],
  });

  CuratedPlaylist copyWith({
    String? id,
    String? deezerPlaylistId,
    String? title,
    int? songCount,
    String? spotifyUrl,
    String? coverUrl,
    List<String>? sampleCovers,
    List<TrackMetadata>? preloadedTracks,
  }) {
    return CuratedPlaylist(
      id: id ?? this.id,
      deezerPlaylistId: deezerPlaylistId ?? this.deezerPlaylistId,
      title: title ?? this.title,
      songCount: songCount ?? this.songCount,
      spotifyUrl: spotifyUrl ?? this.spotifyUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      sampleCovers: sampleCovers ?? this.sampleCovers,
      preloadedTracks: preloadedTracks ?? this.preloadedTracks,
    );
  }
}

