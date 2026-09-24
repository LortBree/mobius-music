import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Local persistent favorites and playlists for the current library.
class UserCollections {
  static const _favoritesKey = 'favorite_track_ids';
  static const _playlistsKey = 'user_playlists_v1';
  static const _playlistCoversKey = 'user_playlist_covers_v1';
  static const _removedLibraryTrackIdsKey = 'removed_library_track_ids_v1';

  Future<Set<int>> removedLibraryTrackIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_removedLibraryTrackIdsKey) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> removeFromLibrary(int trackId) async {
    final ids = await removedLibraryTrackIds()..add(trackId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _removedLibraryTrackIdsKey,
      ids.map((id) => id.toString()).toList()..sort(),
    );
  }

  Future<Set<int>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favoritesKey) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<bool> toggleFavorite(int trackId) async {
    final values = await favorites();
    final isFavorite = !values.add(trackId);
    if (isFavorite) values.remove(trackId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      values.map((id) => id.toString()).toList()..sort(),
    );
    return !isFavorite;
  }

  Future<Map<String, List<int>>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: (entry.value as List<dynamic>)
              .whereType<num>()
              .map((id) => id.toInt())
              .toList(),
      };
    } on Object {
      return {};
    }
  }

  Future<void> createPlaylist(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw ArgumentError('Playlist name is empty.');
    final values = await playlists();
    if (values.keys.any(
      (key) => key.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw StateError('A playlist with this name already exists.');
    }
    values[normalized] = [];
    await _savePlaylists(values);
  }

  Future<void> deletePlaylist(String name) async {
    final values = await playlists()
      ..remove(name);
    await _savePlaylists(values);
    final covers = await _playlistCovers();
    covers.remove(name);
    await _saveCovers(covers);
  }

  Future<void> renamePlaylist(String oldName, String newName) async {
    final normalized = newName.trim();
    if (normalized.isEmpty) throw ArgumentError('Playlist name is empty.');
    final values = await playlists();
    if (!values.containsKey(oldName)) throw StateError('Playlist not found.');
    if (oldName != normalized &&
        values.keys.any(
          (key) => key.toLowerCase() == normalized.toLowerCase(),
        )) {
      throw StateError('A playlist with this name already exists.');
    }
    final renamed = <String, List<int>>{};
    for (final entry in values.entries) {
      renamed[entry.key == oldName ? normalized : entry.key] = entry.value;
    }
    await _savePlaylists(renamed);

    final covers = await _playlistCovers();
    final cover = covers.remove(oldName);
    if (cover != null) covers[normalized] = cover;
    await _saveCovers(covers);
  }

  Future<void> addToPlaylist(String name, int trackId) async {
    final values = await playlists();
    final tracks = values[name];
    if (tracks == null) throw StateError('Playlist no longer exists.');
    if (!tracks.contains(trackId)) tracks.add(trackId);
    await _savePlaylists(values);
  }

  Future<void> removeFromPlaylist(String name, int trackId) async {
    final values = await playlists();
    values[name]?.remove(trackId);
    await _savePlaylists(values);
  }

  Future<void> reorderPlaylist(String name, List<int> trackIds) async {
    final values = await playlists();
    if (!values.containsKey(name)) throw StateError('Playlist not found.');
    values[name] = List<int>.from(trackIds);
    await _savePlaylists(values);
  }

  Future<Uint8List?> playlistCover(String name) async {
    final encoded = (await _playlistCovers())[name];
    if (encoded == null) return null;
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } on FormatException {
      return null;
    }
  }

  Future<void> setPlaylistCover(String name, Uint8List bytes) async {
    final covers = await _playlistCovers();
    covers[name] = base64Encode(bytes);
    await _saveCovers(covers);
  }

  Future<Map<String, String>> _playlistCovers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playlistCoversKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (name, value) => MapEntry(name, value as String),
      );
    } on Object {
      return {};
    }
  }

  Future<void> _savePlaylists(Map<String, List<int>> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistsKey, jsonEncode(values));
  }

  Future<void> _saveCovers(Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playlistCoversKey, jsonEncode(values));
  }
}
