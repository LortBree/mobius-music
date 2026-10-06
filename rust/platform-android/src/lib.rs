//! Android audio output backed by the NDK AAudio C API.
//!
//! This is the Android analogue of `offline-player-platform-macos`. It presents
//! the same shape the controller expects from `PcmOutput`:
//! `open_with_equalizer` / `start` / `stop` / `set_volume` / `telemetry`, pulling
//! interleaved `i32` PCM out of an `offline-player-audio-core` ring **consumer**
//! inside an AAudio data callback (a pull model — never a timer).
//!
//! The platform FFI, the AAudio stream type and the realtime callback are all
//! `cfg(target_os = "android")`, so the crate compiles to a near-empty library
//! on macOS (and any other host). The pure PCM channel-mix helper
//! ([`mix_source_frame_into_output`]) is host-compiled and unit-tested.

use offline_player_audio_core::PcmSample;

/// Mix one source-channel frame of i32 PCM into one output-channel frame of
/// normalised, volume-scaled `f32`, handling a channel-count mismatch between
/// what the source decodes and what AAudio actually opened.
///
/// The ring is always interleaved at the SOURCE channel count and the equaliser
/// runs on source channels; only the final write to the device frame changes
/// shape. The rules are the common, well-defined cases:
///
/// - equal counts: straight per-channel copy;
/// - mono source -> N-channel output: duplicate the single sample to every
///   output channel;
/// - stereo (or more) source -> mono output: average the source channels;
/// - any other N->M: fill each output channel from the source channel at the
///   same index when it exists, else the last source channel (so a wider
///   output still receives signal and a narrower one keeps the leading
///   channels). This is a best-effort fallback, not a proper down-mix matrix.
///
/// `src` is one source frame (`src.len()` == source channels, >= 1); `out` is
/// one output frame (`out.len()` == output channels, >= 1). `divisor` maps the
/// integer sample to [-1.0, 1.0] for the source bit depth and `volume` is the
/// linear gain. Allocation-free and panic-free for non-empty slices.
pub fn mix_source_frame_into_output(src: &[PcmSample], out: &mut [f32], divisor: f32, volume: f32) {
    let src_ch = src.len();
    let out_ch = out.len();
    if src_ch == 0 || out_ch == 0 {
        return;
    }

    let norm = |s: PcmSample| (s as f32 / divisor) * volume;

    if src_ch == out_ch {
        for (o, &s) in out.iter_mut().zip(src.iter()) {
            *o = norm(s);
        }
    } else if src_ch == 1 {
        // Mono -> N: duplicate.
        let s = norm(src[0]);
        for o in out.iter_mut() {
            *o = s;
        }
    } else if out_ch == 1 {
        // Stereo/N -> mono: average (sum in f32 then divide).
        let mut acc = 0.0f32;
        for &s in src {
            acc += norm(s);
        }
        out[0] = acc / src_ch as f32;
    } else {
        // Best-effort N -> M: index-matched, clamping to the last source
        // channel so a wider output is still driven on every channel.
        let last = src_ch - 1;
        for (i, o) in out.iter_mut().enumerate() {
            let s = src[i.min(last)];
            *o = norm(s);
        }
    }
}

/// Linear-to-sample divisor for a signed-integer source bit depth, mapping the
/// full-scale integer to 1.0. Factored out so it is host-testable.
pub fn sample_divisor(source_bits: u32) -> f32 {
    if source_bits >= 32 {
        2_147_483_648.0f32
    } else {
        (1u64 << (source_bits.max(1) - 1)) as f32
    }
}

#[cfg(target_os = "android")]
pub mod usb_spike;

#[cfg(target_os = "android")]
pub mod uac2_driver;

