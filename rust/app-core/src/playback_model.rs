use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaybackTrack {
    pub track_id: i64,
    pub asset_id: i64,
    pub path: PathBuf,
    pub sample_rate: u32,
    pub channels: u16,
    pub bits_per_sample: u16,
    pub start_frame: u64,
    pub frame_count: Option<u64>,
}

impl PlaybackTrack {
    pub fn end_frame(&self) -> Option<u64> {
        self.frame_count
            .and_then(|count| self.start_frame.checked_add(count))
    }

    pub fn duration_seconds(&self) -> Option<f64> {
        self.frame_count
            .filter(|_| self.sample_rate > 0)
            .map(|frames| frames as f64 / self.sample_rate as f64)
    }

    pub fn contains_frame(&self, source_frame: u64) -> bool {
        if source_frame < self.start_frame {
            return false;
        }

        match self.end_frame() {
            Some(end) => source_frame < end,
            None => true,
        }
    }

    pub fn local_frame(&self, source_frame: u64) -> Option<u64> {
        self.contains_frame(source_frame)
            .then_some(source_frame - self.start_frame)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> PlaybackTrack {
        PlaybackTrack {
            track_id: 10,
            asset_id: 20,
            path: PathBuf::from("/music/album.flac"),
            sample_rate: 44_100,
            channels: 2,
            bits_per_sample: 16,
            start_frame: 10_000,
            frame_count: Some(5_000),
        }
    }

    #[test]
    fn computes_end_frame() {
        assert_eq!(sample().end_frame(), Some(15_000));
    }

    #[test]
    fn computes_duration() {
        let duration = sample().duration_seconds().unwrap();

        assert!((duration - (5_000.0 / 44_100.0)).abs() < 1e-12);
    }

    #[test]
    fn checks_source_frame_membership() {
        let track = sample();

        assert!(!track.contains_frame(9_999));
        assert!(track.contains_frame(10_000));
        assert!(track.contains_frame(14_999));
        assert!(!track.contains_frame(15_000));
    }

    #[test]
    fn converts_source_frame_to_local_frame() {
        let track = sample();

        assert_eq!(track.local_frame(10_000), Some(0));
        assert_eq!(track.local_frame(10_123), Some(123));
        assert_eq!(track.local_frame(15_000), None);
    }

    #[test]
    fn open_ended_track_contains_frames_after_start() {
        let track = PlaybackTrack {
            frame_count: None,
            ..sample()
        };

        assert!(track.contains_frame(10_000));
        assert!(track.contains_frame(999_999));
        assert_eq!(track.local_frame(10_123), Some(123));
    }
}
