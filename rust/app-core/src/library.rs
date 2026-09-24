use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AudioAssetId(pub i64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TrackId(pub i64);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioAsset {
    pub id: AudioAssetId,
    pub path: PathBuf,
    pub sample_rate: u32,
    pub channels: u32,
    pub bits_per_sample: u16,
    pub total_frames: Option<u64>,
}

impl AudioAsset {
    pub fn duration_seconds(&self) -> Option<f64> {
        self.total_frames
            .filter(|_| self.sample_rate > 0)
            .map(|frames| frames as f64 / self.sample_rate as f64)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Track {
    pub id: TrackId,
    pub asset_id: AudioAssetId,

    /// Zero-based start frame inside the physical asset.
    pub start_frame: u64,

    /// Number of frames belonging to this logical track.
    ///
    /// `None` means the track continues until the end of the asset.
    pub frame_count: Option<u64>,

    pub disc_number: Option<u32>,
    pub track_number: u32,

    pub title: Option<String>,
    pub performer: Option<String>,
    pub album: Option<String>,
}

impl Track {
    pub fn end_frame(&self) -> Option<u64> {
        self.frame_count
            .map(|count| self.start_frame.saturating_add(count))
    }

    pub fn contains_frame(&self, frame: u64) -> bool {
        if frame < self.start_frame {
            return false;
        }

        match self.frame_count {
            Some(count) => frame < self.start_frame.saturating_add(count),

            None => true,
        }
    }

    pub fn local_frame(&self, asset_frame: u64) -> Option<u64> {
        if !self.contains_frame(asset_frame) {
            return None;
        }

        Some(asset_frame.saturating_sub(self.start_frame))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrackIndex {
    pub tracks: Vec<Track>,
}

impl TrackIndex {
    pub fn new(tracks: Vec<Track>) -> Self {
        Self { tracks }
    }

    pub fn find_frame(&self, frame: u64) -> Option<&Track> {
        self.tracks.iter().find(|track| track.contains_frame(frame))
    }

    pub fn validate(&self) -> Result<(), TrackIndexError> {
        for pair in self.tracks.windows(2) {
            let left = &pair[0];
            let right = &pair[1];

            if right.start_frame < left.start_frame {
                return Err(TrackIndexError::Unsorted {
                    previous: left.start_frame,
                    current: right.start_frame,
                });
            }

            if let Some(left_end) = left.end_frame() {
                if right.start_frame < left_end {
                    return Err(TrackIndexError::Overlap {
                        left_start: left.start_frame,
                        left_end,
                        right_start: right.start_frame,
                    });
                }
            }
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrackIndexError {
    Unsorted {
        previous: u64,
        current: u64,
    },

    Overlap {
        left_start: u64,
        left_end: u64,
        right_start: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(id: i64, start: u64, count: Option<u64>) -> Track {
        Track {
            id: TrackId(id),
            asset_id: AudioAssetId(1),
            start_frame: start,
            frame_count: count,
            disc_number: None,
            track_number: id as u32,
            title: None,
            performer: None,
            album: None,
        }
    }

    #[test]
    fn track_local_frame() {
        let value = track(1, 100, Some(50));

        assert_eq!(value.local_frame(100), Some(0));

        assert_eq!(value.local_frame(125), Some(25));

        assert_eq!(value.local_frame(150), None);
    }

    #[test]
    fn index_finds_containing_track() {
        let index = TrackIndex::new(vec![track(1, 0, Some(100)), track(2, 100, Some(100))]);

        assert_eq!(index.find_frame(99).map(|track| track.id), Some(TrackId(1)));

        assert_eq!(
            index.find_frame(100).map(|track| track.id),
            Some(TrackId(2))
        );
    }

    #[test]
    fn overlapping_tracks_are_rejected() {
        let index = TrackIndex::new(vec![track(1, 0, Some(100)), track(2, 50, Some(100))]);

        assert_eq!(
            index.validate(),
            Err(TrackIndexError::Overlap {
                left_start: 0,
                left_end: 100,
                right_start: 50,
            })
        );
    }
}
