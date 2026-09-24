use std::path::{Path, PathBuf};

use thiserror::Error;

use crate::{
    library_store::{LibraryStore, LibraryStoreError, StoredArtwork, StoredScan, TrackMetadata},
    playback_model::PlaybackTrack,
    scanner::{ScanResult, Scanner, ScannerError},
};

#[derive(Debug, Error)]
pub enum LibraryServiceError {
    #[error("scanner error: {0}")]
    Scanner(#[from] ScannerError),

    #[error("library store error: {0}")]
    Store(#[from] LibraryStoreError),
}

#[derive(Debug, Clone)]
pub struct LibraryScanReport {
    pub root: PathBuf,
    pub scan: ScanResult,
    pub stored: Vec<StoredScan>,
}

impl LibraryScanReport {
    pub fn scanned_assets(&self) -> usize {
        self.scan.assets.len()
    }

    pub fn ignored_files(&self) -> usize {
        self.scan.ignored_files.len()
    }

    pub fn scan_errors(&self) -> usize {
        self.scan.errors.len()
    }

    pub fn persisted_assets(&self) -> usize {
        self.stored.len()
    }

    pub fn has_scan_errors(&self) -> bool {
        !self.scan.errors.is_empty()
    }

    pub fn asset_count(&self) -> usize {
        self.scanned_assets()
    }

    pub fn ignored_count(&self) -> usize {
        self.ignored_files()
    }

    pub fn error_count(&self) -> usize {
        self.scan_errors()
    }

    pub fn persisted_count(&self) -> usize {
        self.persisted_assets()
    }
}

pub struct LibraryService {
    scanner: Scanner,
    store: LibraryStore,
}

impl LibraryService {
    pub fn open(path: &Path) -> Result<Self, LibraryServiceError> {
        Ok(Self {
            scanner: Scanner::new(),
            store: LibraryStore::open(path)?,
        })
    }

    pub fn open_in_memory() -> Result<Self, LibraryServiceError> {
        Ok(Self {
            scanner: Scanner::new(),
            store: LibraryStore::open_in_memory()?,
        })
    }

    pub fn scan_directory(
        &mut self,
        root: &Path,
    ) -> Result<LibraryScanReport, LibraryServiceError> {
        let scan = self.scanner.scan_directory(root)?;

        let mut stored = Vec::with_capacity(scan.assets.len());

        for asset in &scan.assets {
            stored.push(self.store.persist_scan(asset)?);
        }

        if scan.errors.is_empty() {
            let scanned_paths = scan
                .assets
                .iter()
                .map(|asset| asset.asset.path.to_string_lossy().into_owned())
                .collect::<Vec<_>>();

            self.store
                .remove_assets_missing_from_scan(root, &scanned_paths)?;
        }

        Ok(LibraryScanReport {
            root: root.to_path_buf(),
            scan,
            stored,
        })
    }

    pub fn playback_track(
        &self,
        track_id: i64,
    ) -> Result<Option<PlaybackTrack>, LibraryServiceError> {
        Ok(self.store.playback_track(track_id)?)
    }

    pub fn playback_tracks(&self) -> Result<Vec<PlaybackTrack>, LibraryServiceError> {
        Ok(self.store.playback_tracks()?)
    }

    pub fn track_artwork(
        &self,
        track_id: i64,
    ) -> Result<Option<StoredArtwork>, LibraryServiceError> {
        Ok(self.store.track_artwork(track_id)?)
    }

    pub fn track_metadata(
        &self,
        track_id: i64,
    ) -> Result<Option<TrackMetadata>, LibraryServiceError> {
        Ok(self.store.track_metadata(track_id)?)
    }

    pub fn asset_count(&self) -> Result<i64, LibraryServiceError> {
        Ok(self.store.asset_count()?)
    }

    pub fn track_count(&self) -> Result<i64, LibraryServiceError> {
        Ok(self.store.track_count()?)
    }

    pub fn artist_count(&self) -> Result<i64, LibraryServiceError> {
        Ok(self.store.artist_count()?)
    }

    pub fn album_count(&self) -> Result<i64, LibraryServiceError> {
        Ok(self.store.album_count()?)
    }

    pub fn track_title(&self, track_id: i64) -> Result<Option<String>, LibraryServiceError> {
        Ok(self.store.track_title(track_id)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_with_empty_database() -> Result<(), LibraryServiceError> {
        let mut service = LibraryService::open_in_memory()?;

        assert!(service.playback_tracks()?.is_empty());

        assert_eq!(service.asset_count()?, 0);

        assert_eq!(service.track_count()?, 0);

        assert_eq!(service.artist_count()?, 0);

        assert_eq!(service.album_count()?, 0);

        assert_eq!(service.track_title(999)?, None);

        assert_eq!(service.track_metadata(999)?, None);

        assert_eq!(service.track_artwork(999)?, None);

        assert_eq!(service.playback_track(999)?, None);

        Ok(())
    }

    #[test]
    fn unknown_playback_track_returns_none() -> Result<(), LibraryServiceError> {
        let service = LibraryService::open_in_memory()?;

        assert!(service.playback_track(999)?.is_none());

        Ok(())
    }

    #[test]
    fn unknown_track_metadata_returns_none() -> Result<(), LibraryServiceError> {
        let mut service = LibraryService::open_in_memory()?;

        assert!(service.track_metadata(999)?.is_none());

        Ok(())
    }

    #[test]
    fn unknown_track_artwork_returns_none() -> Result<(), LibraryServiceError> {
        let mut service = LibraryService::open_in_memory()?;

        assert!(service.track_artwork(999)?.is_none());

        Ok(())
    }
}
