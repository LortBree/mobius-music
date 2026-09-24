use offline_player_metadata::EmbeddedArtwork;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct EmbeddedMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub composer: Option<String>,
    pub genre: Option<String>,
    pub date: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub artwork: Option<EmbeddedArtwork>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct NormalizedAlbumMetadata {
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub date: Option<String>,
    pub genre: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct NormalizedTrackMetadata {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub composer: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedMetadata {
    pub source_path: PathBuf,
    pub album: NormalizedAlbumMetadata,
    pub track: NormalizedTrackMetadata,
}

impl NormalizedMetadata {
    pub fn from_embedded(source_path: PathBuf, embedded: EmbeddedMetadata) -> Self {
        Self {
            source_path,
            album: NormalizedAlbumMetadata {
                album: embedded.album,
                album_artist: embedded.album_artist,
                date: embedded.date,
                genre: embedded.genre,
            },
            track: NormalizedTrackMetadata {
                title: embedded.title,
                artist: embedded.artist,
                track_number: embedded.track_number,
                disc_number: embedded.disc_number,
                composer: embedded.composer,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CueMetadataOverride {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub track_number: Option<u32>,
}

impl NormalizedTrackMetadata {
    pub fn apply_cue_override(&mut self, cue: &CueMetadataOverride) {
        if cue.title.is_some() {
            self.title = cue.title.clone();
        }

        if cue.artist.is_some() {
            self.artist = cue.artist.clone();
        }

        if cue.track_number.is_some() {
            self.track_number = cue.track_number;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_metadata_becomes_normalized_metadata() {
        let embedded = EmbeddedMetadata {
            title: Some("Original Title".to_string()),
            artist: Some("Original Artist".to_string()),
            album: Some("Original Album".to_string()),
            album_artist: Some("Album Artist".to_string()),
            composer: None,
            genre: Some("Soundtrack".to_string()),
            date: Some("1995".to_string()),
            track_number: Some(1),
            disc_number: Some(1),
            artwork: None,
        };

        let normalized = NormalizedMetadata::from_embedded(PathBuf::from("album.flac"), embedded);

        assert_eq!(normalized.track.title.as_deref(), Some("Original Title"));

        assert_eq!(normalized.track.artist.as_deref(), Some("Original Artist"));

        assert_eq!(normalized.album.album.as_deref(), Some("Original Album"));

        assert_eq!(
            normalized.album.album_artist.as_deref(),
            Some("Album Artist")
        );
    }

    #[test]
    fn cue_can_override_track_title_and_artist() {
        let mut track = NormalizedTrackMetadata {
            title: Some("Embedded Title".to_string()),
            artist: Some("Embedded Artist".to_string()),
            track_number: Some(1),
            disc_number: Some(1),
            composer: None,
        };

        let cue = CueMetadataOverride {
            title: Some("CUE Title".to_string()),
            artist: Some("CUE Artist".to_string()),
            track_number: Some(7),
        };

        track.apply_cue_override(&cue);

        assert_eq!(track.title.as_deref(), Some("CUE Title"));

        assert_eq!(track.artist.as_deref(), Some("CUE Artist"));

        assert_eq!(track.track_number, Some(7));

        assert_eq!(track.disc_number, Some(1));
    }

    #[test]
    fn absent_cue_values_do_not_destroy_embedded_metadata() {
        let mut track = NormalizedTrackMetadata {
            title: Some("Embedded Title".to_string()),
            artist: Some("Embedded Artist".to_string()),
            track_number: Some(3),
            disc_number: Some(1),
            composer: Some("Composer".to_string()),
        };

        let cue = CueMetadataOverride::default();

        track.apply_cue_override(&cue);

        assert_eq!(track.title.as_deref(), Some("Embedded Title"));

        assert_eq!(track.artist.as_deref(), Some("Embedded Artist"));

        assert_eq!(track.track_number, Some(3));

        assert_eq!(track.disc_number, Some(1));

        assert_eq!(track.composer.as_deref(), Some("Composer"));
    }
}
