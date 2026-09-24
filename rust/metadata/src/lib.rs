use std::path::Path;

use lofty::{file::TaggedFileExt, picture::PictureType, prelude::*, probe::Probe, tag::ItemKey};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum MetadataError {
    #[error("failed to read metadata: {0}")]
    Probe(#[from] lofty::error::FileParseError),
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct EmbeddedArtwork {
    pub mime_type: Option<String>,
    pub data: Vec<u8>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
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

pub fn read(path: &Path) -> Result<EmbeddedMetadata, MetadataError> {
    let tagged_file = Probe::open(path)?.read()?;

    let Some(tag) = tagged_file
        .primary_tag()
        .or_else(|| tagged_file.first_tag())
    else {
        return Ok(EmbeddedMetadata::default());
    };

    let track_number = tag.track();

    let disc_number = tag.disk();

    let date = tag
        .get_string(ItemKey::RecordingDate)
        .or_else(|| tag.get_string(ItemKey::ReleaseDate))
        .map(str::to_owned);

    let artwork = select_artwork(tag.pictures());

    Ok(EmbeddedMetadata {
        title: tag.title().map(|value| value.into_owned()),

        artist: tag.artist().map(|value| value.into_owned()),

        album: tag.album().map(|value| value.into_owned()),

        album_artist: tag.get_string(ItemKey::AlbumArtist).map(str::to_owned),

        composer: tag.get_string(ItemKey::Composer).map(str::to_owned),

        genre: tag.genre().map(|value| value.into_owned()),

        date,

        track_number,

        disc_number,

        artwork,
    })
}

fn select_artwork(pictures: &[lofty::picture::Picture]) -> Option<EmbeddedArtwork> {
    let picture = pictures
        .iter()
        .find(|picture| picture.pic_type() == PictureType::CoverFront)
        .or_else(|| {
            pictures
                .iter()
                .find(|picture| picture.pic_type() == PictureType::Other)
        })
        .or_else(|| pictures.first())?;

    Some(EmbeddedArtwork {
        mime_type: picture.mime_type().map(|mime| mime.as_str().to_owned()),

        data: picture.data().to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_tags_return_empty_metadata() {
        //
        // This test is intentionally about the normalization
        // contract rather than a real fixture file.
        //
        let metadata = EmbeddedMetadata::default();

        assert_eq!(metadata.title, None);

        assert_eq!(metadata.artist, None);

        assert_eq!(metadata.album, None);

        assert_eq!(metadata.album_artist, None);

        assert_eq!(metadata.composer, None);

        assert_eq!(metadata.genre, None);

        assert_eq!(metadata.date, None);

        assert_eq!(metadata.track_number, None);

        assert_eq!(metadata.disc_number, None);

        assert_eq!(metadata.artwork, None);
    }

    #[test]
    fn empty_picture_list_has_no_artwork() {
        assert_eq!(select_artwork(&[]), None);
    }
}
