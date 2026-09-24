use std::path::{Path, PathBuf};

pub use offline_player_db::StoredArtwork;
use offline_player_db::{
    ArtworkRecord, AssetRecord, DbError, LibraryRepository, PersistedAsset, TrackRecord,
};
use rusqlite::OptionalExtension;
use thiserror::Error;

use crate::{
    library::AudioAsset,
    metadata_model::NormalizedMetadata,
    playback_model::PlaybackTrack,
    scanner::{ScannedAsset, ScannedTrack},
};

#[derive(Debug, Error)]
pub enum LibraryStoreError {
    #[error("database error: {0}")]
    Db(#[from] DbError),

    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),

    #[error("missing total frame count for asset: {path}")]
    MissingTotalFrames { path: PathBuf },

    #[error("invalid sample rate for asset: {path}")]
    InvalidSampleRate { path: PathBuf },

    #[error("invalid channel count for asset: {path}")]
    InvalidChannels { path: PathBuf },

    #[error("invalid bits per sample for asset: {path}")]
    InvalidBitsPerSample { path: PathBuf },

    #[error("channel count out of supported range for asset: {path}")]
    ChannelsOutOfRange { path: PathBuf },

    #[error("negative SQLite frame value for {field}: {value}")]
    NegativeFrameValue { field: &'static str, value: i64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredScan {
    pub asset_id: i64,
    pub track_ids: Vec<i64>,
}

impl From<PersistedAsset> for StoredScan {
    fn from(value: PersistedAsset) -> Self {
        Self {
            asset_id: value.asset_id,
            track_ids: value.track_ids,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub composer: Option<String>,
    pub date: Option<String>,
    pub genre: Option<String>,
    pub track_number: u32,
    pub disc_number: Option<u32>,
}

pub struct LibraryStore {
    connection: rusqlite::Connection,
}

impl LibraryStore {
    pub fn open(path: &Path) -> Result<Self, LibraryStoreError> {
        let connection = offline_player_db::open(path)?;

        Ok(Self { connection })
    }

    pub fn open_in_memory() -> Result<Self, LibraryStoreError> {
        let connection = offline_player_db::open_in_memory()?;

        Ok(Self { connection })
    }

    pub fn persist_scan(
        &mut self,
        scanned: &ScannedAsset,
    ) -> Result<StoredScan, LibraryStoreError> {
        validate_asset(&scanned.asset)?;

        let total_frames =
            scanned
                .asset
                .total_frames
                .ok_or_else(|| LibraryStoreError::MissingTotalFrames {
                    path: scanned.asset.path.clone(),
                })?;

        let channels = u16::try_from(scanned.asset.channels).map_err(|_| {
            LibraryStoreError::ChannelsOutOfRange {
                path: scanned.asset.path.clone(),
            }
        })?;

        let asset = AssetRecord {
            path: scanned.asset.path.to_string_lossy().into_owned(),
            sample_rate: scanned.asset.sample_rate,
            channels,
            bits_per_sample: scanned.asset.bits_per_sample,
            total_frames: Some(total_frames),
            codec: None,
        };

        let tracks = scanned
            .tracks
            .iter()
            .map(|track| {
                track_record_from_scanned(
                    track,
                    &scanned.normalized_metadata,
                    scanned.metadata.artwork.as_ref(),
                )
            })
            .collect::<Vec<_>>();

        let mut repository = LibraryRepository::new(&mut self.connection);

        let persisted = repository.upsert_asset_with_ids(&asset, &tracks)?;

        Ok(persisted.into())
    }

    pub fn remove_assets_missing_from_scan(
        &mut self,
        root: &Path,
        scanned_paths: &[String],
    ) -> Result<usize, LibraryStoreError> {
        let mut repository = LibraryRepository::new(&mut self.connection);

        Ok(repository.remove_assets_missing_from_scan(root, scanned_paths)?)
    }

    pub fn asset_count(&self) -> Result<i64, LibraryStoreError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM assets", [], |row| row.get(0))?)
    }

    pub fn track_count(&self) -> Result<i64, LibraryStoreError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM tracks", [], |row| row.get(0))?)
    }

