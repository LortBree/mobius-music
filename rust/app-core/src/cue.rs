use std::path::PathBuf;

use thiserror::Error;

const CUE_FRAMES_PER_SECOND: u64 = 75;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CueSheet {
    pub file: Option<PathBuf>,
    pub tracks: Vec<CueTrack>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CueTrack {
    pub number: u32,
    pub title: Option<String>,
    pub performer: Option<String>,
    pub index_01: Option<CueTime>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CueTime {
    pub minutes: u64,
    pub seconds: u8,
    pub frames: u8,
}

impl CueTime {
    pub fn parse(value: &str) -> Result<Self, CueError> {
        let mut parts = value.split(':');

        let minutes = parts
            .next()
            .ok_or_else(|| CueError::InvalidTimecode {
                value: value.to_string(),
            })?
            .parse::<u64>()
            .map_err(|_| CueError::InvalidTimecode {
                value: value.to_string(),
            })?;

        let seconds = parts
            .next()
            .ok_or_else(|| CueError::InvalidTimecode {
                value: value.to_string(),
            })?
            .parse::<u8>()
            .map_err(|_| CueError::InvalidTimecode {
                value: value.to_string(),
            })?;

        let frames = parts
            .next()
            .ok_or_else(|| CueError::InvalidTimecode {
                value: value.to_string(),
            })?
            .parse::<u8>()
            .map_err(|_| CueError::InvalidTimecode {
                value: value.to_string(),
            })?;

        if parts.next().is_some() {
            return Err(CueError::InvalidTimecode {
                value: value.to_string(),
            });
        }

        if seconds >= 60 {
            return Err(CueError::InvalidTimecode {
                value: value.to_string(),
            });
        }

        if frames >= CUE_FRAMES_PER_SECOND as u8 {
            return Err(CueError::InvalidTimecode {
                value: value.to_string(),
            });
        }

        Ok(Self {
            minutes,
            seconds,
            frames,
        })
    }

    /// Converts CUE MM:SS:FF into source audio frames.
    ///
    /// CUE time uses 75 frames per second. Conversion is performed
    /// entirely with integer arithmetic:
    ///
    /// floor(cue_frames * sample_rate / 75)
    pub fn to_source_frame(self, sample_rate: u32) -> Result<u64, CueError> {
        if sample_rate == 0 {
            return Err(CueError::InvalidSampleRate);
        }

        let cue_frames = self
            .minutes
            .checked_mul(60)
            .and_then(|value| value.checked_mul(CUE_FRAMES_PER_SECOND))
            .and_then(|value| {
                value.checked_add((self.seconds as u64).checked_mul(CUE_FRAMES_PER_SECOND)?)
            })
            .and_then(|value| value.checked_add(self.frames as u64))
            .ok_or(CueError::FrameOverflow)?;

        let numerator = cue_frames
            .checked_mul(sample_rate as u64)
            .ok_or(CueError::FrameOverflow)?;

        Ok(numerator / CUE_FRAMES_PER_SECOND)
    }
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum CueError {
    #[error("empty CUE sheet")]
    Empty,

    #[error("invalid CUE line {line}: {message}")]
    InvalidLine { line: usize, message: String },

    #[error("invalid timecode: {value}")]
    InvalidTimecode { value: String },

    #[error("invalid sample rate")]
    InvalidSampleRate,

    #[error("source frame overflow")]
    FrameOverflow,

    #[error("TRACK encountered before FILE")]
    TrackWithoutFile,

    #[error("INDEX 01 encountered before TRACK")]
    IndexWithoutTrack,

    #[error("duplicate INDEX 01 for track {0}")]
    DuplicateIndex01(u32),

    #[error("duplicate TRACK number {0}")]
    DuplicateTrack(u32),

    #[error("no TRACK entries found")]
    NoTracks,

    #[error("TRACK {0} is missing INDEX 01")]
    MissingIndex01(u32),
}

pub fn parse(input: &str) -> Result<CueSheet, CueError> {
    if input.trim().is_empty() {
        return Err(CueError::Empty);
    }

    let mut sheet = CueSheet {
        file: None,
        tracks: Vec::new(),
    };

    for (line_index, raw_line) in input.lines().enumerate() {
        let line_number = line_index + 1;

        let line = raw_line.trim();

        if line.is_empty() {
            continue;
        }

        let (command, rest) = split_command(line);

        match command {
            "REM" => {
                continue;
            }

            "FILE" => {
                let value = parse_file_path(rest, line_number)?;

                if value.is_empty() {
                    return Err(CueError::InvalidLine {
                        line: line_number,
                        message: "FILE path is empty".to_string(),
                    });
                }

                sheet.file = Some(PathBuf::from(value));
            }

            "TRACK" => {
                if sheet.file.is_none() {
                    return Err(CueError::TrackWithoutFile);
                }

                let mut parts = rest.split_whitespace();

                let number_text = parts.next().ok_or_else(|| CueError::InvalidLine {
                    line: line_number,
                    message: "TRACK number missing".to_string(),
                })?;

                let number = number_text
                    .parse::<u32>()
                    .map_err(|_| CueError::InvalidLine {
                        line: line_number,
                        message: format!("invalid TRACK number: {number_text}"),
                    })?;

                let kind = parts.next().ok_or_else(|| CueError::InvalidLine {
                    line: line_number,
                    message: "TRACK type missing".to_string(),
                })?;

                if kind != "AUDIO" {
                    return Err(CueError::InvalidLine {
                        line: line_number,
                        message: format!("unsupported TRACK type: {kind}"),
                    });
                }

                if sheet.tracks.iter().any(|track| track.number == number) {
                    return Err(CueError::DuplicateTrack(number));
                }

                sheet.tracks.push(CueTrack {
                    number,
                    title: None,
                    performer: None,
                    index_01: None,
                });
            }

            "TITLE" => {
                let track = current_track_mut(&mut sheet, line_number, "TITLE")?;

                track.title = Some(parse_quoted_or_bare(rest, line_number, "TITLE")?);
            }

            "PERFORMER" => {
                let track = current_track_mut(&mut sheet, line_number, "PERFORMER")?;

                track.performer = Some(parse_quoted_or_bare(rest, line_number, "PERFORMER")?);
            }

            "INDEX" => {
                let mut parts = rest.split_whitespace();

                let index_number = parts.next().ok_or_else(|| CueError::InvalidLine {
                    line: line_number,
                    message: "INDEX number missing".to_string(),
                })?;

                let value = parts.next().ok_or_else(|| CueError::InvalidLine {
                    line: line_number,
                    message: "INDEX time missing".to_string(),
                })?;

                //
                // First implementation only uses INDEX 01.
                //
                if index_number != "01" {
                    continue;
                }

                let track = current_track_mut(&mut sheet, line_number, "INDEX 01")?;

                if track.index_01.is_some() {
                    return Err(CueError::DuplicateIndex01(track.number));
                }

                track.index_01 = Some(CueTime::parse(value)?);
            }

            //
            // Valid CUE directives that are not needed yet by the
            // logical-track model.
            //
            "CATALOG" | "CDTEXTFILE" | "FLAGS" | "ISRC" | "POSTGAP" | "PREGAP" | "SONGWRITER" => {
                continue;
            }

            _ => {
                return Err(CueError::InvalidLine {
                    line: line_number,
                    message: format!("unsupported directive: {command}"),
                });
            }
        }
    }

    if sheet.file.is_none() {
        return Err(CueError::InvalidLine {
            line: 0,
            message: "missing FILE directive".to_string(),
        });
    }

    if sheet.tracks.is_empty() {
        return Err(CueError::NoTracks);
    }

    for track in &sheet.tracks {
        if track.index_01.is_none() {
            return Err(CueError::MissingIndex01(track.number));
        }
    }

    Ok(sheet)
}

pub fn track_start_frames(sheet: &CueSheet, sample_rate: u32) -> Result<Vec<(u32, u64)>, CueError> {
    let mut result = Vec::with_capacity(sheet.tracks.len());

    let mut previous_frame = 0u64;

    for track in &sheet.tracks {
        let cue_time = track
            .index_01
            .ok_or(CueError::MissingIndex01(track.number))?;

        let frame = cue_time.to_source_frame(sample_rate)?;

        if frame < previous_frame {
            return Err(CueError::InvalidLine {
                line: 0,
                message: format!("TRACK {} starts before the previous track", track.number),
            });
        }

        result.push((track.number, frame));

        previous_frame = frame;
    }

    Ok(result)
}

fn split_command(line: &str) -> (&str, &str) {
    let mut split = line.splitn(2, char::is_whitespace);

    let command = split.next().unwrap_or("");

    let rest = split.next().unwrap_or("").trim();

    (command, rest)
}

fn parse_file_path(value: &str, line: usize) -> Result<String, CueError> {
    let trimmed = value.trim();

    if trimmed.is_empty() {
        return Err(CueError::InvalidLine {
            line,
            message: "FILE value missing".to_string(),
        });
    }

    //
    // Standard CUE:
    //
    // FILE "album.flac" WAVE
    //
    // The filename is the quoted token. The file type suffix
    // (WAVE/BINARY/MOTOROLA/etc.) is separate and is ignored for now.
    //
    if trimmed.starts_with('"') {
        let remainder = &trimmed[1..];

        let closing_quote = remainder.find('"').ok_or_else(|| CueError::InvalidLine {
            line,
            message: "unterminated quoted FILE".to_string(),
        })?;

        let path = &remainder[..closing_quote];

        return Ok(path.to_string());
    }

    //
    // Bare FILE form.
    //
    Ok(trimmed.split_whitespace().next().unwrap_or("").to_string())
}

fn parse_quoted_or_bare(value: &str, line: usize, directive: &str) -> Result<String, CueError> {
    let trimmed = value.trim();

    if trimmed.is_empty() {
        return Err(CueError::InvalidLine {
            line,
            message: format!("{directive} value missing"),
        });
    }

    if trimmed.starts_with('"') {
        let remainder = &trimmed[1..];

        let closing_quote = remainder.find('"').ok_or_else(|| CueError::InvalidLine {
            line,
            message: format!("unterminated quoted {directive}"),
        })?;

        return Ok(remainder[..closing_quote].to_string());
    }

    Ok(trimmed.to_string())
}

fn current_track_mut<'a>(
    sheet: &'a mut CueSheet,
    line: usize,
    directive: &str,
) -> Result<&'a mut CueTrack, CueError> {
    sheet.tracks.last_mut().ok_or_else(|| {
        if directive == "INDEX 01" {
            CueError::IndexWithoutTrack
        } else {
            CueError::InvalidLine {
                line,
                message: format!("{directive} encountered before TRACK"),
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_standard_cue_sheet() {
        let input = r#"
FILE "album.flac" WAVE
  TRACK 01 AUDIO
    TITLE "First Song"
    PERFORMER "Artist"
    INDEX 01 00:00:00

  TRACK 02 AUDIO
    TITLE "Second Song"
    PERFORMER "Artist"
    INDEX 01 03:42:15
"#;

        let sheet = parse(input).unwrap();

        assert_eq!(sheet.file, Some(PathBuf::from("album.flac")));

        assert_eq!(sheet.tracks.len(), 2);

        assert_eq!(sheet.tracks[0].number, 1);

        assert_eq!(sheet.tracks[0].title.as_deref(), Some("First Song"));

        assert_eq!(sheet.tracks[0].performer.as_deref(), Some("Artist"));

        assert_eq!(
            sheet.tracks[0].index_01,
            Some(CueTime {
                minutes: 0,
                seconds: 0,
                frames: 0,
            })
        );

        assert_eq!(
            sheet.tracks[1].index_01,
            Some(CueTime {
                minutes: 3,
                seconds: 42,
                frames: 15,
            })
        );
    }

    #[test]
    fn cue_time_validates_ranges() {
        assert!(CueTime::parse("03:42:15").is_ok());

        assert_eq!(
            CueTime::parse("03:60:00"),
            Err(CueError::InvalidTimecode {
                value: "03:60:00".to_string(),
            })
        );

        assert_eq!(
            CueTime::parse("03:42:75"),
            Err(CueError::InvalidTimecode {
                value: "03:42:75".to_string(),
            })
        );
    }

    #[test]
    fn converts_one_second_to_source_frame() {
        let time = CueTime::parse("00:01:00").unwrap();

        assert_eq!(time.to_source_frame(44_100).unwrap(), 44_100);

        assert_eq!(time.to_source_frame(48_000).unwrap(), 48_000);
    }

    #[test]
    fn converts_three_minutes_and_fraction() {
        let time = CueTime::parse("03:42:15").unwrap();

        assert_eq!(time.to_source_frame(44_100).unwrap(), 9_799_020);
    }

    #[test]
    fn converts_subsecond_cue_time_without_float() {
        let time = CueTime::parse("00:00:37").unwrap();

        //
        // floor(37 * 44100 / 75)
        // = 21756.
        //
        assert_eq!(time.to_source_frame(44_100).unwrap(), 21_756);
    }

    #[test]
    fn produces_track_start_frames() {
        let input = r#"
FILE "album.flac" WAVE
TRACK 01 AUDIO
TITLE "First"
INDEX 01 00:00:00
TRACK 02 AUDIO
TITLE "Second"
INDEX 01 03:42:15
TRACK 03 AUDIO
TITLE "Third"
INDEX 01 05:00:00
"#;

        let sheet = parse(input).unwrap();

        let frames = track_start_frames(&sheet, 44_100).unwrap();

        assert_eq!(frames, vec![(1, 0), (2, 9_799_020), (3, 13_230_000),]);
    }

    #[test]
    fn rejects_track_before_file() {
        let input = r#"
TRACK 01 AUDIO
INDEX 01 00:00:00
"#;

        assert_eq!(parse(input), Err(CueError::TrackWithoutFile));
    }

    #[test]
    fn rejects_index_before_track() {
        let input = r#"
FILE "album.flac" WAVE
INDEX 01 00:00:00
"#;

        assert_eq!(parse(input), Err(CueError::IndexWithoutTrack));
    }

    #[test]
    fn rejects_duplicate_track() {
        let input = r#"
FILE "album.flac" WAVE
TRACK 01 AUDIO
INDEX 01 00:00:00
TRACK 01 AUDIO
INDEX 01 01:00:00
"#;

        assert_eq!(parse(input), Err(CueError::DuplicateTrack(1)));
    }

    #[test]
    fn rejects_missing_index() {
        let input = r#"
FILE "album.flac" WAVE
TRACK 01 AUDIO
TITLE "First"
"#;

        assert_eq!(parse(input), Err(CueError::MissingIndex01(1)));
    }
}
