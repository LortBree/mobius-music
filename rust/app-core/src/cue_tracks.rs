use crate::cue::{CueError, CueSheet};
use crate::library::{AudioAssetId, Track, TrackId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CueTrackBuild {
    pub track: Track,
    pub source_file: std::path::PathBuf,
}

pub fn build_tracks(
    asset_id: AudioAssetId,
    total_frames: u64,
    sample_rate: u32,
    sheet: &CueSheet,
    first_track_id: TrackId,
) -> Result<Vec<CueTrackBuild>, CueError> {
    if sample_rate == 0 {
        return Err(CueError::InvalidSampleRate);
    }

    if sheet.tracks.is_empty() {
        return Err(CueError::NoTracks);
    }

    let starts = crate::cue::track_start_frames(sheet, sample_rate)?;

    if starts.len() != sheet.tracks.len() {
        return Err(CueError::InvalidLine {
            line: 0,
            message: "CUE track/start count mismatch".to_string(),
        });
    }

    let mut result = Vec::with_capacity(sheet.tracks.len());

    for index in 0..sheet.tracks.len() {
        let cue_track = &sheet.tracks[index];

        let start_frame = starts[index].1;

        if start_frame > total_frames {
            return Err(CueError::InvalidLine {
                line: 0,
                message: format!(
                    "TRACK {} starts after asset EOF: {} > {}",
                    cue_track.number, start_frame, total_frames,
                ),
            });
        }

        let end_frame = if index + 1 < starts.len() {
            starts[index + 1].1
        } else {
            total_frames
        };

        if end_frame < start_frame {
            return Err(CueError::InvalidLine {
                line: 0,
                message: format!("TRACK {} has negative duration", cue_track.number),
            });
        }

        let frame_count = end_frame.saturating_sub(start_frame);

        if frame_count == 0 {
            return Err(CueError::InvalidLine {
                line: 0,
                message: format!("TRACK {} has zero duration", cue_track.number),
            });
        }

        let track_id = TrackId(first_track_id.0.checked_add(index as i64).ok_or(
            CueError::InvalidLine {
                line: 0,
                message: "TrackId overflow".to_string(),
            },
        )?);

        result.push(CueTrackBuild {
            track: Track {
                id: track_id,
                asset_id,

                start_frame,
                frame_count: Some(frame_count),

                disc_number: None,
                track_number: cue_track.number,

                title: cue_track.title.clone(),

                performer: cue_track.performer.clone(),

                album: None,
            },

            source_file: sheet
                .file
                .clone()
                .expect("validated CueSheet must have FILE"),
        });
    }

    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cue::parse;

    fn sheet() -> CueSheet {
        parse(
            r#"
FILE "album.flac" WAVE

TRACK 01 AUDIO
TITLE "First Song"
PERFORMER "Artist"
INDEX 01 00:00:00

TRACK 02 AUDIO
TITLE "Second Song"
PERFORMER "Artist"
INDEX 01 00:01:00

TRACK 03 AUDIO
TITLE "Third Song"
PERFORMER "Artist"
INDEX 01 00:03:00
"#,
        )
        .unwrap()
    }

    #[test]
    fn builds_frame_ranges_from_next_track() {
        let tracks =
            build_tracks(AudioAssetId(7), 220_500, 44_100, &sheet(), TrackId(100)).unwrap();

        assert_eq!(tracks.len(), 3);

        //
        // Track 1: 0 .. 44100
        //
        assert_eq!(tracks[0].track.start_frame, 0);

        assert_eq!(tracks[0].track.frame_count, Some(44_100));

        //
        // Track 2: 44100 .. 132300
        //
        assert_eq!(tracks[1].track.start_frame, 44_100);

        assert_eq!(tracks[1].track.frame_count, Some(88_200));

        //
        // Track 3: 132300 .. EOF 220500
        //
        assert_eq!(tracks[2].track.start_frame, 132_300);

        assert_eq!(tracks[2].track.frame_count, Some(88_200));
    }

    #[test]
    fn preserves_track_metadata() {
        let tracks =
            build_tracks(AudioAssetId(99), 220_500, 44_100, &sheet(), TrackId(500)).unwrap();

        assert_eq!(tracks[0].track.id, TrackId(500));

        assert_eq!(tracks[1].track.id, TrackId(501));

        assert_eq!(tracks[2].track.id, TrackId(502));

        assert_eq!(tracks[0].track.asset_id, AudioAssetId(99));

        assert_eq!(tracks[1].track.title.as_deref(), Some("Second Song"));

        assert_eq!(tracks[1].track.performer.as_deref(), Some("Artist"));

        assert_eq!(
            tracks[0].source_file,
            std::path::PathBuf::from("album.flac")
        );
    }

    #[test]
    fn rejects_track_start_after_eof() {
        let source = parse(
            r#"
FILE "album.flac" WAVE

TRACK 01 AUDIO
TITLE "First"
INDEX 01 00:10:00
"#,
        )
        .unwrap();

        let result = build_tracks(AudioAssetId(1), 44_100, 44_100, &source, TrackId(1));

        assert!(matches!(result, Err(CueError::InvalidLine { .. })));
    }

    #[test]
    fn rejects_zero_length_track() {
        let source = parse(
            r#"
FILE "album.flac" WAVE

TRACK 01 AUDIO
TITLE "First"
INDEX 01 00:00:00

TRACK 02 AUDIO
TITLE "Second"
INDEX 01 00:00:00
"#,
        )
        .unwrap();

        let result = build_tracks(AudioAssetId(1), 44_100, 44_100, &source, TrackId(1));

        assert!(matches!(result, Err(CueError::InvalidLine { .. })));
    }
}