    pub fn artist_count(&self) -> Result<i64, LibraryStoreError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM artists", [], |row| row.get(0))?)
    }

    pub fn album_count(&self) -> Result<i64, LibraryStoreError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM albums", [], |row| row.get(0))?)
    }

    pub fn track_title(&self, track_id: i64) -> Result<Option<String>, LibraryStoreError> {
        let title = self
            .connection
            .query_row(
                r#"
                SELECT title
                FROM tracks
                WHERE id = ?1
                "#,
                [track_id],
                |row| row.get(0),
            )
            .optional()?;

        Ok(title)
    }

    pub fn track_artwork(&self, track_id: i64) -> Result<Option<StoredArtwork>, LibraryStoreError> {
        let artwork = self
            .connection
            .query_row(
                r#"
                SELECT
                    artworks.mime_type,
                    artworks.path,
                    artworks.data,
                    artworks.width,
                    artworks.height
                FROM tracks
                INNER JOIN artworks
                    ON artworks.album_id = tracks.album_id
                WHERE tracks.id = ?1
                "#,
                [track_id],
                |row| {
                    Ok(StoredArtwork {
                        mime_type: row.get(0)?,
                        path: row.get(1)?,
                        data: row.get(2)?,
                        width: row.get(3)?,
                        height: row.get(4)?,
                    })
                },
            )
            .optional()?;

        Ok(artwork)
    }

    pub fn track_metadata(
        &self,
        track_id: i64,
    ) -> Result<Option<TrackMetadata>, LibraryStoreError> {
        let metadata = self
            .connection
            .query_row(
                r#"
                SELECT
                    t.title,
                    track_artist.name,
                    albums.title,
                    album_artist.name,
                    t.composer,
                    albums.date,
                    albums.genre,
                    t.track_number,
                    t.disc_number
                FROM tracks AS t
                LEFT JOIN artists AS track_artist
                    ON track_artist.id = t.artist_id
                LEFT JOIN albums
                    ON albums.id = t.album_id
                LEFT JOIN artists AS album_artist
                    ON album_artist.id = albums.album_artist_id
                WHERE t.id = ?1
                "#,
                [track_id],
                |row| {
                    let track_number: i64 = row.get(7)?;
                    let disc_number: Option<i64> = row.get(8)?;

                    let track_number = u32::try_from(track_number)
                        .map_err(|_| rusqlite::Error::IntegralValueOutOfRange(7, track_number))?;

                    let disc_number = match disc_number {
                        Some(value) => Some(
                            u32::try_from(value)
                                .map_err(|_| rusqlite::Error::IntegralValueOutOfRange(8, value))?,
                        ),
                        None => None,
                    };

                    Ok(TrackMetadata {
                        title: row.get(0)?,
                        artist: row.get(1)?,
                        album: row.get(2)?,
                        album_artist: row.get(3)?,
                        composer: row.get(4)?,
                        date: row.get(5)?,
                        genre: row.get(6)?,
                        track_number,
                        disc_number,
                    })
                },
            )
            .optional()?;

        Ok(metadata)
    }

    pub fn playback_track(
        &self,
        track_id: i64,
    ) -> Result<Option<PlaybackTrack>, LibraryStoreError> {
        let result = self
            .connection
            .query_row(
                r#"
                SELECT
                    t.id,
                    t.asset_id,
                    a.path,
                    a.sample_rate,
                    a.channels,
                    a.bits_per_sample,
                    t.start_frame,
                    t.frame_count
                FROM tracks AS t
                INNER JOIN assets AS a
                    ON a.id = t.asset_id
                WHERE t.id = ?1
                "#,
                [track_id],
                |row| {
                    let path: String = row.get(2)?;

                    let start_frame_raw: i64 = row.get(6)?;

                    let frame_count_raw: Option<i64> = row.get(7)?;

                    let start_frame =
                        non_negative_frame("start_frame", start_frame_raw).map_err(|error| {
                            rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                        })?;

                    let frame_count = match frame_count_raw {
                        Some(value) => {
                            Some(non_negative_frame("frame_count", value).map_err(|error| {
                                rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                            })?)
                        }
                        None => None,
                    };

                    Ok(PlaybackTrack {
                        track_id: row.get(0)?,
                        asset_id: row.get(1)?,
                        path: PathBuf::from(path),
                        sample_rate: row.get(3)?,
                        channels: row.get(4)?,
                        bits_per_sample: row.get(5)?,
                        start_frame,
                        frame_count,
                    })
                },
            )
            .optional()?;

        Ok(result)
    }

    pub fn playback_tracks(&self) -> Result<Vec<PlaybackTrack>, LibraryStoreError> {
        let mut statement = self.connection.prepare(
            r#"
            SELECT
                t.id,
                t.asset_id,
                a.path,
                a.sample_rate,
                a.channels,
                a.bits_per_sample,
                t.start_frame,
                t.frame_count
            FROM tracks AS t
            INNER JOIN assets AS a
                ON a.id = t.asset_id
            ORDER BY
                COALESCE(t.disc_number, 0),
                t.track_number,
                t.id
            "#,
        )?;

        let rows = statement.query_map([], |row| {
            let path: String = row.get(2)?;

            let start_frame_raw: i64 = row.get(6)?;

            let frame_count_raw: Option<i64> = row.get(7)?;

            let start_frame = non_negative_frame("start_frame", start_frame_raw)
                .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;

            let frame_count = match frame_count_raw {
                Some(value) => {
                    Some(non_negative_frame("frame_count", value).map_err(|error| {
                        rusqlite::Error::ToSqlConversionFailure(Box::new(error))
                    })?)
                }
                None => None,
            };

            Ok(PlaybackTrack {
                track_id: row.get(0)?,
                asset_id: row.get(1)?,
                path: PathBuf::from(path),
                sample_rate: row.get(3)?,
                channels: row.get(4)?,
                bits_per_sample: row.get(5)?,
                start_frame,
                frame_count,
            })
        })?;

        let mut tracks = Vec::new();

        for row in rows {
            tracks.push(row?);
        }

        Ok(tracks)
    }
}

