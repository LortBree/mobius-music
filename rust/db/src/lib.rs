use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DbError {
    #[error("sqlite error: {0}")]
    Sql(#[from] rusqlite::Error),

    #[error("unsupported schema version: {0}")]
    UnsupportedSchemaVersion(i64),
}

const SCHEMA_VERSION: i64 = 1;

const SCHEMA_SQL: &str = r#"
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_info (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    version INTEGER NOT NULL
);

INSERT INTO schema_info (id, version)
VALUES (1, 1)
ON CONFLICT(id) DO NOTHING;

CREATE TABLE IF NOT EXISTS artists (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    sort_name TEXT,
    UNIQUE(name)
);

CREATE TABLE IF NOT EXISTS albums (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    album_artist_id INTEGER,
    date TEXT,
    genre TEXT,
    FOREIGN KEY (album_artist_id)
        REFERENCES artists(id)
        ON DELETE SET NULL,
    UNIQUE(title, album_artist_id)
);

CREATE TABLE IF NOT EXISTS assets (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL,
    sample_rate INTEGER NOT NULL,
    channels INTEGER NOT NULL,
    bits_per_sample INTEGER NOT NULL,
    total_frames INTEGER,
    codec TEXT,
    UNIQUE(path)
);

CREATE TABLE IF NOT EXISTS tracks (
    id INTEGER PRIMARY KEY,
    asset_id INTEGER NOT NULL,
    album_id INTEGER,
    artist_id INTEGER,
    title TEXT NOT NULL,
    track_number INTEGER NOT NULL,
    disc_number INTEGER,
    start_frame INTEGER NOT NULL,
    frame_count INTEGER,
    composer TEXT,
    FOREIGN KEY (asset_id)
        REFERENCES assets(id)
        ON DELETE CASCADE,
    FOREIGN KEY (album_id)
        REFERENCES albums(id)
        ON DELETE SET NULL,
    FOREIGN KEY (artist_id)
        REFERENCES artists(id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_tracks_asset_id
    ON tracks(asset_id);

CREATE INDEX IF NOT EXISTS idx_tracks_album_id
    ON tracks(album_id);

CREATE INDEX IF NOT EXISTS idx_tracks_artist_id
    ON tracks(artist_id);

CREATE TABLE IF NOT EXISTS artworks (
    id INTEGER PRIMARY KEY,
    album_id INTEGER,
    mime_type TEXT,
    path TEXT,
    data BLOB,
    width INTEGER,
    height INTEGER,
    FOREIGN KEY (album_id)
        REFERENCES albums(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_artworks_album_id
    ON artworks(album_id);

CREATE TABLE IF NOT EXISTS playlists (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id INTEGER NOT NULL,
    position INTEGER NOT NULL,
    track_id INTEGER NOT NULL,
    added_at INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, position),
    FOREIGN KEY (playlist_id)
        REFERENCES playlists(id)
        ON DELETE CASCADE,
    FOREIGN KEY (track_id)
        REFERENCES tracks(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_playlist_tracks_track_id
    ON playlist_tracks(track_id);

CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY,
    track_id INTEGER NOT NULL,
    played_at INTEGER NOT NULL,
    position_frame INTEGER,
    FOREIGN KEY (track_id)
        REFERENCES tracks(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_history_track_id
    ON history(track_id);

CREATE INDEX IF NOT EXISTS idx_history_played_at
    ON history(played_at);

CREATE TABLE IF NOT EXISTS favorites (
    track_id INTEGER PRIMARY KEY,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (track_id)
        REFERENCES tracks(id)
        ON DELETE CASCADE
);
"#;

#[derive(Debug, Clone)]
pub struct AssetRecord {
    pub path: String,
    pub sample_rate: u32,
    pub channels: u16,
    pub bits_per_sample: u16,
    pub total_frames: Option<u64>,
    pub codec: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtworkRecord {
    pub mime_type: Option<String>,
    pub path: Option<String>,
    pub data: Vec<u8>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct TrackRecord {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub date: Option<String>,
    pub genre: Option<String>,
    pub composer: Option<String>,
    pub track_number: u32,
    pub disc_number: Option<u32>,
    pub start_frame: u64,
    pub frame_count: Option<u64>,
    pub artwork: Option<ArtworkRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PersistedAsset {
    pub asset_id: i64,
    pub track_ids: Vec<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredArtwork {
    pub mime_type: Option<String>,
    pub path: Option<String>,
    pub data: Vec<u8>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

pub struct LibraryRepository<'a> {
    connection: &'a mut Connection,
}

impl<'a> LibraryRepository<'a> {
    pub fn new(connection: &'a mut Connection) -> Self {
        Self { connection }
    }

    pub fn upsert_asset(
        &mut self,
        asset: &AssetRecord,
        tracks: &[TrackRecord],
    ) -> Result<i64, DbError> {
        Ok(self.upsert_asset_with_ids(asset, tracks)?.asset_id)
    }

    pub fn upsert_asset_with_ids(
        &mut self,
        asset: &AssetRecord,
        tracks: &[TrackRecord],
    ) -> Result<PersistedAsset, DbError> {
        let transaction = self.connection.transaction()?;

        let asset_id = {
            transaction.execute(
                r#"
                INSERT INTO assets (
                    path,
                    sample_rate,
                    channels,
                    bits_per_sample,
                    total_frames,
                    codec
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                ON CONFLICT(path) DO UPDATE SET
                    sample_rate = excluded.sample_rate,
                    channels = excluded.channels,
                    bits_per_sample = excluded.bits_per_sample,
                    total_frames = excluded.total_frames,
                    codec = excluded.codec
                "#,
                params![
                    asset.path,
                    i64::from(asset.sample_rate),
                    i64::from(asset.channels),
                    i64::from(asset.bits_per_sample),
                    asset.total_frames.map(|value| value as i64),
                    asset.codec,
                ],
            )?;

            transaction.query_row(
                "SELECT id FROM assets WHERE path = ?1",
                params![asset.path],
                |row| row.get::<_, i64>(0),
            )?
        };

        let mut persisted_track_ids = Vec::with_capacity(tracks.len());

        for track in tracks {
            let artist_id = match normalize_optional_string(track.artist.as_deref()) {
                Some(name) => Some(upsert_artist(&transaction, name)?),
                None => None,
            };

            let album_artist_id = match normalize_optional_string(track.album_artist.as_deref()) {
                Some(name) => Some(upsert_artist(&transaction, name)?),
                None => None,
            };

            let album_id = match normalize_optional_string(track.album.as_deref()) {
                Some(title) => Some(upsert_album(
                    &transaction,
                    title,
                    album_artist_id,
                    track.date.as_deref(),
                    track.genre.as_deref(),
                )?),
                None => None,
            };

            if let (Some(album_id), Some(artwork)) = (album_id, track.artwork.as_ref()) {
                upsert_artwork(&transaction, album_id, artwork)?;
            }

            let title = track
                .title
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("<untitled>");

            let start_frame = i64::try_from(track.start_frame)
                .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))?;

            let frame_count = track
                .frame_count
                .map(|value| {
                    i64::try_from(value)
                        .map_err(|error| rusqlite::Error::ToSqlConversionFailure(Box::new(error)))
                })
                .transpose()?;

            let disc_number = track.disc_number.map(i64::from);
            let track_number = i64::from(track.track_number);

            let existing_id = transaction
                .query_row(
                    r#"
                    SELECT id
                    FROM tracks
                    WHERE asset_id = ?1
                      AND track_number = ?2
                      AND disc_number IS ?3
                      AND start_frame = ?4
                    LIMIT 1
                    "#,
                    params![asset_id, track_number, disc_number, start_frame,],
                    |row| row.get::<_, i64>(0),
                )
                .optional()?;

            let track_id = match existing_id {
                Some(track_id) => {
                    transaction.execute(
                        r#"
                        UPDATE tracks
                        SET
                            album_id = ?1,
                            artist_id = ?2,
                            title = ?3,
                            track_number = ?4,
                            disc_number = ?5,
                            start_frame = ?6,
                            frame_count = ?7,
                            composer = ?8
                        WHERE id = ?9
                        "#,
                        params![
                            album_id,
                            artist_id,
                            title,
                            track_number,
                            disc_number,
                            start_frame,
                            frame_count,
                            track.composer,
                            track_id,
                        ],
                    )?;

                    track_id
                }
                None => {
                    transaction.execute(
                        r#"
                        INSERT INTO tracks (
                            asset_id,
                            album_id,
                            artist_id,
                            title,
                            track_number,
                            disc_number,
                            start_frame,
                            frame_count,
                            composer
                        )
                        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
                        "#,
                        params![
                            asset_id,
                            album_id,
                            artist_id,
                            title,
                            track_number,
                            disc_number,
                            start_frame,
                            frame_count,
                            track.composer,
                        ],
                    )?;

                    transaction.last_insert_rowid()
                }
            };

            persisted_track_ids.push(track_id);
        }

        let existing_ids = {
            let mut statement = transaction.prepare("SELECT id FROM tracks WHERE asset_id = ?1")?;

            let rows = statement.query_map(params![asset_id], |row| row.get::<_, i64>(0))?;

            rows.collect::<Result<Vec<_>, _>>()?
        };

        for existing_id in existing_ids {
            if !persisted_track_ids.contains(&existing_id) {
                transaction.execute("DELETE FROM tracks WHERE id = ?1", params![existing_id])?;
            }
        }

        transaction.commit()?;

        Ok(PersistedAsset {
            asset_id,
            track_ids: persisted_track_ids,
        })
    }

    pub fn remove_assets_missing_from_scan(
        &mut self,
        root: &Path,
        scanned_paths: &[String],
    ) -> Result<usize, DbError> {
        use std::collections::HashSet;

        let scanned = scanned_paths
            .iter()
            .map(|path| Path::new(path).to_path_buf())
            .collect::<HashSet<_>>();

        let transaction = self.connection.transaction()?;

        let existing_paths = {
            let mut statement = transaction.prepare("SELECT id, path FROM assets")?;

            let rows = statement.query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })?;

            rows.collect::<Result<Vec<_>, _>>()?
        };

        let mut removed = 0usize;

        for (asset_id, path) in existing_paths {
            let path_buf = Path::new(&path);

            if path_buf.starts_with(root) && !scanned.contains(path_buf) {
                transaction.execute("DELETE FROM assets WHERE id = ?1", params![asset_id])?;
                removed += 1;
            }
        }

        transaction.commit()?;

        Ok(removed)
    }

    pub fn asset_count(&self) -> Result<i64, DbError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM assets", [], |row| row.get(0))?)
    }

    pub fn track_count(&self) -> Result<i64, DbError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM tracks", [], |row| row.get(0))?)
    }

    pub fn artist_count(&self) -> Result<i64, DbError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM artists", [], |row| row.get(0))?)
    }

    pub fn album_count(&self) -> Result<i64, DbError> {
        Ok(self
            .connection
            .query_row("SELECT COUNT(*) FROM albums", [], |row| row.get(0))?)
    }

    pub fn track_title(&self, asset_id: i64, track_number: u32) -> Result<Option<String>, DbError> {
        Ok(self
            .connection
            .query_row(
                r#"
                SELECT title
                FROM tracks
                WHERE asset_id = ?1
                  AND track_number = ?2
                ORDER BY start_frame
                LIMIT 1
                "#,
                params![asset_id, i64::from(track_number)],
                |row| row.get(0),
            )
            .optional()?)
    }

    pub fn track_artwork(&self, track_id: i64) -> Result<Option<StoredArtwork>, DbError> {
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
                ORDER BY artworks.id
                LIMIT 1
                "#,
                params![track_id],
                |row| {
                    let data: Option<Vec<u8>> = row.get(2)?;

                    Ok(StoredArtwork {
                        mime_type: row.get(0)?,
                        path: row.get(1)?,
                        data: data.unwrap_or_default(),
                        width: row.get(3)?,
                        height: row.get(4)?,
                    })
                },
            )
            .optional()?;

        Ok(artwork)
    }
}

fn normalize_optional_string(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|value| !value.is_empty())
}

fn upsert_artist(connection: &Connection, name: &str) -> Result<i64, rusqlite::Error> {
    connection.execute(
        r#"
        INSERT INTO artists (name)
        VALUES (?1)
        ON CONFLICT(name) DO NOTHING
        "#,
        params![name],
    )?;

    connection.query_row(
        "SELECT id FROM artists WHERE name = ?1",
        params![name],
        |row| row.get(0),
    )
}

fn upsert_album(
    connection: &Connection,
    title: &str,
    album_artist_id: Option<i64>,
    date: Option<&str>,
    genre: Option<&str>,
) -> Result<i64, rusqlite::Error> {
    let existing_id = connection
        .query_row(
            r#"
            SELECT id
            FROM albums
            WHERE title = ?1
              AND (
                    album_artist_id = ?2
                    OR (album_artist_id IS NULL AND ?2 IS NULL)
              )
            LIMIT 1
            "#,
            params![title, album_artist_id],
            |row| row.get::<_, i64>(0),
        )
        .optional()?;

    if let Some(id) = existing_id {
        connection.execute(
            r#"
            UPDATE albums
            SET
                date = COALESCE(?1, date),
                genre = COALESCE(?2, genre)
            WHERE id = ?3
            "#,
            params![date, genre, id],
        )?;

        return Ok(id);
    }

    connection.execute(
        r#"
        INSERT INTO albums (
            title,
            album_artist_id,
            date,
            genre
        )
        VALUES (?1, ?2, ?3, ?4)
        "#,
        params![title, album_artist_id, date, genre],
    )?;

    Ok(connection.last_insert_rowid())
}

fn upsert_artwork(
    connection: &Connection,
    album_id: i64,
    artwork: &ArtworkRecord,
) -> Result<i64, rusqlite::Error> {
    let existing_id = connection
        .query_row(
            r#"
            SELECT id
            FROM artworks
            WHERE album_id = ?1
            ORDER BY id
            LIMIT 1
            "#,
            params![album_id],
            |row| row.get::<_, i64>(0),
        )
        .optional()?;

    let width = artwork.width.map(i64::from);
    let height = artwork.height.map(i64::from);

    if let Some(id) = existing_id {
        connection.execute(
            r#"
            UPDATE artworks
            SET
                mime_type = ?1,
                path = ?2,
                data = ?3,
                width = ?4,
                height = ?5
            WHERE id = ?6
            "#,
            params![
                artwork.mime_type,
                artwork.path,
                artwork.data,
                width,
                height,
                id,
            ],
        )?;

        return Ok(id);
    }

    connection.execute(
        r#"
        INSERT INTO artworks (
            album_id,
            mime_type,
            path,
            data,
            width,
            height
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
        params![
            album_id,
            artwork.mime_type,
            artwork.path,
            artwork.data,
            width,
            height,
        ],
    )?;

    Ok(connection.last_insert_rowid())
}

pub fn open(path: &Path) -> Result<Connection, DbError> {
    let connection = Connection::open(path)?;
    initialize(&connection)?;
    Ok(connection)
}

pub fn open_in_memory() -> Result<Connection, DbError> {
    let connection = Connection::open_in_memory()?;
    initialize(&connection)?;
    Ok(connection)
}

pub fn initialize(connection: &Connection) -> Result<(), DbError> {
    connection.execute_batch(SCHEMA_SQL)?;

    let version: i64 =
        connection.query_row("SELECT version FROM schema_info WHERE id = 1", [], |row| {
            row.get(0)
        })?;

    if version != SCHEMA_VERSION {
        return Err(DbError::UnsupportedSchemaVersion(version));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initializes_schema() {
        let connection = open_in_memory().expect("database should initialize");

        let version: i64 = connection
            .query_row("SELECT version FROM schema_info WHERE id = 1", [], |row| {
                row.get(0)
            })
            .expect("schema version should exist");

        assert_eq!(version, SCHEMA_VERSION);
    }

    #[test]
    fn foreign_keys_are_enabled() {
        let connection = open_in_memory().expect("database should initialize");

        let foreign_keys: i64 = connection
            .query_row("PRAGMA foreign_keys", [], |row| row.get(0))
            .expect("foreign_keys pragma should be readable");

        assert_eq!(foreign_keys, 1);
    }

    #[test]
    fn expected_tables_exist() {
        let connection = open_in_memory().expect("database should initialize");

        let expected = [
            "schema_info",
            "artists",
            "albums",
            "assets",
            "tracks",
            "artworks",
            "playlists",
            "playlist_tracks",
            "history",
            "favorites",
        ];

        for table in expected {
            let exists: i64 = connection
                .query_row(
                    "SELECT EXISTS(
                        SELECT 1
                        FROM sqlite_master
                        WHERE type = 'table' AND name = ?1
                    )",
                    [table],
                    |row| row.get(0),
                )
                .expect("table existence query should work");

            assert_eq!(exists, 1, "missing table: {table}");
        }
    }

    #[test]
    fn asset_path_is_unique() {
        let connection = open_in_memory().expect("database should initialize");

        connection
            .execute(
                r#"
                INSERT INTO assets (
                    path,
                    sample_rate,
                    channels,
                    bits_per_sample,
                    total_frames
                )
                VALUES (?1, ?2, ?3, ?4, ?5)
                "#,
                ("/music/test.flac", 96_000i64, 2i64, 24i64, 15_376_640i64),
            )
            .expect("first asset insert should work");

        let duplicate = connection.execute(
            r#"
            INSERT INTO assets (
                path,
                sample_rate,
                channels,
                bits_per_sample,
                total_frames
            )
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            ("/music/test.flac", 96_000i64, 2i64, 24i64, 15_376_640i64),
        );

        assert!(duplicate.is_err());
    }

    #[test]
    fn track_requires_existing_asset() {
        let connection = open_in_memory().expect("database should initialize");

        let result = connection.execute(
            r#"
            INSERT INTO tracks (
                asset_id,
                title,
                track_number,
                start_frame,
                frame_count
            )
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            (999i64, "Broken Track", 1i64, 0i64, 100i64),
        );

        assert!(result.is_err());
    }

    #[test]
    fn deleting_asset_deletes_tracks() {
        let connection = open_in_memory().expect("database should initialize");

        connection
            .execute(
                r#"
                INSERT INTO assets (
                    id,
                    path,
                    sample_rate,
                    channels,
                    bits_per_sample,
                    total_frames
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                "#,
                (
                    1i64,
                    "/music/test.flac",
                    44_100i64,
                    2i64,
                    16i64,
                    2_551_618i64,
                ),
            )
            .expect("asset insert should work");

        connection
            .execute(
                r#"
                INSERT INTO tracks (
                    id,
                    asset_id,
                    title,
                    track_number,
                    start_frame,
                    frame_count
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                "#,
                (1i64, 1i64, "Test Track", 1i64, 0i64, 2_551_618i64),
            )
            .expect("track insert should work");

        connection
            .execute("DELETE FROM assets WHERE id = 1", [])
            .expect("asset delete should work");

        let count: i64 = connection
            .query_row(
                "SELECT COUNT(*) FROM tracks WHERE asset_id = 1",
                [],
                |row| row.get(0),
            )
            .expect("track count query should work");

        assert_eq!(count, 0);
    }

    #[test]
    fn removes_missing_assets_only_inside_scanned_root() {
        let mut connection = open_in_memory().expect("database should initialize");

        for (path, id) in [
            ("/music/a/keep.flac", 1i64),
            ("/music/a/delete.flac", 2i64),
            ("/music/b/keep.flac", 3i64),
        ] {
            connection
                .execute(
                    r#"
                    INSERT INTO assets (
                        id,
                        path,
                        sample_rate,
                        channels,
                        bits_per_sample,
                        total_frames,
                        codec
                    )
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                    "#,
                    (
                        id,
                        path,
                        44_100i64,
                        2i64,
                        16i64,
                        100i64,
                        Option::<String>::None,
                    ),
                )
                .expect("asset insert should work");
        }

        let removed = {
            let mut repository = LibraryRepository::new(&mut connection);
            repository
                .remove_assets_missing_from_scan(
                    Path::new("/music/a"),
                    &["/music/a/keep.flac".to_string()],
                )
                .expect("reconciliation should work")
        };

        assert_eq!(removed, 1);

        let remaining: Vec<String> = {
            let mut statement = connection
                .prepare("SELECT path FROM assets ORDER BY id")
                .expect("query should prepare");
            statement
                .query_map([], |row| row.get(0))
                .expect("query should run")
                .collect::<Result<Vec<String>, _>>()
                .expect("rows should collect")
        };

        assert_eq!(
            remaining,
            vec![
                "/music/a/keep.flac".to_string(),
                "/music/b/keep.flac".to_string(),
            ]
        );
    }

    #[test]
    fn removes_missing_asset_tracks_via_cascade() {
        let mut connection = open_in_memory().expect("database should initialize");

        connection
            .execute(
                r#"
                INSERT INTO assets (
                    id,
                    path,
                    sample_rate,
                    channels,
                    bits_per_sample,
                    total_frames
                )
                VALUES (1, '/music/delete.flac', 44_100, 2, 16, 100)
                "#,
                [],
            )
            .expect("asset insert should work");

        connection
            .execute(
                r#"
                INSERT INTO tracks (
                    id,
                    asset_id,
                    title,
                    track_number,
                    start_frame,
                    frame_count
                )
                VALUES (1, 1, 'Delete Me', 1, 0, 100)
                "#,
                [],
            )
            .expect("track insert should work");

        let removed = {
            let mut repository = LibraryRepository::new(&mut connection);
            repository
                .remove_assets_missing_from_scan(Path::new("/music"), &[])
                .expect("reconciliation should work")
        };

        assert_eq!(removed, 1);

        let track_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM tracks", [], |row| row.get(0))
            .expect("track count should work");

        assert_eq!(track_count, 0);
    }

    #[test]
    fn upserts_asset_and_tracks() {
        let mut connection = open_in_memory().expect("database should initialize");

        let asset = AssetRecord {
            path: "/music/highschool.flac".to_string(),
            sample_rate: 96_000,
            channels: 2,
            bits_per_sample: 24,
            total_frames: Some(15_376_640),
            codec: Some("FLAC".to_string()),
        };

        let track = TrackRecord {
            title: Some("Highschool Lover".to_string()),
            artist: Some("Air".to_string()),
            album: Some("The Virgin Suicides Redux".to_string()),
            album_artist: Some("Air".to_string()),
            date: Some("2025-09-27".to_string()),
            genre: None,
            composer: Some("Nicolas Godin, Jean-Benoît Dunckel".to_string()),
            track_number: 8,
            disc_number: Some(1),
            start_frame: 0,
            frame_count: Some(15_376_640),
            artwork: None,
        };

        let result = {
            let mut repository = LibraryRepository::new(&mut connection);

            repository
                .upsert_asset_with_ids(&asset, &[track.clone()])
                .expect("asset should be inserted")
        };

        assert_eq!(result.asset_id, 1);
        assert_eq!(result.track_ids, vec![1]);

        let repository = LibraryRepository::new(&mut connection);

        assert_eq!(repository.asset_count().expect("asset count"), 1);
        assert_eq!(repository.track_count().expect("track count"), 1);
        assert_eq!(repository.artist_count().expect("artist count"), 1);
        assert_eq!(repository.album_count().expect("album count"), 1);

        assert_eq!(
            repository.track_title(1, 8).expect("track title query"),
            Some("Highschool Lover".to_string())
        );
    }

    #[test]
    fn persists_and_reads_album_artwork() {
        let mut connection = open_in_memory().expect("database should initialize");

        let asset = AssetRecord {
            path: "/music/artwork.flac".to_string(),
            sample_rate: 44_100,
            channels: 2,
            bits_per_sample: 16,
            total_frames: Some(100),
            codec: Some("FLAC".to_string()),
        };

        let artwork = ArtworkRecord {
            mime_type: Some("image/jpeg".to_string()),
            path: None,
            data: vec![1, 2, 3, 4, 5],
            width: Some(600),
            height: Some(600),
        };

        let track = TrackRecord {
            title: Some("Artwork Track".to_string()),
            artist: Some("Test Artist".to_string()),
            album: Some("Artwork Album".to_string()),
            album_artist: Some("Test Artist".to_string()),
            date: None,
            genre: None,
            composer: None,
            track_number: 1,
            disc_number: Some(1),
            start_frame: 0,
            frame_count: Some(100),
            artwork: Some(artwork.clone()),
        };

        {
            let mut repository = LibraryRepository::new(&mut connection);

            repository
                .upsert_asset_with_ids(&asset, &[track])
                .expect("asset should be persisted");
        }

        let repository = LibraryRepository::new(&mut connection);

        let stored = repository
            .track_artwork(1)
            .expect("artwork lookup should work")
            .expect("artwork should exist");

        assert_eq!(stored.mime_type, artwork.mime_type);
        assert_eq!(stored.path, artwork.path);
        assert_eq!(stored.data, artwork.data);
        assert_eq!(stored.width, artwork.width);
        assert_eq!(stored.height, artwork.height);
    }

    #[test]
    fn artwork_upsert_is_idempotent() {
        let mut connection = open_in_memory().expect("database should initialize");

        let asset = AssetRecord {
            path: "/music/artwork.flac".to_string(),
            sample_rate: 44_100,
            channels: 2,
            bits_per_sample: 16,
            total_frames: Some(100),
            codec: Some("FLAC".to_string()),
        };

        let artwork = ArtworkRecord {
            mime_type: Some("image/jpeg".to_string()),
            path: None,
            data: vec![10, 20, 30],
            width: Some(300),
            height: Some(300),
        };

        let track = TrackRecord {
            title: Some("Artwork Track".to_string()),
            artist: Some("Test Artist".to_string()),
            album: Some("Artwork Album".to_string()),
            album_artist: Some("Test Artist".to_string()),
            date: None,
            genre: None,
            composer: None,
            track_number: 1,
            disc_number: Some(1),
            start_frame: 0,
            frame_count: Some(100),
            artwork: Some(artwork),
        };

        {
            let mut repository = LibraryRepository::new(&mut connection);

            repository
                .upsert_asset_with_ids(&asset, &[track.clone()])
                .expect("first scan should work");

            repository
                .upsert_asset_with_ids(&asset, &[track])
                .expect("second scan should work");
        }

        let artwork_count: i64 = connection
            .query_row("SELECT COUNT(*) FROM artworks", [], |row| row.get(0))
            .expect("artwork count should work");

        assert_eq!(artwork_count, 1);
    }

    #[test]
    fn scan_without_artwork_preserves_existing_artwork() {
        let mut connection = open_in_memory().expect("database should initialize");

        let asset = AssetRecord {
            path: "/music/artwork.flac".to_string(),
            sample_rate: 44_100,
            channels: 2,
            bits_per_sample: 16,
            total_frames: Some(100),
            codec: Some("FLAC".to_string()),
        };

        let artwork = ArtworkRecord {
            mime_type: Some("image/jpeg".to_string()),
            path: None,
            data: vec![1, 2, 3],
            width: Some(500),
            height: Some(500),
        };

        let track_with_artwork = TrackRecord {
            title: Some("Artwork Track".to_string()),
            artist: Some("Test Artist".to_string()),
            album: Some("Artwork Album".to_string()),
            album_artist: Some("Test Artist".to_string()),
            date: None,
            genre: None,
            composer: None,
            track_number: 1,
            disc_number: Some(1),
            start_frame: 0,
            frame_count: Some(100),
            artwork: Some(artwork.clone()),
        };

        let track_without_artwork = TrackRecord {
            artwork: None,
            ..track_with_artwork.clone()
        };

        {
            let mut repository = LibraryRepository::new(&mut connection);

            repository
                .upsert_asset_with_ids(&asset, &[track_with_artwork])
                .expect("first scan should work");

            repository
                .upsert_asset_with_ids(&asset, &[track_without_artwork])
                .expect("second scan should work");
        }

        let repository = LibraryRepository::new(&mut connection);

        let stored = repository
            .track_artwork(1)
            .expect("artwork lookup should work")
            .expect("existing artwork should remain");

        assert_eq!(stored.data, artwork.data);
        assert_eq!(stored.mime_type, artwork.mime_type);
    }
}
