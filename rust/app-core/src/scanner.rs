use std::{
    fs, io,
    path::{Path, PathBuf},
};

use offline_player_decoder::{probe, AudioFormat, SampleFormat};
use offline_player_metadata::{
    read as read_embedded_metadata, EmbeddedMetadata as LoftyEmbeddedMetadata,
};
use thiserror::Error;

use crate::{
    cue::parse as parse_cue,
    cue_tracks::build_tracks,
    library::{AudioAsset, AudioAssetId, Track, TrackId},
    metadata_model::{
        EmbeddedMetadata, NormalizedAlbumMetadata, NormalizedMetadata, NormalizedTrackMetadata,
    },
};

#[derive(Debug, Clone)]
pub struct ScannedAsset {
    pub asset: AudioAsset,
    pub metadata: EmbeddedMetadata,
    pub normalized_metadata: NormalizedMetadata,
    pub tracks: Vec<ScannedTrack>,
}

#[derive(Debug, Clone)]
pub struct ScannedTrack {
    pub track: Track,
    pub source_path: PathBuf,
}

#[derive(Debug, Clone, Default)]
pub struct ScanResult {
    pub assets: Vec<ScannedAsset>,
    pub ignored_files: Vec<PathBuf>,
    pub errors: Vec<ScanErrorRecord>,
}

#[derive(Debug, Clone)]
pub struct ScanErrorRecord {
    pub path: PathBuf,
    pub error: String,
}

#[derive(Debug, Error)]
pub enum ScannerError {
    #[error("filesystem error for {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("probe failed for {path}: {message}")]
    Probe { path: PathBuf, message: String },

    #[error("unsupported audio format for {path}: {format}")]
    UnsupportedFormat { path: PathBuf, format: String },

    #[error("unsupported sample format for {path}: {format:?}")]
    UnsupportedSampleFormat { path: PathBuf, format: SampleFormat },

    #[error("missing total frame count for {path}")]
    MissingTotalFrames { path: PathBuf },

    #[error("embedded metadata failed for {path}: {message}")]
    Metadata { path: PathBuf, message: String },

    #[error("CUE parse failed for {path}: {message}")]
    Cue { path: PathBuf, message: String },

    #[error("CUE track construction failed for {path}: {message}")]
    CueTracks { path: PathBuf, message: String },
}

pub struct Scanner {
    next_asset_id: i64,
    next_track_id: i64,
}

impl Default for Scanner {
    fn default() -> Self {
        Self::new()
    }
}

impl Scanner {
    pub fn new() -> Self {
        Self {
            next_asset_id: 1,
            next_track_id: 1,
        }
    }

    pub fn scan_directory(&mut self, root: &Path) -> Result<ScanResult, ScannerError> {
        let mut result = ScanResult::default();

        self.scan_directory_inner(root, &mut result)?;

        result
            .assets
            .sort_by(|a, b| a.asset.path.cmp(&b.asset.path));

        result.ignored_files.sort();

        result.errors.sort_by(|a, b| a.path.cmp(&b.path));

        Ok(result)
    }

    fn scan_directory_inner(
        &mut self,
        path: &Path,
        result: &mut ScanResult,
    ) -> Result<(), ScannerError> {
        let metadata = fs::metadata(path).map_err(|source| ScannerError::Io {
            path: path.to_path_buf(),
            source,
        })?;

        if metadata.is_file() {
            self.scan_file(path, result)?;

            return Ok(());
        }

        if !metadata.is_dir() {
            return Ok(());
        }

        let mut entries = fs::read_dir(path)
            .map_err(|source| ScannerError::Io {
                path: path.to_path_buf(),
                source,
            })?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|source| ScannerError::Io {
                path: path.to_path_buf(),
                source,
            })?;

        entries.sort_by_key(|entry| entry.file_name());

        for entry in entries {
            self.scan_directory_inner(&entry.path(), result)?;
        }