fn validate_asset(asset: &AudioAsset) -> Result<(), LibraryStoreError> {
    if asset.sample_rate == 0 {
        return Err(LibraryStoreError::InvalidSampleRate {
            path: asset.path.clone(),
        });
    }

    if asset.channels == 0 {
        return Err(LibraryStoreError::InvalidChannels {
            path: asset.path.clone(),
        });
    }

    if !matches!(asset.bits_per_sample, 8 | 16 | 24 | 32) {
        return Err(LibraryStoreError::InvalidBitsPerSample {
            path: asset.path.clone(),
        });
    }

    if asset.total_frames.is_none() {
        return Err(LibraryStoreError::MissingTotalFrames {
            path: asset.path.clone(),
        });
    }

    Ok(())
}

fn track_record_from_scanned(
    scanned: &ScannedTrack,
    normalized: &NormalizedMetadata,
    artwork: Option<&offline_player_metadata::EmbeddedArtwork>,
) -> TrackRecord {
    TrackRecord {
        title: scanned.track.title.clone(),
        artist: scanned.track.performer.clone(),
        album: scanned.track.album.clone(),
        album_artist: normalized.album.album_artist.clone(),
        date: normalized.album.date.clone(),
        genre: normalized.album.genre.clone(),
        composer: normalized.track.composer.clone(),
        track_number: scanned.track.track_number,
        disc_number: scanned.track.disc_number,
        start_frame: scanned.track.start_frame,
        frame_count: scanned.track.frame_count,
        artwork: artwork.map(|artwork| ArtworkRecord {
            mime_type: artwork.mime_type.clone(),
            path: None,
            data: artwork.data.clone(),
            width: None,
            height: None,
        }),
    }
}

