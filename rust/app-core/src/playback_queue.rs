use thiserror::Error;

use crate::{
    playback_model::PlaybackTrack,
    playback_service::{PlaybackService, PlaybackServiceError},
    PlaybackState,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RepeatMode {
    Off,
    Track,
    Queue,
}

impl Default for RepeatMode {
    fn default() -> Self {
        Self::Off
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct QueuePosition {
    pub index: usize,
    pub track_id: i64,
}

#[derive(Debug, Error)]
pub enum PlaybackQueueError {
    #[error("queue is empty")]
    Empty,

    #[error("queue index {index} is out of range for queue length {len}")]
    IndexOutOfRange { index: usize, len: usize },

    #[error("queue reorder must contain the same tracks as the selected section")]
    InvalidReorder,

    #[error("track {track_id} is not present in the library")]
    TrackNotFound { track_id: i64 },

    #[error(transparent)]
    Library(#[from] crate::library_service::LibraryServiceError),

    #[error(transparent)]
    Playback(#[from] PlaybackServiceError),
}

pub struct PlaybackQueue {
    track_ids: Vec<i64>,
    current_index: Option<usize>,
    queued_count: usize,
    repeat_mode: RepeatMode,
}

impl Default for PlaybackQueue {
    fn default() -> Self {
        Self::new()
    }
}

impl PlaybackQueue {
    pub fn new() -> Self {
        Self {
            track_ids: Vec::new(),
            current_index: None,
            queued_count: 0,
            repeat_mode: RepeatMode::Off,
        }
    }

    pub fn set_queue(
        &mut self,
        service: &PlaybackService,
        track_ids: Vec<i64>,
    ) -> Result<(), PlaybackQueueError> {
        for &track_id in &track_ids {
            if service.library().playback_track(track_id)?.is_none() {
                return Err(PlaybackQueueError::TrackNotFound { track_id });
            }
        }

        self.track_ids = track_ids;

        self.current_index = if self.track_ids.is_empty() {
            None
        } else {
            Some(0)
        };
        self.queued_count = 0;

        Ok(())
    }

    pub fn add_to_queue(
        &mut self,
        service: &PlaybackService,
        track_id: i64,
    ) -> Result<usize, PlaybackQueueError> {
        if service.library().playback_track(track_id)?.is_none() {
            return Err(PlaybackQueueError::TrackNotFound { track_id });
        }

        if let Some(current_index) = self.current_index {
            let insert_at = (current_index + 1 + self.queued_count).min(self.track_ids.len());
            self.track_ids.insert(insert_at, track_id);
            self.queued_count += 1;
        } else {
            self.track_ids.push(track_id);
            self.current_index = Some(0);
        }

        Ok(self.track_ids.len())
    }

    pub fn clear(&mut self) {
        self.track_ids.clear();
        self.current_index = None;
        self.queued_count = 0;
    }

    pub fn len(&self) -> usize {
        self.track_ids.len()
    }

    pub fn is_empty(&self) -> bool {
        self.track_ids.is_empty()
    }

    pub fn track_ids(&self) -> &[i64] {
        &self.track_ids
    }

    pub fn track_id_at(&self, index: usize) -> Option<i64> {
        self.track_ids.get(index).copied()
    }

    pub fn queued_count(&self) -> usize {
        self.queued_count
    }

    pub fn reorder_segment(
        &mut self,
        start: usize,
        reordered_ids: Vec<i64>,
    ) -> Result<(), PlaybackQueueError> {
        let current_index = self.current_index.ok_or(PlaybackQueueError::Empty)?;
        let end = start.saturating_add(reordered_ids.len());
        if start <= current_index || end > self.track_ids.len() {
            return Err(PlaybackQueueError::IndexOutOfRange {
                index: end,
                len: self.track_ids.len(),
            });
        }

        let existing = &self.track_ids[start..end];
        let mut expected = existing.to_vec();
        let mut received = reordered_ids.clone();
        expected.sort_unstable();
        received.sort_unstable();
        if expected != received {
            return Err(PlaybackQueueError::InvalidReorder);
        }

        self.track_ids[start..end].copy_from_slice(&reordered_ids);
        if start == current_index + 1 && end == self.track_ids.len() {
            // The user has manually ordered the full upcoming queue, so there
            // is no longer a separate "added next" segment.
            self.queued_count = 0;
        }
        Ok(())
    }

    pub fn current_index(&self) -> Option<usize> {
        self.current_index
    }

    pub fn repeat_mode(&self) -> RepeatMode {
        self.repeat_mode
    }

    pub fn set_repeat_mode(&mut self, repeat_mode: RepeatMode) {
        self.repeat_mode = repeat_mode;
    }

    pub fn current_position(&self) -> Option<QueuePosition> {
        self.current_index.map(|index| QueuePosition {
            index,
            track_id: self.track_ids[index],
        })
    }

    pub fn current_track(
        &self,
        service: &PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        let Some(index) = self.current_index else {
            return Ok(None);
        };

        Ok(service.library().playback_track(self.track_ids[index])?)
    }

    pub fn select(
        &mut self,
        service: &PlaybackService,
        index: usize,
    ) -> Result<PlaybackTrack, PlaybackQueueError> {
        let track_id = *self
            .track_ids
            .get(index)
            .ok_or(PlaybackQueueError::IndexOutOfRange {
                index,
                len: self.track_ids.len(),
            })?;

        let track = service
            .library()
            .playback_track(track_id)?
            .ok_or(PlaybackQueueError::TrackNotFound { track_id })?;

        if let Some(previous_index) = self.current_index {
            let up_next_boundary = previous_index + 1 + self.queued_count;
            if index != previous_index {
                self.queued_count = if index > previous_index && index < up_next_boundary {
                    up_next_boundary - index - 1
                } else {
                    0
                };
            }
        }
        self.current_index = Some(index);

        Ok(track)
    }

    pub fn select_and_load(
        &mut self,
        service: &mut PlaybackService,
        index: usize,
    ) -> Result<PlaybackTrack, PlaybackQueueError> {
        let track = self.select(service, index)?;

        service.load_track(track.track_id)?;

        Ok(track)
    }

    pub fn play_current(&self, service: &mut PlaybackService) -> Result<(), PlaybackQueueError> {
        if self.current_index.is_none() {
            return Err(PlaybackQueueError::Empty);
        }

        service.play()?;

        Ok(())
    }

    pub fn select_and_play(
        &mut self,
        service: &mut PlaybackService,
        index: usize,
    ) -> Result<PlaybackTrack, PlaybackQueueError> {
        let track = self.select_and_load(service, index)?;

        service.play()?;

        Ok(track)
    }

    pub fn next(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        let Some(current_index) = self.current_index else {
            return Err(PlaybackQueueError::Empty);
        };

        let next_index = current_index + 1;

        if next_index >= self.track_ids.len() {
            return Ok(None);
        }

        self.select_and_load(service, next_index).map(Some)
    }

    pub fn next_and_play(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        let Some(track) = self.next(service)? else {
            return Ok(None);
        };

        service.play()?;

        Ok(Some(track))
    }

    pub fn previous(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        let Some(current_index) = self.current_index else {
            return Err(PlaybackQueueError::Empty);
        };

        if current_index == 0 {
            return Ok(None);
        }

        self.select_and_load(service, current_index - 1).map(Some)
    }

    pub fn previous_and_play(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        let Some(track) = self.previous(service)? else {
            return Ok(None);
        };

        service.play()?;

        Ok(Some(track))
    }

    pub fn repeat_current_and_play(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        let Some(index) = self.current_index else {
            return Err(PlaybackQueueError::Empty);
        };

        self.select_and_play(service, index).map(Some)
    }

    pub fn advance_and_play(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        match self.repeat_mode {
            RepeatMode::Track => self.repeat_current_and_play(service),

            RepeatMode::Off => self.next_and_play(service),

            RepeatMode::Queue => {
                let Some(current_index) = self.current_index else {
                    return Err(PlaybackQueueError::Empty);
                };

                let next_index = current_index + 1;

                if next_index < self.track_ids.len() {
                    return self.select_and_play(service, next_index).map(Some);
                }

                if self.track_ids.is_empty() {
                    return Err(PlaybackQueueError::Empty);
                }

                self.select_and_play(service, 0).map(Some)
            }
        }
    }

    pub fn advance_if_at_end(
        &mut self,
        service: &mut PlaybackService,
    ) -> Result<Option<PlaybackTrack>, PlaybackQueueError> {
        if self.current_index.is_none() {
            return Err(PlaybackQueueError::Empty);
        }

        if service.state() != PlaybackState::Playing {
            return Ok(None);
        }

        if !service.is_at_end() {
            return Ok(None);
        }

        match self.repeat_mode {
            RepeatMode::Track => self.repeat_current_and_play(service),

            RepeatMode::Queue => {
                let current_index = self.current_index.ok_or(PlaybackQueueError::Empty)?;

                let next_index = current_index + 1;

                if next_index < self.track_ids.len() {
                    return self.select_and_play(service, next_index).map(Some);
                }

                if self.track_ids.is_empty() {
                    return Err(PlaybackQueueError::Empty);
                }

                self.select_and_play(service, 0).map(Some)
            }

            RepeatMode::Off => {
                let current_index = self.current_index.ok_or(PlaybackQueueError::Empty)?;

                let next_index = current_index + 1;

                if next_index >= self.track_ids.len() {
                    service.stop()?;
                    return Ok(None);
                }

                self.select_and_play(service, next_index).map(Some)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_service() -> PlaybackService {
        PlaybackService::open_in_memory().expect("in-memory service should open")
    }

    #[test]
    fn starts_empty() {
        let queue = PlaybackQueue::new();

        assert!(queue.is_empty());
        assert_eq!(queue.len(), 0);
        assert_eq!(queue.current_index(), None);
        assert_eq!(queue.current_position(), None);
        assert_eq!(queue.repeat_mode(), RepeatMode::Off);
    }

    #[test]
    fn clear_resets_queue() {
        let mut queue = PlaybackQueue::new();

        queue.track_ids = vec![1, 2, 3];
        queue.current_index = Some(1);

        queue.clear();

        assert!(queue.is_empty());
        assert_eq!(queue.current_index(), None);
    }

    #[test]
    fn repeat_mode_can_be_changed() {
        let mut queue = PlaybackQueue::new();

        queue.set_repeat_mode(RepeatMode::Track);
        assert_eq!(queue.repeat_mode(), RepeatMode::Track);

        queue.set_repeat_mode(RepeatMode::Queue);
        assert_eq!(queue.repeat_mode(), RepeatMode::Queue);

        queue.set_repeat_mode(RepeatMode::Off);
        assert_eq!(queue.repeat_mode(), RepeatMode::Off);
    }

    #[test]
    fn empty_queue_next_returns_empty_error() {
        let mut service = empty_service();
        let mut queue = PlaybackQueue::new();

        let error = queue.next(&mut service).unwrap_err();

        assert!(matches!(error, PlaybackQueueError::Empty));
    }

    #[test]
    fn empty_queue_previous_returns_empty_error() {
        let mut service = empty_service();
        let mut queue = PlaybackQueue::new();

        let error = queue.previous(&mut service).unwrap_err();

        assert!(matches!(error, PlaybackQueueError::Empty));
    }

    #[test]
    fn empty_queue_advance_if_at_end_returns_empty_error() {
        let mut service = empty_service();
        let mut queue = PlaybackQueue::new();

        let error = queue.advance_if_at_end(&mut service).unwrap_err();

        assert!(matches!(error, PlaybackQueueError::Empty));
    }

    #[test]
    fn select_rejects_out_of_range_index() {
        let service = empty_service();
        let mut queue = PlaybackQueue::new();

        queue.track_ids = vec![1, 2];

        let error = queue.select(&service, 2).unwrap_err();

        assert!(matches!(
            error,
            PlaybackQueueError::IndexOutOfRange { index: 2, len: 2 }
        ));
    }

    #[test]
    fn next_at_end_does_not_wrap() {
        let mut service = empty_service();
        let mut queue = PlaybackQueue::new();

        queue.track_ids = vec![1, 2];
        queue.current_index = Some(1);

        let result = queue.next(&mut service).unwrap();

        assert_eq!(result, None);
        assert_eq!(queue.current_index(), Some(1));
    }

    #[test]
    fn previous_at_start_does_not_wrap() {
        let mut service = empty_service();
        let mut queue = PlaybackQueue::new();

        queue.track_ids = vec![1, 2];
        queue.current_index = Some(0);

        let result = queue.previous(&mut service).unwrap();

        assert_eq!(result, None);
        assert_eq!(queue.current_index(), Some(0));
    }

    #[test]
    fn set_empty_queue_clears_position() {
        let service = empty_service();
        let mut queue = PlaybackQueue::new();

        queue.track_ids = vec![1, 2];
        queue.current_index = Some(1);

        queue.set_queue(&service, Vec::new()).unwrap();

        assert!(queue.is_empty());
        assert_eq!(queue.current_index(), None);
    }
}