        Ok(())
    }

    fn scan_file(&mut self, path: &Path, result: &mut ScanResult) -> Result<(), ScannerError> {
        if is_cue_file(path) {
            result.ignored_files.push(path.to_path_buf());

            return Ok(());
        }

        if !is_supported_audio_file(path) {
            result.ignored_files.push(path.to_path_buf());

            return Ok(());
        }

        match self.scan_audio_file(path) {
            Ok(asset) => {
                result.assets.push(asset);
            }

            Err(error) => {
                result.errors.push(ScanErrorRecord {
                    path: path.to_path_buf(),
                    error: error.to_string(),
                });
            }
        }

        Ok(())
    }

    fn scan_audio_file(&mut self, path: &Path) -> Result<ScannedAsset, ScannerError> {
        let media_info = probe(path).map_err(|error| ScannerError::Probe {
            path: path.to_path_buf(),
            message: error.to_string(),
        })?;

        validate_audio_format(path, media_info.format)?;

        let total_frames =
            media_info
                .total_frames
                .ok_or_else(|| ScannerError::MissingTotalFrames {
                    path: path.to_path_buf(),
                })?;

        let lofty_metadata =
            read_embedded_metadata(path).map_err(|error| ScannerError::Metadata {
                path: path.to_path_buf(),
                message: error.to_string(),
            })?;

        let metadata = convert_metadata(lofty_metadata);

        let normalized_metadata = normalize_metadata(path, &metadata);

        let asset_id = AudioAssetId(self.next_asset_id);

        self.next_asset_id += 1;

        let asset = AudioAsset {
            id: asset_id,

            path: path.to_path_buf(),

            sample_rate: media_info.format.sample_rate,

            channels: media_info.format.channels,

            bits_per_sample: sample_bits(media_info.format),

            total_frames: Some(total_frames),
        };

        let cue_path = find_matching_cue(path);

        let tracks = match cue_path {
            Some(cue_path) => build_cue_tracks(
                asset_id,
                &asset,
                &normalized_metadata,
                &cue_path,
                &mut self.next_track_id,
            )?,

            None => {
                vec![make_single_track(
                    asset_id,
                    &asset,
                    &normalized_metadata,
                    &mut self.next_track_id,
                )]
            }
        };

        Ok(ScannedAsset {
            asset,

            metadata,

            normalized_metadata,

            tracks,
        })
    }
}

fn make_single_track(
    asset_id: AudioAssetId,
    asset: &AudioAsset,
    metadata: &NormalizedMetadata,
    next_track_id: &mut i64,
) -> ScannedTrack {
    let id = TrackId(*next_track_id);

    *next_track_id += 1;

    let track = Track {
        id,

        asset_id,

        start_frame: 0,

        frame_count: asset.total_frames,

        disc_number: metadata.track.disc_number,

        track_number: metadata.track.track_number.unwrap_or(0),

        title: metadata.track.title.clone(),

        performer: metadata.track.artist.clone(),

        album: metadata.album.album.clone(),
    };

    ScannedTrack {
        track,

        source_path: asset.path.clone(),
    }
}

fn build_cue_tracks(
    asset_id: AudioAssetId,
    asset: &AudioAsset,
    metadata: &NormalizedMetadata,
    cue_path: &Path,
    next_track_id: &mut i64,
) -> Result<Vec<ScannedTrack>, ScannerError> {
    let cue_text = fs::read_to_string(cue_path).map_err(|source| ScannerError::Io {
        path: cue_path.to_path_buf(),
        source,
    })?;

    let sheet = parse_cue(&cue_text).map_err(|error| ScannerError::Cue {
        path: cue_path.to_path_buf(),
        message: error.to_string(),
    })?;

    let first_track_id = TrackId(*next_track_id);

    let built = build_tracks(
        asset_id,
        asset.total_frames.unwrap_or(0),
        asset.sample_rate,
        &sheet,
        first_track_id,
    )
    .map_err(|error| ScannerError::CueTracks {
        path: cue_path.to_path_buf(),
        message: error.to_string(),
    })?;

    let mut result = Vec::with_capacity(built.len());

    for built_track in built {
        let mut track = built_track.track;

        if track.album.is_none() {
            track.album = metadata.album.album.clone();
        }

        if track.performer.is_none() {
            track.performer = metadata.track.artist.clone();
        }

        if track.track_number == 0 {
            track.track_number = metadata.track.track_number.unwrap_or(0);
        }

        if track.disc_number.is_none() {
            track.disc_number = metadata.track.disc_number;
        }

        result.push(ScannedTrack {
            track,

            source_path: resolve_cue_source(cue_path, &built_track.source_file),
        });
    }

    *next_track_id += result.len() as i64;

    Ok(result)
}

fn resolve_cue_source(cue_path: &Path, source_file: &Path) -> PathBuf {
    if source_file.is_absolute() {
        source_file.to_path_buf()
    } else {
        cue_path
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join(source_file)
    }
}

fn find_matching_cue(audio_path: &Path) -> Option<PathBuf> {
    let parent = audio_path.parent()?;

    let stem = audio_path.file_stem()?;

    let exact = parent.join(format!("{}.cue", stem.to_string_lossy()));

    if exact.is_file() {
        return Some(exact);
    }

    let target_stem = stem.to_string_lossy().to_ascii_lowercase();

    let entries = fs::read_dir(parent).ok()?;

    let mut matches = Vec::<PathBuf>::new();

    for entry in entries.flatten() {
        let candidate = entry.path();

        if !is_cue_file(&candidate) {
            continue;
        }

        let Some(candidate_stem) = candidate.file_stem() else {
            continue;
        };

        if candidate_stem.to_string_lossy().to_ascii_lowercase() == target_stem {
            matches.push(candidate);
        }
    }

    matches.sort();

    matches.into_iter().next()
}