fn non_negative_frame(field: &'static str, value: i64) -> Result<u64, LibraryStoreError> {
    if value < 0 {
        return Err(LibraryStoreError::NegativeFrameValue { field, value });
    }

    Ok(value as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::{
        library::{AudioAssetId, Track, TrackId},
        metadata_model::{
            EmbeddedMetadata, NormalizedAlbumMetadata, NormalizedMetadata, NormalizedTrackMetadata,
        },
    };

    fn scanned_asset() -> ScannedAsset {
        let asset_path = PathBuf::from("/music/test.flac");

        let asset = AudioAsset {
            id: AudioAssetId(1),
            path: asset_path.clone(),
            sample_rate: 44_100,
            channels: 2,
            bits_per_sample: 24,
            total_frames: Some(44_100),
        };

        let track = Track {
            id: TrackId(1),
            asset_id: asset.id,
            start_frame: 0,
            frame_count: Some(44_100),
            disc_number: Some(1),
            track_number: 7,
            title: Some("Test Track".to_owned()),
            performer: Some("Test Artist".to_owned()),
            album: Some("Test Album".to_owned()),
        };

        ScannedAsset {
            asset,
            metadata: EmbeddedMetadata {
                title: Some("Test Track".to_owned()),
                artist: Some("Test Artist".to_owned()),
                album: Some("Test Album".to_owned()),
                album_artist: Some("Test Album Artist".to_owned()),
                composer: Some("Test Composer".to_owned()),
                genre: Some("Test Genre".to_owned()),
                date: Some("2026".to_owned()),
                track_number: Some(7),
                disc_number: Some(1),
                artwork: None,
            },
            normalized_metadata: NormalizedMetadata {
                source_path: asset_path.clone(),
                album: NormalizedAlbumMetadata {
                    album: Some("Test Album".to_owned()),
                    album_artist: Some("Test Album Artist".to_owned()),
                    date: Some("2026".to_owned()),
                    genre: Some("Test Genre".to_owned()),
                },
                track: NormalizedTrackMetadata {
                    title: Some("Test Track".to_owned()),
                    artist: Some("Test Artist".to_owned()),
                    track_number: Some(7),
                    disc_number: Some(1),
                    composer: Some("Test Composer".to_owned()),
                },
            },
            tracks: vec![ScannedTrack {
                track,
                source_path: asset_path,
            }],
        }
    }

    #[test]
    fn playback_tracks_returns_all_tracks_in_order() -> Result<(), LibraryStoreError> {
        let mut store = LibraryStore::open_in_memory()?;

        store.persist_scan(&scanned_asset())?;

        let tracks = store.playback_tracks()?;

        assert_eq!(tracks.len(), 1);
        assert_eq!(tracks[0].track_id, 1);
        assert_eq!(tracks[0].asset_id, 1);
        assert_eq!(tracks[0].start_frame, 0);
        assert_eq!(tracks[0].frame_count, Some(44_100));

        Ok(())
    }

    #[test]
    fn playback_tracks_returns_empty_when_library_is_empty() -> Result<(), LibraryStoreError> {
        let store = LibraryStore::open_in_memory()?;

        let tracks = store.playback_tracks()?;

        assert!(tracks.is_empty());

        Ok(())
    }

    #[test]
    fn persists_scanned_asset() -> Result<(), LibraryStoreError> {
        let mut store = LibraryStore::open_in_memory()?;

        let stored = store.persist_scan(&scanned_asset())?;

        assert_eq!(stored.asset_id, 1);
        assert_eq!(stored.track_ids, vec![1]);
        assert_eq!(store.asset_count()?, 1);
        assert_eq!(store.track_count()?, 1);
        assert_eq!(store.artist_count()?, 2);
        assert_eq!(store.album_count()?, 1);

        assert_eq!(store.track_title(1)?.as_deref(), Some("Test Track"));

        Ok(())
    }

    #[test]
    fn track_metadata_returns_expected_values() -> Result<(), LibraryStoreError> {
        let mut store = LibraryStore::open_in_memory()?;

        store.persist_scan(&scanned_asset())?;

        let metadata = store
            .track_metadata(1)?
            .expect("track metadata should exist");

        assert_eq!(metadata.title.as_deref(), Some("Test Track"));

        assert_eq!(metadata.artist.as_deref(), Some("Test Artist"));

        assert_eq!(metadata.album.as_deref(), Some("Test Album"));

        assert_eq!(metadata.album_artist.as_deref(), Some("Test Album Artist"));

        assert_eq!(metadata.composer.as_deref(), Some("Test Composer"));

        assert_eq!(metadata.date.as_deref(), Some("2026"));

        assert_eq!(metadata.genre.as_deref(), Some("Test Genre"));

        assert_eq!(metadata.track_number, 7);
        assert_eq!(metadata.disc_number, Some(1));

        Ok(())
    }

    #[test]
    fn track_metadata_returns_none_for_unknown_id() -> Result<(), LibraryStoreError> {
        let store = LibraryStore::open_in_memory()?;

        assert_eq!(store.track_metadata(999)?, None);

        Ok(())
    }

    #[test]
    fn playback_track_lookup_returns_expected_mapping() -> Result<(), LibraryStoreError> {
        let mut store = LibraryStore::open_in_memory()?;

        store.persist_scan(&scanned_asset())?;

        let track = store.playback_track(1)?.expect("track 1 must exist");

        assert_eq!(track.track_id, 1);
        assert_eq!(track.asset_id, 1);
        assert_eq!(track.path, PathBuf::from("/music/test.flac"));
        assert_eq!(track.sample_rate, 44_100);
        assert_eq!(track.channels, 2);
        assert_eq!(track.bits_per_sample, 24);
        assert_eq!(track.start_frame, 0);
        assert_eq!(track.frame_count, Some(44_100));

        Ok(())
    }

    #[test]
    fn playback_track_lookup_returns_none_for_unknown_id() -> Result<(), LibraryStoreError> {
        let store = LibraryStore::open_in_memory()?;

        assert!(store.playback_track(999)?.is_none());

        Ok(())
    }

    #[test]
    fn persists_embedded_artwork() -> Result<(), LibraryStoreError> {
        use offline_player_metadata::EmbeddedArtwork;

        let mut store = LibraryStore::open_in_memory()?;

        let mut scan = scanned_asset();

        scan.metadata.artwork = Some(EmbeddedArtwork {
            mime_type: Some("image/jpeg".to_owned()),
            data: vec![1, 2, 3, 4, 5],
        });

        store.persist_scan(&scan)?;

        let artwork = store
            .track_artwork(1)?
            .expect("embedded artwork should be persisted");

        assert_eq!(artwork.mime_type.as_deref(), Some("image/jpeg"));
        assert_eq!(artwork.data, vec![1, 2, 3, 4, 5]);
        assert_eq!(artwork.path, None);
        assert_eq!(artwork.width, None);
        assert_eq!(artwork.height, None);

        Ok(())
    }

    #[test]
    fn track_artwork_returns_none_for_unknown_id() -> Result<(), LibraryStoreError> {
        let mut store = LibraryStore::open_in_memory()?;

        assert_eq!(store.track_artwork(999)?, None);

        Ok(())
    }

    #[test]
    fn persist_is_idempotent_for_same_scan() -> Result<(), LibraryStoreError> {
        let mut store = LibraryStore::open_in_memory()?;

        let scan = scanned_asset();

        let first = store.persist_scan(&scan)?;

        let second = store.persist_scan(&scan)?;

        assert_eq!(first.asset_id, second.asset_id);

        assert_eq!(first.track_ids, second.track_ids);

        assert_eq!(store.asset_count()?, 1);

        assert_eq!(store.track_count()?, 1);

        Ok(())
    }
}