#[cfg(target_os = "android")]
mod android {
    use std::{
        ffi::{c_char, c_void, CStr},
        ptr::NonNull,
        slice,
        sync::{
            atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering},
            Arc,
        },
    };

    use offline_player_audio_core::{PcmConsumer, RealtimeEqualizer, SharedEqualizerGains};

    use super::{mix_source_frame_into_output, sample_divisor};

    // =======================================================================
    // AAudio C API bindings (hand-written, no crates.io dependency).
    //
    // Signatures taken from `<ndk>/sysroot/usr/include/aaudio/AAudio.h`
    // (API 26+). The target is API 33, comfortably above AAudio's floor.
    // Opaque builder/stream handles are modelled as pointers to zero-sized
    // `extern` types.
    // =======================================================================

    #[repr(C)]
    struct AAudioStreamBuilder {
        _private: [u8; 0],
    }

    #[repr(C)]
    struct AAudioStream {
        _private: [u8; 0],
    }

    type AaudioResult = i32;
    type AaudioFormat = i32;
    type AaudioDirection = i32;
    type AaudioSharingMode = i32;
    type AaudioPerformanceMode = i32;
    type AaudioUsage = i32;
    type AaudioContentType = i32;
    type AaudioDataCallbackResult = i32;

    // aaudio_result_t
    const AAUDIO_OK: AaudioResult = 0;

    // aaudio_format_t
    const AAUDIO_FORMAT_PCM_FLOAT: AaudioFormat = 2;

    // aaudio_direction_t
    const AAUDIO_DIRECTION_OUTPUT: AaudioDirection = 0;

    // aaudio_sharing_mode_t
    const AAUDIO_SHARING_MODE_SHARED: AaudioSharingMode = 0;

    // aaudio_performance_mode_t
    const AAUDIO_PERFORMANCE_MODE_NONE: AaudioPerformanceMode = 10;

    // aaudio_usage_t
    const AAUDIO_USAGE_MEDIA: AaudioUsage = 1;

    // aaudio_content_type_t
    const AAUDIO_CONTENT_TYPE_MUSIC: AaudioContentType = 2;

    // aaudio_data_callback_result_t
    const AAUDIO_CALLBACK_RESULT_CONTINUE: AaudioDataCallbackResult = 0;

    type AaudioDataCallback = unsafe extern "C" fn(
        stream: *mut AAudioStream,
        user_data: *mut c_void,
        audio_data: *mut c_void,
        num_frames: i32,
    ) -> AaudioDataCallbackResult;

    type AaudioErrorCallback = unsafe extern "C" fn(
        stream: *mut AAudioStream,
        user_data: *mut c_void,
        error: AaudioResult,
    );

    #[link(name = "aaudio")]
    extern "C" {
        fn AAudio_createStreamBuilder(builder: *mut *mut AAudioStreamBuilder) -> AaudioResult;
        fn AAudioStreamBuilder_setDirection(
            builder: *mut AAudioStreamBuilder,
            direction: AaudioDirection,
        );
        fn AAudioStreamBuilder_setSharingMode(
            builder: *mut AAudioStreamBuilder,
            mode: AaudioSharingMode,
        );
        fn AAudioStreamBuilder_setSampleRate(builder: *mut AAudioStreamBuilder, sample_rate: i32);
        fn AAudioStreamBuilder_setChannelCount(
            builder: *mut AAudioStreamBuilder,
            channel_count: i32,
        );
        fn AAudioStreamBuilder_setFormat(builder: *mut AAudioStreamBuilder, format: AaudioFormat);
        fn AAudioStreamBuilder_setPerformanceMode(
            builder: *mut AAudioStreamBuilder,
            mode: AaudioPerformanceMode,
        );
        fn AAudioStreamBuilder_setUsage(builder: *mut AAudioStreamBuilder, usage: AaudioUsage);
        fn AAudioStreamBuilder_setContentType(
            builder: *mut AAudioStreamBuilder,
            content_type: AaudioContentType,
        );
        fn AAudioStreamBuilder_setDataCallback(
            builder: *mut AAudioStreamBuilder,
            callback: AaudioDataCallback,
            user_data: *mut c_void,
        );
        fn AAudioStreamBuilder_setErrorCallback(
            builder: *mut AAudioStreamBuilder,
            callback: AaudioErrorCallback,
            user_data: *mut c_void,
        );
        fn AAudioStreamBuilder_openStream(
            builder: *mut AAudioStreamBuilder,
            stream: *mut *mut AAudioStream,
        ) -> AaudioResult;
        fn AAudioStreamBuilder_delete(builder: *mut AAudioStreamBuilder) -> AaudioResult;

        fn AAudioStream_requestStart(stream: *mut AAudioStream) -> AaudioResult;
        fn AAudioStream_requestStop(stream: *mut AAudioStream) -> AaudioResult;
        fn AAudioStream_close(stream: *mut AAudioStream) -> AaudioResult;
        fn AAudioStream_getSampleRate(stream: *mut AAudioStream) -> i32;
        fn AAudioStream_getChannelCount(stream: *mut AAudioStream) -> i32;

        fn AAudio_convertResultToText(code: AaudioResult) -> *const c_char;
    }

    /// Errors from the AAudio output path.
    #[derive(Debug)]
    pub enum AndroidAudioError {
        /// AAudio returned a negative result code; carries the code and its text.
        Aaudio { code: AaudioResult, text: String },
        /// AAudio returned `OK` but handed back a null builder/stream pointer.
        NullHandle(&'static str),
        /// The negotiated channel count was not positive.
        InvalidChannelCount(i32),
        /// The negotiated sample rate was not positive.
        InvalidSampleRate(i32),
    }

    impl std::fmt::Display for AndroidAudioError {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::Aaudio { code, text } => write!(f, "AAudio error {code}: {text}"),
                Self::NullHandle(what) => write!(f, "AAudio returned a null {what}"),
                Self::InvalidChannelCount(c) => {
                    write!(f, "AAudio negotiated invalid channel count {c}")
                }
                Self::InvalidSampleRate(r) => {
                    write!(f, "AAudio negotiated invalid sample rate {r}")
                }
            }
        }
    }

    impl std::error::Error for AndroidAudioError {}

    fn result_text(code: AaudioResult) -> String {
        // SAFETY: `AAudio_convertResultToText` returns a pointer to a static,
        // NUL-terminated C string for any code; the pointer is non-null and
        // valid for the lifetime of the process. We copy it out immediately.
        unsafe {
            let ptr = AAudio_convertResultToText(code);
            if ptr.is_null() {
                format!("code {code}")
            } else {
                CStr::from_ptr(ptr).to_string_lossy().into_owned()
            }
        }
    }

    fn check(code: AaudioResult) -> Result<(), AndroidAudioError> {
        if code == AAUDIO_OK {
            Ok(())
        } else {
            Err(AndroidAudioError::Aaudio {
                code,
                text: result_text(code),
            })
        }
    }

    /// Telemetry mirroring the macOS `PlaybackTelemetry` fields the controller
    /// consumes for its position clock. Only the counters the controller reads
    /// are tracked; AAudio does not expose the first-buffer byte dump macOS does.
    #[derive(Debug, Clone, Copy)]
    pub struct PlaybackTelemetry {
        pub callback_count: u64,
        pub requested_samples: u64,
        pub consumed_samples: u64,
        pub underrun_samples: u64,
    }

    /// State shared between the control thread and the realtime callback.
    ///
    /// Both sides only ever access this through a shared reference (`&Shared`):
    /// every field is an atomic, so there is never a `&mut` to it anywhere, and
    /// the control thread's `set_volume`/`telemetry`/`is_disconnected` cannot
    /// alias a `&mut` the callback holds (C1). Lives behind an `Arc` cloned once
    /// into the callback-owned struct.
    struct Shared {
        volume: AtomicU32,
        callback_count: AtomicU64,
        requested_samples: AtomicU64,
        consumed_samples: AtomicU64,
        underrun_samples: AtomicU64,
        // Source samples still queued in the ring after the most recent
        // callback pop. Published by the data callback (a lock-free atomic
        // store, RT-safe) and read by the control thread for buffer telemetry.
        ring_fill_samples: AtomicU64,
        // Set by the error callback (headphones unplugged, BT route change) so
        // the controller can notice and reopen the stream. Never panics.
        disconnected: AtomicBool,
    }

    impl Shared {
        fn new() -> Self {
            Self {
                volume: AtomicU32::new(1.0f32.to_bits()),
                callback_count: AtomicU64::new(0),
                requested_samples: AtomicU64::new(0),
                consumed_samples: AtomicU64::new(0),
                underrun_samples: AtomicU64::new(0),
                ring_fill_samples: AtomicU64::new(0),
                disconnected: AtomicBool::new(false),
            }
        }
    }

    /// State owned EXCLUSIVELY by the realtime callback. The control thread
    /// never forms any reference to it after `open` installs its raw pointer,
    /// so the callback may take `&mut CallbackOwned` soundly (C1). It is boxed
    /// so its address is stable for the lifetime of the stream, and freed only
    /// in `PcmOutput::drop` AFTER the stream is stopped+closed (so the callback
    /// can no longer run).
    struct CallbackOwned {
        consumer: PcmConsumer,
        source_bits: u32,
        source_channels: usize,
        output_channels: usize,
        equalizer: Option<RealtimeEqualizer>,
        // Scratch holding whole SOURCE frames pulled from the ring before the
        // equaliser and the channel mix. Sized at open; never reallocated.
        scratch: Vec<i32>,
        shared: Arc<Shared>,
    }

    /// AAudio float output pulling i32 PCM from a ring consumer.
    ///
    /// `user_data` is the raw pointer to the callback-owned `CallbackOwned`
    /// box. The control thread holds a clone of the inner `Arc<Shared>` but
    /// never references `CallbackOwned`, so taking `&mut` here does not alias.
    unsafe extern "C" fn data_callback(
        _stream: *mut AAudioStream,
        user_data: *mut c_void,
        audio_data: *mut c_void,
        num_frames: i32,
    ) -> AaudioDataCallbackResult {
        if user_data.is_null() || audio_data.is_null() || num_frames <= 0 {
            return AAUDIO_CALLBACK_RESULT_CONTINUE;
        }

        // SAFETY: `user_data` is the `*mut CallbackOwned` installed at open.
        // AAudio never calls this concurrently with itself, and `PcmOutput`
        // guarantees the stream is stopped+closed before the box is freed, so
        // this is the only live reference to `CallbackOwned`.
        let owned = unsafe { &mut *(user_data as *mut CallbackOwned) };
        let shared = &*owned.shared;

        shared.callback_count.fetch_add(1, Ordering::Relaxed);

        let out_ch = owned.output_channels.max(1);
        let src_ch = owned.source_channels.max(1);
        let frames = num_frames as usize;
        let out_sample_count = frames.saturating_mul(out_ch);

        // SAFETY: AAudio guarantees `audio_data` points to at least
        // `num_frames * output_channels` floats for a float stream.
        let output = unsafe { slice::from_raw_parts_mut(audio_data as *mut f32, out_sample_count) };

        shared
            .requested_samples
            .fetch_add(out_sample_count as u64, Ordering::Relaxed);

        let divisor = sample_divisor(owned.source_bits);
        let volume = f32::from_bits(shared.volume.load(Ordering::Relaxed));

        // How many whole source frames fit in the scratch buffer per pass.
        let scratch_frames = if owned.scratch.is_empty() {
            0
        } else {
            owned.scratch.len() / src_ch
        };

        let mut filled_frames = 0usize;

        if scratch_frames > 0 {
            while filled_frames < frames {
                // Only pop WHOLE source frames: popping a partial frame and
                // dropping it would desynchronise the interleave (L/R swap)
                // for the rest of the track.
                let available_frames = owned.consumer.len() / src_ch;
                let want_frames = (frames - filled_frames)
                    .min(scratch_frames)
                    .min(available_frames);
                if want_frames == 0 {
                    break;
                }
                let want_samples = want_frames * src_ch;
                let chunk = &mut owned.scratch[..want_samples];
                let got_samples = owned.consumer.pop_slice(chunk);
                // SPSC: the consumer is the only reader, so at least
                // `want_samples` are poppable; guard anyway.
                let got_frames = got_samples / src_ch;
                if got_frames == 0 {
                    break;
                }
                let usable = &mut chunk[..got_frames * src_ch];
                if let Some(eq) = owned.equalizer.as_mut() {
                    eq.process(usable);
                }
                for f in 0..got_frames {
                    let src_frame = &usable[f * src_ch..f * src_ch + src_ch];
                    let out_base = (filled_frames + f) * out_ch;
                    let out_frame = &mut output[out_base..out_base + out_ch];
                    mix_source_frame_into_output(src_frame, out_frame, divisor, volume);
                }
                filled_frames += got_frames;
                if got_frames < want_frames {
                    break;
                }
            }
        }

        let consumed_output_samples = filled_frames * out_ch;
        shared
            .consumed_samples
            .fetch_add(consumed_output_samples as u64, Ordering::Relaxed);

        // Publish how many SOURCE samples remain queued ahead of the device so
        // the control thread can report buffer depth. Lock-free store, RT-safe.
        shared
            .ring_fill_samples
            .store(owned.consumer.len() as u64, Ordering::Relaxed);

        // Underrun -> silence (never a crash, never stale audio).
        if filled_frames < frames {
            let missing = out_sample_count - consumed_output_samples;
            shared
                .underrun_samples
                .fetch_add(missing as u64, Ordering::Relaxed);
            output[consumed_output_samples..].fill(0.0);
        }

        AAUDIO_CALLBACK_RESULT_CONTINUE
    }

    /// Error callback: flag the disconnect so the controller can reopen. Per the
    /// AAudio contract we do NOT stop/close/reopen from inside this callback.
    unsafe extern "C" fn error_callback(
        _stream: *mut AAudioStream,
        user_data: *mut c_void,
        _error: AaudioResult,
    ) {
        if user_data.is_null() {
            return;
        }
        // SAFETY: `user_data` is `Arc::as_ptr` of the `Shared` the stream
        // owner keeps alive until after close. Only atomics are touched, and
        // CallbackOwned (which the data callback holds `&mut` to, possibly on
        // another thread) is never referenced here.
        let shared = unsafe { &*(user_data as *const Shared) };
        shared.disconnected.store(true, Ordering::Release);
    }

    pub enum PcmBackend {
        Aaudio {
            stream: NonNull<AAudioStream>,
            negotiated_sample_rate: u32,
            negotiated_channels: u32,
            shared: Arc<Shared>,
            #[allow(dead_code)]
            owned: Box<CallbackOwned>,
        },
        Uac2(super::uac2_driver::Uac2Output),
    }

    /// Audio output pulling PCM from a ring consumer, backed by either
    /// AAudio (system mixer) or direct UAC2 (bit-perfect USB DAC).
    pub struct PcmOutput {
        backend: PcmBackend,
    }

    // SAFETY: Output handles are moved across controller threads.
    unsafe impl Send for PcmOutput {}

    impl PcmOutput {
        pub fn open_with_equalizer(
            consumer: PcmConsumer,
            requested_sample_rate: u32,
            source_channels: u32,
            source_bits: u32,
            equalizer: Option<Arc<SharedEqualizerGains>>,
        ) -> Result<Self, AndroidAudioError> {
            if let Some(dac) = super::uac2_driver::get_active_usb_dac() {
                if dac.fd >= 0 {
                    match super::uac2_driver::Uac2Output::open(
                        dac.fd,
                        consumer,
                        requested_sample_rate,
                        source_channels,
                        source_bits,
                        equalizer,
                    ) {
                        Ok(uac2) => {
                            return Ok(Self {
                                backend: PcmBackend::Uac2(uac2),
                            });
                        }
                        Err(err) => {
                            eprintln!("[Mobius UAC2] UAC2 output open failed on fd {}: {err}", dac.fd);
                            return Err(AndroidAudioError::Aaudio {
                                code: -1,
                                text: format!("UAC2 output open failed on fd {}: {err}", dac.fd),
                            });
                        }
                    }
                }
            }

            // Scratch holds whole source frames; sized ~16k samples like macOS,
            // rounded down to a whole number of source frames.
            const SCRATCH_SAMPLES: usize = 16_384;
            let src_ch = source_channels.max(1) as usize;

            let realtime_equalizer = equalizer.map(|shared| {
                RealtimeEqualizer::new(shared, requested_sample_rate.max(1), src_ch, source_bits)
            });
            let scratch = if realtime_equalizer.is_some() {
                let frames = (SCRATCH_SAMPLES / src_ch).max(1);
                vec![0; frames * src_ch]
            } else {
                let frames = (SCRATCH_SAMPLES / src_ch).max(1);
                vec![0; frames * src_ch]
            };

            let shared = Arc::new(Shared::new());

            let mut owned = Box::new(CallbackOwned {
                consumer,
                source_bits,
                source_channels: src_ch,
                output_channels: src_ch,
                equalizer: realtime_equalizer,
                scratch,
                shared: Arc::clone(&shared),
            });

            let user_data = (&mut *owned as *mut CallbackOwned).cast::<c_void>();
            let error_user_data = Arc::as_ptr(&shared) as *mut c_void;

            let mut builder: *mut AAudioStreamBuilder = std::ptr::null_mut();
            check(unsafe { AAudio_createStreamBuilder(&mut builder) })?;
            let builder =
                NonNull::new(builder).ok_or(AndroidAudioError::NullHandle("stream builder"))?;

            let stream_result = unsafe {
                let b = builder.as_ptr();
                AAudioStreamBuilder_setDirection(b, AAUDIO_DIRECTION_OUTPUT);
                AAudioStreamBuilder_setSharingMode(b, AAUDIO_SHARING_MODE_SHARED);
                AAudioStreamBuilder_setSampleRate(b, requested_sample_rate as i32);
                AAudioStreamBuilder_setChannelCount(b, src_ch as i32);
                AAudioStreamBuilder_setFormat(b, AAUDIO_FORMAT_PCM_FLOAT);
                AAudioStreamBuilder_setPerformanceMode(b, AAUDIO_PERFORMANCE_MODE_NONE);
                AAudioStreamBuilder_setUsage(b, AAUDIO_USAGE_MEDIA);
                AAudioStreamBuilder_setContentType(b, AAUDIO_CONTENT_TYPE_MUSIC);
                AAudioStreamBuilder_setDataCallback(b, data_callback, user_data);
                AAudioStreamBuilder_setErrorCallback(b, error_callback, error_user_data);

                let mut stream: *mut AAudioStream = std::ptr::null_mut();
                let code = AAudioStreamBuilder_openStream(b, &mut stream);
                (code, stream)
            };

            let _ = unsafe { AAudioStreamBuilder_delete(builder.as_ptr()) };

            let (open_code, stream_ptr) = stream_result;
            check(open_code)?;
            let stream = NonNull::new(stream_ptr).ok_or(AndroidAudioError::NullHandle("stream"))?;

            let negotiated_sample_rate = unsafe { AAudioStream_getSampleRate(stream.as_ptr()) };
            let negotiated_channels = unsafe { AAudioStream_getChannelCount(stream.as_ptr()) };

            if negotiated_channels <= 0 {
                let _ = unsafe { AAudioStream_close(stream.as_ptr()) };
                return Err(AndroidAudioError::InvalidChannelCount(negotiated_channels));
            }
            if negotiated_sample_rate <= 0 {
                let _ = unsafe { AAudioStream_close(stream.as_ptr()) };
                return Err(AndroidAudioError::InvalidSampleRate(negotiated_sample_rate));
            }

            owned.output_channels = negotiated_channels as usize;

            Ok(Self {
                backend: PcmBackend::Aaudio {
                    stream,
                    negotiated_sample_rate: negotiated_sample_rate as u32,
                    negotiated_channels: negotiated_channels as u32,
                    shared,
                    owned,
                },
            })
        }

        pub fn is_usb_dac(&self) -> bool {
            matches!(self.backend, PcmBackend::Uac2(_))
        }

        pub fn sample_rate(&self) -> u32 {
            match &self.backend {
                PcmBackend::Aaudio { negotiated_sample_rate, .. } => *negotiated_sample_rate,
                PcmBackend::Uac2(uac2) => uac2.sample_rate(),
            }
        }

        pub fn channels(&self) -> u32 {
            match &self.backend {
                PcmBackend::Aaudio { negotiated_channels, .. } => *negotiated_channels,
                PcmBackend::Uac2(uac2) => uac2.channels(),
            }
        }

        pub fn is_disconnected(&self) -> bool {
            match &self.backend {
                PcmBackend::Aaudio { shared, .. } => shared.disconnected.load(Ordering::Acquire),
                PcmBackend::Uac2(uac2) => uac2.is_disconnected(),
            }
        }

        pub fn queued_source_samples(&self) -> u64 {
            match &self.backend {
                PcmBackend::Aaudio { shared, .. } => shared.ring_fill_samples.load(Ordering::Relaxed),
                PcmBackend::Uac2(uac2) => uac2.queued_source_samples(),
            }
        }

        pub fn start(&self) -> Result<(), AndroidAudioError> {
            match &self.backend {
                PcmBackend::Aaudio { stream, .. } => {
                    check(unsafe { AAudioStream_requestStart(stream.as_ptr()) })
                }
                PcmBackend::Uac2(uac2) => {
                    uac2.start().map_err(|e| AndroidAudioError::Aaudio { code: -1, text: e })
                }
            }
        }

        pub fn stop(&self) -> Result<(), AndroidAudioError> {
            match &self.backend {
                PcmBackend::Aaudio { stream, .. } => {
                    check(unsafe { AAudioStream_requestStop(stream.as_ptr()) })
                }
                PcmBackend::Uac2(uac2) => {
                    uac2.stop().map_err(|e| AndroidAudioError::Aaudio { code: -1, text: e })
                }
            }
        }

        pub fn set_volume(&self, volume: f32) {
            match &self.backend {
                PcmBackend::Aaudio { shared, .. } => {
                    shared.volume.store(volume.to_bits(), Ordering::Relaxed);
                }
                PcmBackend::Uac2(uac2) => {
                    let _ = uac2.set_volume(volume);
                }
            }
        }

        pub fn set_software_volume(&self, volume: f32) {
            match &self.backend {
                PcmBackend::Aaudio { shared, .. } => {
                    shared.volume.store(volume.to_bits(), Ordering::Relaxed);
                }
                PcmBackend::Uac2(uac2) => {
                    let _ = uac2.set_software_volume(volume);
                }
            }
        }

        pub fn set_hardware_volume(&self, volume: f32) {
            match &self.backend {
                PcmBackend::Aaudio { .. } => {}
                PcmBackend::Uac2(uac2) => {
                    let _ = uac2.set_hardware_volume(volume);
                }
            }
        }

        pub fn set_bit_perfect_mode(&self, enabled: bool) {
            match &self.backend {
                PcmBackend::Aaudio { .. } => {}
                PcmBackend::Uac2(uac2) => {
                    let _ = uac2.set_bit_perfect_mode(enabled);
                }
            }
        }

        pub fn is_bit_perfect_mode(&self) -> bool {
            match &self.backend {
                PcmBackend::Aaudio { .. } => false,
                PcmBackend::Uac2(uac2) => uac2.is_bit_perfect_mode(),
            }
        }

        pub fn hardware_volume(&self) -> f32 {
            match &self.backend {
                PcmBackend::Aaudio { .. } => 1.0,
                PcmBackend::Uac2(uac2) => uac2.hardware_volume(),
            }
        }

        pub fn software_volume(&self) -> f32 {
            match &self.backend {
                PcmBackend::Aaudio { shared, .. } => f32::from_bits(shared.volume.load(Ordering::Relaxed)),
                PcmBackend::Uac2(uac2) => uac2.software_volume(),
            }
        }

        pub fn telemetry(&self) -> PlaybackTelemetry {
            match &self.backend {
                PcmBackend::Aaudio { shared, .. } => PlaybackTelemetry {
                    callback_count: shared.callback_count.load(Ordering::Relaxed),
                    requested_samples: shared.requested_samples.load(Ordering::Relaxed),
                    consumed_samples: shared.consumed_samples.load(Ordering::Relaxed),
                    underrun_samples: shared.underrun_samples.load(Ordering::Relaxed),
                },
                PcmBackend::Uac2(uac2) => uac2.telemetry(),
            }
        }
    }

    impl Drop for PcmOutput {
        fn drop(&mut self) {
            if let PcmBackend::Aaudio { stream, .. } = &mut self.backend {
                unsafe {
                    let _ = AAudioStream_requestStop(stream.as_ptr());
                    let _ = AAudioStream_close(stream.as_ptr());
                }
            }
        }
    }
}

