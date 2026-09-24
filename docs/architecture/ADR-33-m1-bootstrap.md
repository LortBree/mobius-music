# M1 Bootstrap

## Scope

First implementation milestone for macOS Ventura:

1. Probe local FLAC/WAV.
2. Decode with Symphonia.
3. Preserve source sample-rate/channel/bit-depth information.
4. Later connect decoded PCM to native CoreAudio output.

## Constraints

- No Flutter dependency in the audio core.
- No SQLite in the realtime audio path.
- No fixed FLAC frame-size assumptions.
- Decoder frame/block size is independent of CoreAudio render buffer size.
- External USB DAC is required for Hi-Res output acceptance tests.
