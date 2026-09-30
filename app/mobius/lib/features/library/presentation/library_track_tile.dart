import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../core/ffi/offline_player.dart';

class LibraryTrackTile extends StatelessWidget {
  const LibraryTrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  final TrackMetadata track;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent
          ? MobiusColors.borderOf(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: MobiusColors.panelOf(context),
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Center(
                  child: isCurrent
                      ? Icon(
                          Icons.equalizer_rounded,
                          size: 19,
                          color: MobiusColors.accentOf(context),
                        )
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  track.title.isEmpty
                      ? 'Unknown title'
                      : track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobiusColors.textOf(context),
                    fontSize: 15,
                    fontWeight: isCurrent
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  track.artist.isEmpty
                      ? 'Unknown artist'
                      : track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  track.album.isEmpty
                      ? '—'
                      : track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}