#[cfg(target_os = "android")]
pub use android::{AndroidAudioError, PcmOutput, PlaybackTelemetry};

#[cfg(test)]
mod tests {
    use super::{mix_source_frame_into_output, sample_divisor};

    const D16: f32 = 32_768.0; // divisor for 16-bit

    fn mix(src: &[i32], out_ch: usize) -> Vec<f32> {
        let mut out = vec![0.0f32; out_ch];
        mix_source_frame_into_output(src, &mut out, D16, 1.0);
        out
    }

    #[test]
    fn divisor_matches_bit_depth() {
        assert_eq!(sample_divisor(16), 32_768.0);
        assert_eq!(sample_divisor(24), 8_388_608.0);
        assert_eq!(sample_divisor(32), 2_147_483_648.0);
        // Clamps a degenerate zero to the 1-bit divisor (1.0), never panics.
        assert_eq!(sample_divisor(0), 1.0);
    }

    #[test]
    fn equal_channel_counts_copy_through() {
        let out = mix(&[16_384, -16_384], 2);
        assert_eq!(out, vec![0.5, -0.5]);
    }

    #[test]
    fn mono_source_duplicates_to_stereo() {
        let out = mix(&[16_384], 2);
        assert_eq!(out, vec![0.5, 0.5]);
    }

