use std::path::Path;

use thiserror::Error;

use crate::{
    library_service::LibraryService, playback_model::PlaybackTrack, PlaybackController,
    PlaybackError, PlaybackState,
};

#[derive(Debug, Error)]
pub enum PlaybackServiceError {
    #[error("library error: {0}")]
    Library(#[from] crate::library_service::LibraryServiceError),

    #[error("playback error: {0}")]
    Playback(#[from] PlaybackError),

    #[error("track not found: {track_id}")]
    TrackNotFound { track_id: i64 },
}

pub struct PlaybackService {
    library: LibraryService,
    controller: PlaybackController,
    current_track: Option<PlaybackTrack>,
}

impl PlaybackService {
    pub fn open(path: &Path) -> Result<Self, PlaybackServiceError> {
        Ok(Self {
            library: LibraryService::open(path)?,
            controller: PlaybackController::new(),
            current_track: None,
        })
    }

    pub fn open_in_memory() -> Result<Self, PlaybackServiceError> {
        Ok(Self {
            library: LibraryService::open_in_memory()?,
            controller: PlaybackController::new(),
            current_track: None,
        })
    }

    pub fn library(&self) -> &LibraryService {
        &self.library
    }

    pub fn scan_directory(
        &mut self,
        root: &Path,
    ) -> Result<crate::library_service::LibraryScanReport, PlaybackServiceError> {
        Ok(self.library.scan_directory(root)?)
    }

    pub fn current_track(&self) -> Option<&PlaybackTrack> {
        self.current_track.as_ref()
    }

    pub fn state(&self) -> PlaybackState {
        self.controller.state()
    }

    pub fn output_mode(&self) -> crate::PlaybackOutputMode {
        self.controller.output_mode()
    }

    pub fn set_output_mode(&mut self, mode: crate::PlaybackOutputMode) {
        self.controller.set_output_mode(mode);
    }

    pub fn volume(&self) -> f32 {
        self.controller.volume()
    }

    pub fn set_volume(&mut self, volume: f32) {
        self.controller.set_volume(volume);
    }

    pub fn equalizer_gains(&self) -> [f32; 10] {
        self.controller.equalizer_gains()
    }

    pub fn set_equalizer_gains(&mut self, gains_db: [f32; 10]) {
        self.controller.set_equalizer_gains(gains_db);
    }

    pub fn load_track(&mut self, track_id: i64) -> Result<&PlaybackTrack, PlaybackServiceError> {
        let track = self
            .library
            .playback_track(track_id)?
            .ok_or(PlaybackServiceError::TrackNotFound { track_id })?;

        self.controller.load(&track.path)?;

        if track.start_frame > 0 {
            self.controller.seek_to_frame(track.start_frame)?;
        }

        self.current_track = Some(track);

        Ok(self
            .current_track
            .as_ref()
            .expect("current track was just assigned"))
    }

    pub fn play(&mut self) -> Result<(), PlaybackServiceError> {
        self.controller.play()?;
        Ok(())
    }

    pub fn pause(&mut self) -> Result<(), PlaybackServiceError> {
        self.controller.pause()?;
        Ok(())
    }

    pub fn stop(&mut self) -> Result<(), PlaybackServiceError> {
        self.controller.stop()?;
        Ok(())
    }

    pub fn seek_to_frame(&mut self, local_frame: u64) -> Result<(), PlaybackServiceError> {
        let track = self
            .current_track
            .as_ref()
            .ok_or(PlaybackError::NotLoaded)?;

        let track_frame_count = match track.frame_count {
            Some(frame_count) => frame_count,
            None => self
                .controller
                .total_frames()
                .unwrap_or(track.start_frame)
                .saturating_sub(track.start_frame),
        };

        if local_frame > track_frame_count {
            return Err(PlaybackError::InvalidSeekTarget(local_frame).into());
        }

        let source_frame = track
            .start_frame
            .checked_add(local_frame)
            .ok_or(PlaybackError::InvalidSeekTarget(local_frame))?;

        self.controller.seek_to_frame(source_frame)?;

        Ok(())
    }

    pub fn seek_to_source_frame(&mut self, source_frame: u64) -> Result<(), PlaybackServiceError> {
        self.controller.seek_to_frame(source_frame)?;
        Ok(())
    }

    pub fn current_frame(&self) -> Option<u64> {
        let source_frame = self.controller.current_frame()?;
        let track = self.current_track.as_ref()?;

        Some(source_frame.saturating_sub(track.start_frame))
    }

    pub fn current_source_frame(&self) -> Option<u64> {
        self.controller.current_frame()
    }

    pub fn current_seconds(&self) -> Option<f64> {
        let track = self.current_track.as_ref()?;
        let frame = self.current_frame()?;

        if track.sample_rate == 0 {
            return None;
        }

        Some(frame as f64 / track.sample_rate as f64)
    }

    pub fn duration_seconds(&self) -> Option<f64> {
        self.current_track
            .as_ref()
            .and_then(PlaybackTrack::duration_seconds)
    }

    pub fn total_frames(&self) -> Option<u64> {
        self.current_track
            .as_ref()
            .and_then(|track| track.frame_count)
    }

    pub fn is_at_end(&self) -> bool {
        let Some(track) = self.current_track.as_ref() else {
            return false;
        };

        let Some(frame_count) = track.frame_count else {
            return false;
        };

        let Some(source_frame) = self.controller.current_frame() else {
            return false;
        };

        let Some(end_frame) = track.start_frame.checked_add(frame_count) else {
            return false;
        };

        source_frame >= end_frame
    }

    #[cfg(target_os = "macos")]
    pub fn telemetry(&self) -> Option<crate::PlaybackTelemetry> {
        self.controller.telemetry()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_not_at_end_without_current_track() {
        let service = PlaybackService::open_in_memory().expect("service should open");

        assert!(!service.is_at_end());
    }

    #[test]
    fn starts_idle_without_current_track() {
        let service = PlaybackService::open_in_memory().expect("service should open");

        assert_eq!(service.state(), PlaybackState::Idle);
        assert!(service.current_track().is_none());
        assert!(service.current_frame().is_none());
        assert!(service.current_source_frame().is_none());
        assert!(service.duration_seconds().is_none());
        assert!(service.total_frames().is_none());
    }

    #[test]
    fn unknown_track_is_rejected() {
        let mut service = PlaybackService::open_in_memory().expect("service should open");

        let result = service.load_track(999);

        assert!(matches!(
            result,
            Err(PlaybackServiceError::TrackNotFound { track_id: 999 })
        ));

        assert_eq!(service.state(), PlaybackState::Idle);
        assert!(service.current_track().is_none());
    }

    #[test]
    fn play_without_loaded_track_returns_not_loaded() {
        let mut service = PlaybackService::open_in_memory().expect("service should open");

        let result = service.play();

        assert!(matches!(
            result,
            Err(PlaybackServiceError::Playback(PlaybackError::NotLoaded))
        ));
    }

    #[test]
    fn pause_without_loaded_track_returns_not_loaded() {
        let mut service = PlaybackService::open_in_memory().expect("service should open");

        let result = service.pause();

        assert!(matches!(
            result,
            Err(PlaybackServiceError::Playback(PlaybackError::NotLoaded))
        ));
    }

    #[test]
    fn stop_without_loaded_track_is_safe() {
        let mut service = PlaybackService::open_in_memory().expect("service should open");

        let result = service.stop();

        assert!(result.is_ok());
        assert_eq!(service.state(), PlaybackState::Stopped);
        assert!(service.current_track().is_none());
    }

    #[test]
    fn seek_without_loaded_track_returns_not_loaded() {
        let mut service = PlaybackService::open_in_memory().expect("service should open");

        let result = service.seek_to_frame(0);

        assert!(matches!(
            result,
            Err(PlaybackServiceError::Playback(PlaybackError::NotLoaded))
        ));
    }
}
