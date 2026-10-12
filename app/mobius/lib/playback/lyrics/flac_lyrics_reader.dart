import 'dart:convert';
import 'dart:io';

/// Reads embedded Vorbis comment lyrics from FLAC files or adjacent .lrc files.
class FlacLyricsReader {
  static final Map<String, String?> _lyricsCache = {};

  /// Looks for lyrics for the audio file at [filePath].
  ///
  /// Checks in this order:
  /// 1. In-memory cache.
  /// 2. Adjacent .lrc sidecar file (e.g. `Song.lrc`).
  /// 3. Embedded Vorbis Comment block in the FLAC file (`LYRICS` or `UNSYNCEDLYRICS`).
  static Future<String?> readLyrics(String filePath) async {
    if (filePath.isEmpty) return null;

    if (_lyricsCache.containsKey(filePath)) {
      return _lyricsCache[filePath];
    }

    try {
      // 1. Check adjacent .lrc sidecar file
      final lrcPath = _getAdjacentLrcPath(filePath);
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final content = await lrcFile.readAsString();
        if (content.trim().isNotEmpty) {
          _lyricsCache[filePath] = content;
          return content;
        }
      }

      // 2. Parse FLAC metadata blocks for Vorbis comments
      final file = File(filePath);
      if (await file.exists()) {
        final embedded = await _readEmbeddedVorbisLyrics(file);
        if (embedded != null && embedded.trim().isNotEmpty) {
          _lyricsCache[filePath] = embedded;
          return embedded;
        }
      }
    } catch (_) {
      // Return null on any read/permission error
    }

    _lyricsCache[filePath] = null;
    return null;
  }

  static String _getAdjacentLrcPath(String audioPath) {
    final dotIndex = audioPath.lastIndexOf('.');
    if (dotIndex == -1) return '$audioPath.lrc';
    return '${audioPath.substring(0, dotIndex)}.lrc';
  }

  /// Extracts the `LYRICS` or `UNSYNCEDLYRICS` Vorbis comment from a FLAC file.
  static Future<String?> _readEmbeddedVorbisLyrics(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final length = await raf.length();
      if (length < 8) return null;

      // Verify FLAC magic header ('fLaC')
      final magic = await raf.read(4);
      if (magic.length < 4 ||
          magic[0] != 0x66 ||
          magic[1] != 0x4C ||
          magic[2] != 0x61 ||
          magic[3] != 0x43) {
        return null;
      }

      // Read metadata blocks
      var isLast = false;
      while (!isLast && (await raf.position()) < length) {
        final header = await raf.read(4);
        if (header.length < 4) break;

        isLast = (header[0] & 0x80) != 0;
        final blockType = header[0] & 0x7F;
        final blockLength = (header[1] << 16) | (header[2] << 8) | header[3];

        if (blockType == 4) {
          // Block type 4 is VORBIS_COMMENT
          final blockData = await raf.read(blockLength);
          return _parseVorbisComments(blockData);
        } else {
          // Skip other metadata blocks
          final currentPos = await raf.position();
          await raf.setPosition(currentPos + blockLength);
        }
      }
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }

    return null;
  }

  /// Parses Vorbis Comment block bytes and returns the lyrics string if found.
  static String? _parseVorbisComments(List<int> bytes) {
    if (bytes.length < 8) return null;

    var offset = 0;

    // Vendor string length (32-bit unsigned little-endian)
    final vendorLength = bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    offset += 4;
    offset += vendorLength;

    if (offset + 4 > bytes.length) return null;

    // User comment count (32-bit unsigned little-endian)
    final userCommentCount = bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    offset += 4;

    String? unsyncedFallback;

    for (var i = 0; i < userCommentCount; i++) {
      if (offset + 4 > bytes.length) break;

      final commentLength = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      offset += 4;

      if (offset + commentLength > bytes.length) break;

      final commentBytes = bytes.sublist(offset, offset + commentLength);
      offset += commentLength;

      try {
        final commentStr = utf8.decode(commentBytes, allowMalformed: true);
        final eqIndex = commentStr.indexOf('=');
        if (eqIndex != -1) {
          final key = commentStr.substring(0, eqIndex).toUpperCase();
          final val = commentStr.substring(eqIndex + 1);

          if (key == 'LYRICS') {
            return val;
          } else if (key == 'UNSYNCEDLYRICS') {
            unsyncedFallback ??= val;
          }
        }
      } catch (_) {}
    }

    return unsyncedFallback;
  }
}