    #[test]
    fn mono_source_fills_surround() {
        let out = mix(&[-32_768], 6);
        assert_eq!(out, vec![-1.0; 6]);
    }

    #[test]
    fn stereo_source_averages_to_mono() {
        // (0.5 + -0.5) / 2 = 0.0
        let out = mix(&[16_384, -16_384], 1);
        assert_eq!(out, vec![0.0]);
        // (0.5 + 0.5) / 2 = 0.5
        let out = mix(&[16_384, 16_384], 1);
        assert_eq!(out, vec![0.5]);
    }

    #[test]
    fn surround_source_averages_to_mono() {
        // four channels at 0.25 each -> mean 0.25
        let q = 8_192; // 0.25 * 32768
        let out = mix(&[q, q, q, q], 1);
        assert!((out[0] - 0.25).abs() < 1e-6);
    }

    #[test]
    fn wider_output_than_source_is_index_matched_and_clamped() {
        // stereo source -> 3-channel output: ch0=L, ch1=R, ch2=last(R)
        let out = mix(&[16_384, -16_384], 3);
        assert_eq!(out, vec![0.5, -0.5, -0.5]);
    }

    #[test]
    fn volume_scales_output() {
        let mut out = [0.0f32; 2];
        mix_source_frame_into_output(&[16_384, 16_384], &mut out, D16, 0.5);
        assert_eq!(out, [0.25, 0.25]);
    }

    #[test]
    fn empty_slices_are_noops() {
        let mut out: [f32; 0] = [];
        mix_source_frame_into_output(&[1, 2], &mut out, D16, 1.0);
        let mut out2 = [1.0f32, 2.0];
        mix_source_frame_into_output(&[], &mut out2, D16, 1.0);
        // untouched because src is empty
        assert_eq!(out2, [1.0, 2.0]);
    }
}
