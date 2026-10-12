/// Represents a single line of lyrics with an optional playback timestamp.
class LyricLine {
  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  final Duration timestamp;
  final String text;

  @override
  String toString() => '[${timestamp.inMilliseconds}ms] $text';
}

/// Structured lyrics parsed from an LRC string or plain text.
class ParsedLyrics {
  const ParsedLyrics({
    required this.lines,
    required this.isSynced,
    required this.rawText,
  });

  final List<LyricLine> lines;
  final bool isSynced;
  final String rawText;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Returns the index of the active lyric line for the given [position].
  /// Returns -1 if playback is before the first timestamp.
  int findActiveIndex(Duration position) {
    if (lines.isEmpty || !isSynced) return -1;
    if (position < lines.first.timestamp) return -1;

    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].timestamp) {
        return i;
      }
    }
    return 0;
  }

  /// Parses raw lyric content (either LRC formatted or plain text).
  static ParsedLyrics parse(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return const ParsedLyrics(lines: [], isSynced: false, rawText: '');
    }

    final rawLines = trimmed.split(RegExp(r'\r?\n'));
    final parsedEntries = <LyricLine>[];
    final tagRegex = RegExp(r'\[(\d{1,2}):(\d{1,2}(?:\.\d{1,3})?)\]');

    var hasTimestamps = false;

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final matches = tagRegex.allMatches(line).toList();
      if (matches.isNotEmpty) {
        hasTimestamps = true;
        // Text is everything after the last timestamp match
        final text = line.substring(matches.last.end).trim();

        for (final match in matches) {
          final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
          final secondsWithFrac = double.tryParse(match.group(2) ?? '0') ?? 0.0;
          final milliseconds = (minutes * 60 * 1000) + (secondsWithFrac * 1000).round();

          parsedEntries.add(
            LyricLine(
              timestamp: Duration(milliseconds: milliseconds),
              text: text,
            ),
          );
        }
      } else {
        // Line without timestamp: ignore ID tags like [ar:Artist], [ti:Title]
        if (RegExp(r'^\[[a-zA-Z]+:.*\]$').hasMatch(line)) {
          continue;
        }
        if (!hasTimestamps) {
          parsedEntries.add(
            LyricLine(
              timestamp: Duration.zero,
              text: line,
            ),
          );
        }
      }
    }

    if (hasTimestamps) {
      parsedEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return ParsedLyrics(
      lines: parsedEntries,
      isSynced: hasTimestamps,
      rawText: trimmed,
    );
  }
}