fn convert_metadata(source: LoftyEmbeddedMetadata) -> EmbeddedMetadata {
    EmbeddedMetadata {
        title: source.title,

        artist: source.artist,

        album: source.album,

        album_artist: source.album_artist,

        composer: source.composer,

        genre: source.genre,

        date: source.date,

        track_number: source.track_number,

        disc_number: source.disc_number,

        artwork: source.artwork,
    }
}

fn normalize_metadata(path: &Path, embedded: &EmbeddedMetadata) -> NormalizedMetadata {
    NormalizedMetadata {
        source_path: path.to_path_buf(),

        album: NormalizedAlbumMetadata {
            album: embedded.album.clone(),

            album_artist: embedded.album_artist.clone(),

            date: embedded.date.clone(),

            genre: embedded.genre.clone(),
        },

        track: NormalizedTrackMetadata {
            title: embedded.title.clone(),

            artist: embedded.artist.clone(),

            track_number: embedded.track_number,

            disc_number: embedded.disc_number,

            composer: embedded.composer.clone(),
        },
    }
}

fn sample_bits(format: AudioFormat) -> u16 {
    match format.sample_format {
        SampleFormat::SignedInt(bits) | SampleFormat::Float(bits) => bits,
    }
}

fn validate_audio_format(path: &Path, format: AudioFormat) -> Result<(), ScannerError> {
    if format.sample_rate == 0 {
        return Err(ScannerError::UnsupportedFormat {
            path: path.to_path_buf(),

            format: "zero sample rate".to_owned(),
        });
    }

    if format.channels == 0 {
        return Err(ScannerError::UnsupportedFormat {
            path: path.to_path_buf(),

            format: "zero channels".to_owned(),
        });
    }

    match format.sample_format {
        SampleFormat::SignedInt(8)
        | SampleFormat::SignedInt(16)
        | SampleFormat::SignedInt(24)
        | SampleFormat::SignedInt(32) => Ok(()),

        other => Err(ScannerError::UnsupportedSampleFormat {
            path: path.to_path_buf(),

            format: other,
        }),
    }
}

fn is_supported_audio_file(path: &Path) -> bool {
    let Some(extension) = path.extension() else {
        return false;
    };

    matches!(
        extension.to_string_lossy().to_ascii_lowercase().as_str(),
        "flac" | "wav" | "aiff" | "aif" | "mp3" | "m4a" | "aac" | "ogg" | "oga" | "opus"
    )
}

fn is_cue_file(path: &Path) -> bool {
    path.extension()
        .map(|extension| extension.to_string_lossy().eq_ignore_ascii_case("cue"))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_supported_audio_extensions() {
        assert!(is_supported_audio_file(Path::new("album.FLAC")));

        assert!(is_supported_audio_file(Path::new("album.wav")));

        assert!(is_supported_audio_file(Path::new("album.aiff")));

        assert!(is_supported_audio_file(Path::new("album.mp3")));

        assert!(!is_supported_audio_file(Path::new("cover.jpg")));

        assert!(!is_supported_audio_file(Path::new("book.pdf")));
    }

    #[test]
    fn recognizes_cue_extension_case_insensitively() {
        assert!(is_cue_file(Path::new("album.CUE")));

        assert!(is_cue_file(Path::new("album.cue")));

        assert!(!is_cue_file(Path::new("album.flac")));
    }

    #[test]
    fn converts_lofty_metadata() {
        let source = LoftyEmbeddedMetadata {
            title: Some("Track".to_owned()),

            artist: Some("Artist".to_owned()),

            album: Some("Album".to_owned()),

            album_artist: Some("Album Artist".to_owned()),

            composer: Some("Composer".to_owned()),

            genre: Some("Genre".to_owned()),

            date: Some("2025".to_owned()),

            track_number: Some(8),

            disc_number: Some(1),

            artwork: None,
        };

        let converted = convert_metadata(source);

        assert_eq!(converted.title.as_deref(), Some("Track"));

        assert_eq!(converted.artist.as_deref(), Some("Artist"));

        assert_eq!(converted.album.as_deref(), Some("Album"));

        assert_eq!(converted.album_artist.as_deref(), Some("Album Artist"));

        assert_eq!(converted.composer.as_deref(), Some("Composer"));

        assert_eq!(converted.genre.as_deref(), Some("Genre"));

        assert_eq!(converted.date.as_deref(), Some("2025"));

        assert_eq!(converted.track_number, Some(8));

        assert_eq!(converted.disc_number, Some(1));
    }

    #[test]
    fn scanner_starts_ids_at_one() {
        let scanner = Scanner::new();

        assert_eq!(scanner.next_asset_id, 1);

        assert_eq!(scanner.next_track_id, 1);
    }
}
