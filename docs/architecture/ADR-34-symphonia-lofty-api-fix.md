# ADR-34 — Symphonia / Lofty API Compatibility Fix

Applied for Symphonia 0.6.1 and Lofty 0.25.1.

- Treat `Track::codec_params` as `Option<CodecParameters>`.
- Prefer `Track::num_frames` and fall back to `CodecParameters::n_frames`.
- Remove the unused `FormatReader` import.
- Use Lofty `FileParseError`.
- Convert Lofty `Cow<str>` values with `into_owned()`.
- Pass `ItemKey::AlbumArtist` by value.

Validation: not compiled in the artifact build environment because Rust/Cargo is unavailable there.
