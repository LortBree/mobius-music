//! Direct UAC2 (USB Audio Class 2.0) output driver for bit-perfect playback.
//!
//! Streams decoded PCM directly to Endpoint 0x04 on Interface 2 of the USB DAC,
//! completely bypassing Android's AudioFlinger, ALSA user-space daemon, and system mixer.
//!
//! Formats:
//! - Dynamic Alt-setting selection on Interface 2 matching track bit depth:
//!   - Alt 1: 16-bit PCM (bSubslotSize = 2, 4 bytes/stereo frame).
//!   - Alt 2: 24-bit PCM (bSubslotSize = 3, 6 bytes/stereo frame).
//!   - Alt 3: 32-bit PCM (bSubslotSize = 4, 8 bytes/stereo frame).
//! - Sets hardware oscillator rate via Clock Source ID 1 (CS_SAM_FREQ_CONTROL).
//! - Realtime isochronous packet streaming synchronized with USB High-Speed microframes.

#[cfg(target_os = "android")]
use std::{
    ffi::c_void,
    ptr,
    slice,
    sync::{
        atomic::{AtomicBool, AtomicI32, AtomicU32, AtomicU64, Ordering},
        Arc, RwLock,
    },
    thread,
    time::Duration,
};

use offline_player_audio_core::{PcmConsumer, RealtimeEqualizer, SharedEqualizerGains};
use crate::PlaybackTelemetry;

#[cfg(target_os = "android")]
extern "C" {
    fn __android_log_print(
        prio: libc::c_int,
        tag: *const libc::c_char,
        fmt: *const libc::c_char,
        ...
    ) -> libc::c_int;
}

macro_rules! log_info {
    ($($arg:tt)*) => {
        #[cfg(target_os = "android")]
        {
            let msg = std::ffi::CString::new(format!($($arg)*)).unwrap_or_default();
            let tag = std::ffi::CString::new("MobiusUac2").unwrap();
            #[allow(unused_unsafe)]
            unsafe {
                __android_log_print(4, tag.as_ptr(), b"%s\0".as_ptr() as *const libc::c_char, msg.as_ptr());
            }
        }
        #[cfg(not(target_os = "android"))]
        {
            let _ = format!($($arg)*);
        }
    };
}

macro_rules! log_error {
    ($($arg:tt)*) => {
        #[cfg(target_os = "android")]
        {
            let msg = std::ffi::CString::new(format!($($arg)*)).unwrap_or_default();
            let tag = std::ffi::CString::new("MobiusUac2").unwrap();
            #[allow(unused_unsafe)]
            unsafe {
                __android_log_print(6, tag.as_ptr(), b"%s\0".as_ptr() as *const libc::c_char, msg.as_ptr());
            }
        }
        #[cfg(not(target_os = "android"))]
        {
            let _ = format!($($arg)*);
        }
    };
}

#[derive(Debug, Clone, Copy)]
pub struct UsbDacConfig {
    pub fd: i32,
    pub vid: u16,
    pub pid: u16,
}

static ACTIVE_USB_DAC: RwLock<Option<UsbDacConfig>> = RwLock::new(None);

pub fn set_active_usb_dac(config: Option<UsbDacConfig>) {
    log_info!("set_active_usb_dac: {:?}", config);
    let mut lock = ACTIVE_USB_DAC.write().unwrap();
    *lock = config;
}

pub fn get_active_usb_dac() -> Option<UsbDacConfig> {
    *ACTIVE_USB_DAC.read().unwrap()
}

/// Map linear volume (0.0 to 1.0) to UAC2 8.8 fixed-point dB for JA11 Feature Unit 7.
/// JA11 range: -50 dB (0xCE00) to 0 dB (0x0000).
pub fn volume_to_hw_db(volume: f32) -> (i16, bool) {
    if volume <= 0.001 {
        // Full mute and -50 dB
        return (-50 * 256, true);
    }
    let v = volume.clamp(0.001, 1.0);
    // Smooth perceptual curve:
    // v = 1.0 -> 0.0 dB
    // v = 0.5 -> -14.6 dB
    // v = 0.25 -> -25.0 dB
    // v = 0.10 -> -34.2 dB
    // v = 0.01 -> -50.0 dB
    let db = -50.0 * (1.0 - v.sqrt());
    let db_clamped = db.clamp(-50.0, 0.0);
    let units = (db_clamped * 256.0).round() as i16;
    (units, false)
}

pub struct Uac2Shared {
    pub running: AtomicBool,
    pub playing: AtomicBool,
    pub disconnected: AtomicBool,
    pub bit_perfect_mode: AtomicBool,
    pub software_volume: AtomicU32,
    pub hardware_volume: AtomicU32,
    pub volume: AtomicU32,
    pub target_hw_volume_db: AtomicI32,
    pub target_mute: AtomicBool,
    pub callback_count: AtomicU64,
    pub requested_samples: AtomicU64,
    pub consumed_samples: AtomicU64,
    pub underrun_samples: AtomicU64,
    pub ring_fill_samples: AtomicU64,
    /// Latest validated feedback from EP 0x85: frames per microframe, Q16.16.
    /// 0 = no valid feedback yet (fall back to nominal).
    pub feedback_q16: AtomicU32,
    /// Nominal frames per microframe for the opened rate, Q16.16.
    pub nominal_q16: AtomicU32,
    pub feedback_packets: AtomicU64,
}

impl Uac2Shared {
    pub fn new() -> Self {
        // Safe default hardware volume: 0.36 -> -20.0 dB on FiiO JA11
        let safe_hw_vol = 0.36f32;
        let (initial_units, initial_mute) = volume_to_hw_db(safe_hw_vol);
        Self {
            running: AtomicBool::new(true),
            playing: AtomicBool::new(false),
            disconnected: AtomicBool::new(false),
            bit_perfect_mode: AtomicBool::new(true),
            software_volume: AtomicU32::new(1.0f32.to_bits()),
            hardware_volume: AtomicU32::new(safe_hw_vol.to_bits()),
            volume: AtomicU32::new(safe_hw_vol.to_bits()),
            target_hw_volume_db: AtomicI32::new(initial_units as i32),
            target_mute: AtomicBool::new(initial_mute),
            callback_count: AtomicU64::new(0),
            requested_samples: AtomicU64::new(0),
            consumed_samples: AtomicU64::new(0),
            underrun_samples: AtomicU64::new(0),
            ring_fill_samples: AtomicU64::new(0),
            feedback_q16: AtomicU32::new(0),
            nominal_q16: AtomicU32::new(0),
            feedback_packets: AtomicU64::new(0),
        }
    }
}

#[cfg(target_os = "android")]
struct ThreadContext {
    consumer: PcmConsumer,
    source_channels: usize,
    source_bits: u32,
    sample_rate: u32,
    alt_setting: u32,
    bytes_per_sample: usize,
    bytes_per_frame: usize,
    equalizer: Option<RealtimeEqualizer>,
    shared: Arc<Uac2Shared>,
    rate_accumulator: u32,
    nominal_q16: u32,
    scratch: Vec<i32>,
}

/// Decode a raw UAC2 high-speed feedback value into Q16.16 frames/microframe,
/// accepting it only if it is within ±12.5% of nominal. Some devices report
/// per-1ms-frame instead of per-microframe (8x), so that variant is tried too.
#[cfg(target_os = "android")]
fn decode_feedback(raw: u32, nominal_q16: u32) -> Option<u32> {
    if raw == 0 || nominal_q16 == 0 {
        return None;
    }
    let tol = nominal_q16 / 8;
    let lo = nominal_q16.saturating_sub(tol);
    let hi = nominal_q16.saturating_add(tol);
    [raw, raw >> 3, raw << 2, raw >> 1, raw << 3, raw >> 2]
        .into_iter()
        .find(|v| *v >= lo && *v <= hi)
}

#[cfg(target_os = "android")]
extern "system" fn uac2_feedback_cb(transfer: *mut libusb1_sys::libusb_transfer) {
    if transfer.is_null() {
        return;
    }
    unsafe {
        let shared_ptr = (*transfer).user_data as *const Uac2Shared;
        if shared_ptr.is_null() {
            return;
        }
        let shared = &*shared_ptr;
        let status = (*transfer).status;
        if status == libusb1_sys::constants::LIBUSB_TRANSFER_CANCELLED
            || !shared.running.load(Ordering::Relaxed)
        {
            return;
        }

        let n = (*transfer).num_iso_packets as usize;
        let descs = slice::from_raw_parts_mut((*transfer).iso_packet_desc.as_mut_ptr(), n);
        let buf = (*transfer).buffer;
        let nominal = shared.nominal_q16.load(Ordering::Relaxed);

        if status == libusb1_sys::constants::LIBUSB_TRANSFER_COMPLETED {
            for (i, d) in descs.iter().enumerate() {
                if d.status != libusb1_sys::constants::LIBUSB_TRANSFER_COMPLETED || d.actual_length < 3 {
                    continue;
                }
                let p = buf.add(i * 4);
                let b3 = if d.actual_length >= 4 { *p.add(3) as u32 } else { 0 };
                let raw = (*p as u32) | ((*p.add(1) as u32) << 8) | ((*p.add(2) as u32) << 16) | (b3 << 24);
                let decoded = decode_feedback(raw, nominal);
                let count = shared.feedback_packets.fetch_add(1, Ordering::Relaxed);
                if count < 5 || count % 2000 == 0 {
                    log_info!(
                        "UAC2 feedback #{}: len={}, raw=0x{:08X} -> decoded={:?} (nominal=0x{:08X})",
                        count, d.actual_length, raw, decoded, nominal
                    );
                }
                if let Some(v) = decoded {
                    let prev = shared.feedback_q16.load(Ordering::Relaxed);
                    let smoothed = if prev == 0 {
                        v
                    } else {
                        // Exponential moving average: 1/8 new sample, 7/8 previous sample
                        // Smooths out high-frequency jitter without introducing phase delay.
                        ((prev as u64 * 7 + v as u64) / 8) as u32
                    };
                    shared.feedback_q16.store(smoothed, Ordering::Relaxed);
                }
            }
        }

        // Libusb requirement: re-initialize packet lengths prior to resubmitting
        for d in descs.iter_mut() {
            d.length = 4;
        }

        if shared.running.load(Ordering::Relaxed) {
            if libusb1_sys::libusb_submit_transfer(transfer) != 0 {
                // Feedback lost: keep streaming at the last known / nominal rate.
                log_error!("UAC2 feedback resubmit failed");
            }
        }
    }
}

#[cfg(target_os = "android")]
pub struct Uac2Output {
    shared: Arc<Uac2Shared>,
    sample_rate: u32,
    channels: u32,
    thread_handle: Option<thread::JoinHandle<()>>,
}

#[cfg(target_os = "android")]
extern "system" fn uac2_out_transfer_cb(transfer: *mut libusb1_sys::libusb_transfer) {
    if transfer.is_null() {
        return;
    }
    unsafe {
        let ctx_ptr = (*transfer).user_data as *mut ThreadContext;
        if ctx_ptr.is_null() {
            return;
        }
        let ctx = &mut *ctx_ptr;

        if (*transfer).status != libusb1_sys::constants::LIBUSB_TRANSFER_COMPLETED {
            if (*transfer).status == libusb1_sys::constants::LIBUSB_TRANSFER_CANCELLED {
                return;
            }
            if (*transfer).status == libusb1_sys::constants::LIBUSB_TRANSFER_NO_DEVICE {
                log_error!("UAC2 transfer NO_DEVICE");
                ctx.shared.disconnected.store(true, Ordering::Release);
                return;
            }
            log_error!("UAC2 transfer completed with status {}", (*transfer).status);
            if !ctx.shared.running.load(Ordering::Relaxed) {
                return;
            }
            let buf = (*transfer).buffer;
            let len = (*transfer).length as usize;
            if !buf.is_null() && len > 0 {
                slice::from_raw_parts_mut(buf, len).fill(0);
            }
            let res = libusb1_sys::libusb_submit_transfer(transfer);
            if res != 0 {
                log_error!("Recovery libusb_submit_transfer failed: {}", res);
                ctx.shared.disconnected.store(true, Ordering::Release);
            }
            return;
        }

        if !ctx.shared.running.load(Ordering::Relaxed) {
            return;
        }

        let cb_idx = ctx.shared.callback_count.fetch_add(1, Ordering::Relaxed);
        let num_packets = (*transfer).num_iso_packets as usize;
        let packet_descs = slice::from_raw_parts_mut((*transfer).iso_packet_desc.as_mut_ptr(), num_packets);
        let buf = (*transfer).buffer;

        let is_playing = ctx.shared.playing.load(Ordering::Relaxed);
        let volume = f32::from_bits(ctx.shared.volume.load(Ordering::Relaxed));
        let src_ch = ctx.source_channels.max(1);
        let bytes_per_frame = ctx.bytes_per_frame;

        if cb_idx % 1000 == 0 {
            log_info!(
                "UAC2 cb #{}: playing={}, vol={:.2}, req={}, cons={}, underrun={}, q_fill={}, fb_q16={} (nominal {}), fb_pkts={}",
                cb_idx,
                is_playing,
                volume,
                ctx.shared.requested_samples.load(Ordering::Relaxed),
                ctx.shared.consumed_samples.load(Ordering::Relaxed),
                ctx.shared.underrun_samples.load(Ordering::Relaxed),
                ctx.consumer.len(),
                ctx.shared.feedback_q16.load(Ordering::Relaxed),
                ctx.nominal_q16,
                ctx.shared.feedback_packets.load(Ordering::Relaxed),
            );
        }

        // Asynchronous DAC: the device tells us (EP 0x85) how many frames per
        // microframe it actually consumes. Fall back to nominal until known.
        let fb = ctx.shared.feedback_q16.load(Ordering::Relaxed);
        let base_step_q16 = if fb != 0 { fb } else { ctx.nominal_q16 };

        // Soft PLL / Elastic Drift Compensation:
        // Monitor ring buffer fill level to subtly compensate for any residual clock drift
        // or unhandled feedback jitter. If the ring buffer is draining below 35% capacity,
        // slightly slow down consumption (~0.05% speed, completely inaudible).
        // If the ring buffer is filling up above 75%, slightly speed up (+0.05%).
        let ring_len = ctx.consumer.len();
        let ring_cap = ctx.consumer.capacity().max(1);
        let fill_pct = (ring_len * 100) / ring_cap;
        let drift_adjust: i32 = if fill_pct < 35 {
            -((ctx.nominal_q16 >> 11).max(1) as i32)
        } else if fill_pct > 75 {
            (ctx.nominal_q16 >> 11).max(1) as i32
        } else {
            0
        };
        let step_q16 = ((base_step_q16 as i32 + drift_adjust).max(1)) as u32;

        let mut buf_offset = 0usize;

        for desc in packet_descs.iter_mut() {
            // Q16.16 fractional accumulator per 125 us microframe
            ctx.rate_accumulator += step_q16;
            let frames_this_uframe = (ctx.rate_accumulator >> 16) as usize;
            ctx.rate_accumulator &= 0xFFFF;

            let bytes_this_uframe = frames_this_uframe * bytes_per_frame;
            desc.length = bytes_this_uframe as u32;

            let uframe_buf = slice::from_raw_parts_mut(buf.add(buf_offset), bytes_this_uframe);
            buf_offset += bytes_this_uframe;

            if !is_playing {
                // When paused, stream silence to keep hardware DAC clock locked
                uframe_buf.fill(0);
                continue;
            }

            ctx.shared.requested_samples.fetch_add((frames_this_uframe * 2) as u64, Ordering::Relaxed);

            // Pop frames from consumer
            let want_source_samples = frames_this_uframe * src_ch;
            if ctx.scratch.len() < want_source_samples {
                ctx.scratch.resize(want_source_samples, 0);
            }

            let chunk = &mut ctx.scratch[..want_source_samples];
            let got_samples = ctx.consumer.pop_slice(chunk);
            let got_frames = got_samples / src_ch;

            if let Some(eq) = ctx.equalizer.as_mut() {
                if got_frames > 0 {
                    eq.process(&mut chunk[..got_frames * src_ch]);
                }
            }

            let is_bit_perfect = ctx.shared.bit_perfect_mode.load(Ordering::Relaxed);
            let sw_vol = if is_bit_perfect {
                1.0f32
            } else {
                f32::from_bits(ctx.shared.software_volume.load(Ordering::Relaxed)).clamp(0.0, 1.0)
            };
            let apply_sw_vol = sw_vol < 0.999;

            // Pack frames into wire buffer matching the active Alt-Setting.
            // In Bit-Perfect mode: hardware volume (Feature Unit 7 on DAC) controls level,
            // so audio PCM is passed 100% bit-perfect without digital scaling degradation!
            // In Standard mode: software digital attenuation is applied if sw_vol < 1.0.
            for f in 0..frames_this_uframe {
                let out_offset = f * bytes_per_frame;
                if f < got_frames {
                    let (mut left_raw, mut right_raw) = if src_ch == 1 {
                        (chunk[f], chunk[f])
                    } else {
                        (chunk[f * src_ch], chunk[f * src_ch + 1])
                    };

                    if apply_sw_vol {
                        left_raw = (left_raw as f32 * sw_vol) as i32;
                        right_raw = (right_raw as f32 * sw_vol) as i32;
                    }

                    match ctx.alt_setting {
                        1 => {
                            // 16-bit PCM (bSubslotSize = 2, 4 bytes/stereo frame)
                            let left = if ctx.source_bits <= 16 {
                                left_raw
                            } else if ctx.source_bits == 24 {
                                left_raw >> 8
                            } else {
                                left_raw >> 16
                            };
                            let right = if ctx.source_bits <= 16 {
                                right_raw
                            } else if ctx.source_bits == 24 {
                                right_raw >> 8
                            } else {
                                right_raw >> 16
                            };

                            let left_s16 = left.clamp(-32768, 32767) as i16;
                            let right_s16 = right.clamp(-32768, 32767) as i16;

                            uframe_buf[out_offset..out_offset + 2].copy_from_slice(&left_s16.to_le_bytes());
                            uframe_buf[out_offset + 2..out_offset + 4].copy_from_slice(&right_s16.to_le_bytes());
                        }
                        2 => {
                            // 24-bit PCM (bSubslotSize = 3, 6 bytes/stereo frame)
                            let left = if ctx.source_bits <= 16 {
                                left_raw << 8
                            } else if ctx.source_bits == 24 {
                                left_raw
                            } else {
                                left_raw >> 8
                            };
                            let right = if ctx.source_bits <= 16 {
                                right_raw << 8
                            } else if ctx.source_bits == 24 {
                                right_raw
                            } else {
                                right_raw >> 8
                            };

                            let left_bytes = left.clamp(-8388608, 8388607).to_le_bytes();
                            let right_bytes = right.clamp(-8388608, 8388607).to_le_bytes();

                            uframe_buf[out_offset..out_offset + 3].copy_from_slice(&left_bytes[0..3]);
                            uframe_buf[out_offset + 3..out_offset + 6].copy_from_slice(&right_bytes[0..3]);
                        }
                        _ => {
                            // 32-bit slot / 24-in-32 (bSubslotSize = 4, 8 bytes/stereo frame)
                            let left = match ctx.source_bits {
                                16 => left_raw << 16,
                                24 => left_raw << 8,
                                _ => left_raw,
                            };
                            let right = match ctx.source_bits {
                                16 => right_raw << 16,
                                24 => right_raw << 8,
                                _ => right_raw,
                            };

                            uframe_buf[out_offset..out_offset + 4].copy_from_slice(&left.to_le_bytes());
                            uframe_buf[out_offset + 4..out_offset + 8].copy_from_slice(&right.to_le_bytes());
                        }
                    }
                } else {
                    // Buffer underrun: fill tail with silence
                    uframe_buf[out_offset..out_offset + bytes_per_frame].fill(0);
                    ctx.shared.underrun_samples.fetch_add(2, Ordering::Relaxed);
                }
            }

            let consumed_samples = got_frames * 2;
            ctx.shared.consumed_samples.fetch_add(consumed_samples as u64, Ordering::Relaxed);
        }

        ctx.shared.ring_fill_samples.store(ctx.consumer.len() as u64, Ordering::Relaxed);

        // Update exact transfer length
        (*transfer).length = buf_offset as libc::c_int;

        if ctx.shared.running.load(Ordering::Relaxed) {
            let res = libusb1_sys::libusb_submit_transfer(transfer);
            if res != 0 {
                log_error!("libusb_submit_transfer failed with code {}", res);
                ctx.shared.disconnected.store(true, Ordering::Release);
            }
        }
    }
}

#[cfg(target_os = "android")]
impl Uac2Output {
    pub fn open(
        fd: i32,
        consumer: PcmConsumer,
        sample_rate: u32,
        source_channels: u32,
        source_bits: u32,
        equalizer: Option<Arc<SharedEqualizerGains>>,
    ) -> Result<Self, String> {
        log_info!(
            "Uac2Output::open: fd={}, rate={} Hz, ch={}, bits={}",
            fd, sample_rate, source_channels, source_bits
        );

        let src_ch = source_channels.max(1) as usize;
        let realtime_equalizer = equalizer.map(|shared| {
            RealtimeEqualizer::new(shared, sample_rate.max(1), src_ch, source_bits)
        });

        // Match Alt-Setting on Interface 2 to source bit depth:
        // Alt 1: 16-bit (bSubslotSize = 2) -> 4 bytes/stereo frame
        // Alt 2: 24-bit (bSubslotSize = 3) -> 6 bytes/stereo frame
        // Alt 3: 32-bit (bSubslotSize = 4) -> 8 bytes/stereo frame
        let (alt_setting, bytes_per_sample) = if source_bits <= 16 {
            (1u32, 2usize)
        } else if source_bits == 24 {
            (2u32, 3usize)
        } else {
            (3u32, 4usize)
        };
        let bytes_per_frame = bytes_per_sample * 2;

        let shared = Arc::new(Uac2Shared::new());
        let thread_shared = Arc::clone(&shared);
        let nominal_q16 = (((sample_rate as u64) << 16) / 8000) as u32;
        shared.nominal_q16.store(nominal_q16, Ordering::Relaxed);

        let thread_context = Box::new(ThreadContext {
            consumer,
            source_channels: src_ch,
            source_bits,
            sample_rate,
            alt_setting,
            bytes_per_sample,
            bytes_per_frame,
            equalizer: realtime_equalizer,
            shared: Arc::clone(&shared),
            rate_accumulator: 0,
            nominal_q16,
            scratch: Vec::with_capacity(4096),
        });

        let thread_handle = thread::Builder::new()
            .name("mobius-uac2-audio".to_string())
            .spawn(move || {
                unsafe {
                    Self::run_uac2_stream_thread(fd, sample_rate, alt_setting, bytes_per_frame, thread_shared, thread_context);
                }
            })
            .map_err(|e| format!("Failed to spawn UAC2 audio thread: {e}"))?;

        Ok(Self {
            shared,
            sample_rate,
            channels: 2,
            thread_handle: Some(thread_handle),
        })
    }

    unsafe fn run_uac2_stream_thread(
        fd: i32,
        sample_rate: u32,
        alt_setting: u32,
        bytes_per_frame: usize,
        shared: Arc<Uac2Shared>,
        mut context: Box<ThreadContext>,
    ) {
        log_info!(
            "Starting UAC2 audio thread: fd={}, sample_rate={}, alt={}, bytes/frame={}",
            fd, sample_rate, alt_setting, bytes_per_frame
        );

        let dup_fd = libc::dup(fd);
        if dup_fd < 0 {
            log_error!("dup(fd {}) failed: errno {}", fd, std::io::Error::last_os_error());
            shared.disconnected.store(true, Ordering::Release);
            return;
        }

        let mut ctx: *mut libusb1_sys::libusb_context = ptr::null_mut();
        let _ = libusb1_sys::libusb_set_option(
            ptr::null_mut(),
            libusb1_sys::constants::LIBUSB_OPTION_NO_DEVICE_DISCOVERY,
        );

        if libusb1_sys::libusb_init(&mut ctx) != 0 || ctx.is_null() {
            log_error!("libusb_init failed");
            libc::close(dup_fd);
            shared.disconnected.store(true, Ordering::Release);
            return;
        }

        let mut devh: *mut libusb1_sys::libusb_device_handle = ptr::null_mut();
        if libusb1_sys::libusb_wrap_sys_device(ctx, dup_fd as isize as *mut i32, &mut devh) != 0 || devh.is_null() {
            log_error!("libusb_wrap_sys_device failed on dup_fd {}", dup_fd);
            libc::close(dup_fd);
            libusb1_sys::libusb_exit(ctx);
            shared.disconnected.store(true, Ordering::Release);
            return;
        }

        #[repr(C)]
        struct UsbdevfsSetinterface {
            interface: libc::c_uint,
            altsetting: libc::c_uint,
        }

        // Claim Audio Control (0) and Streaming (2) interfaces.
        // Android's UsbDeviceConnection already detached kernel drivers with USBDEVFS_DISCONNECT_CLAIM.
        let claim_0 = libusb1_sys::libusb_claim_interface(devh, 0);
        log_info!("libusb_claim_interface(0) -> res {}", claim_0);

        let claim_2 = libusb1_sys::libusb_claim_interface(devh, 2);
        log_info!("libusb_claim_interface(2) -> res {}", claim_2);

        // Configure Hardware Clock Source 6 and Feature Unit 7 (JA11 DAC) with safe initial volume
        let initial_vol = shared.target_hw_volume_db.load(Ordering::Acquire) as i16;
        let initial_mute = shared.target_mute.load(Ordering::Acquire);
        Self::configure_dac_hardware(devh, sample_rate, initial_vol, initial_mute);

        // Set Alternate Setting on Interface 2 directly via Linux USBDEVFS_SETINTERFACE ioctl
        let mut setintf = UsbdevfsSetinterface {
            interface: 2,
            altsetting: alt_setting,
        };
        let ioctl_res = libc::ioctl(dup_fd, 0x80085504u32 as libc::c_int, &mut setintf);
        log_info!("Direct ioctl USBDEVFS_SETINTERFACE(intf 2, alt {}) -> res {}", alt_setting, ioctl_res);

        // Also notify libusb of the Alternate Setting
        let alt_res = libusb1_sys::libusb_set_interface_alt_setting(devh, 2, alt_setting as libc::c_int);
        log_info!("libusb_set_interface_alt_setting(intf 2, alt {}) -> res {}", alt_setting, alt_res);

        // Raise this thread to Android's URGENT_AUDIO priority so the libusb
        // event loop is not starved by UI/GC work (which shows up as crackle).
        let tid = libc::gettid();
        let prio_res = libc::setpriority(libc::PRIO_PROCESS, tid as libc::id_t, -19);
        log_info!("setpriority(tid {}, -19) -> {}", tid, prio_res);

        // 16 microframes per transfer (2 ms). 32 transfers in flight = 64 ms of
        // queued audio at the host controller, enough to ride out scheduling
        // hiccups without a gap on the wire.
        const PACKETS_PER_TRANSFER: usize = 16;
        // Max frames per microframe for high-res (up to 384kHz: 48 frames * 8 bytes = 384 bytes, 512 for safety).
        const MAX_BYTES_PER_UFRAME: usize = 512;
        const BUFFER_SIZE: usize = PACKETS_PER_TRANSFER * MAX_BYTES_PER_UFRAME;
        const NUM_TRANSFERS: usize = 32;

        let mut out_transfers: Vec<*mut libusb1_sys::libusb_transfer> = Vec::new();
        let mut out_buffers: Vec<Vec<u8>> = Vec::new();
        let ctx_ptr = &mut *context as *mut ThreadContext as *mut c_void;
        let nominal_q16 = context.nominal_q16;

        for _ in 0..NUM_TRANSFERS {
            let transfer = libusb1_sys::libusb_alloc_transfer(PACKETS_PER_TRANSFER as i32);
            if transfer.is_null() {
                continue;
            }
            let mut buf = vec![0u8; BUFFER_SIZE];
            let buf_ptr = buf.as_mut_ptr();
            out_buffers.push(buf);

            (*transfer).dev_handle = devh;
            (*transfer).endpoint = 0x04; // Isochronous OUT endpoint
            (*transfer).transfer_type = libusb1_sys::constants::LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
            (*transfer).timeout = 1000;
            (*transfer).buffer = buf_ptr;
            (*transfer).num_iso_packets = PACKETS_PER_TRANSFER as i32;
            (*transfer).user_data = ctx_ptr;
            (*transfer).callback = uac2_out_transfer_cb;

            // Pre-roll with silence at the nominal rate.
            let descs = slice::from_raw_parts_mut((*transfer).iso_packet_desc.as_mut_ptr(), PACKETS_PER_TRANSFER);
            let mut transfer_len = 0usize;
            for desc in descs.iter_mut() {
                context.rate_accumulator += nominal_q16;
                let frames = (context.rate_accumulator >> 16) as usize;
                context.rate_accumulator &= 0xFFFF;
                let bytes = frames * bytes_per_frame;
                desc.length = bytes as u32;
                transfer_len += bytes;
            }
            (*transfer).length = transfer_len as i32;

            out_transfers.push(transfer);
        }

        // Feedback IN endpoint 0x85 (async DAC clock). bInterval 4 => one
        // 4-byte packet per 8 microframes; 2 transfers x 4 packets in flight.
        const FB_PACKETS: usize = 4;
        const FB_TRANSFERS: usize = 2;
        let mut fb_transfers: Vec<*mut libusb1_sys::libusb_transfer> = Vec::new();
        let mut fb_buffers: Vec<Vec<u8>> = Vec::new();
        let shared_ptr = Arc::as_ptr(&shared) as *mut c_void;
        for _ in 0..FB_TRANSFERS {
            let t = libusb1_sys::libusb_alloc_transfer(FB_PACKETS as i32);
            if t.is_null() {
                continue;
            }
            let mut buf = vec![0u8; FB_PACKETS * 4];
            (*t).dev_handle = devh;
            (*t).endpoint = 0x85;
            (*t).transfer_type = libusb1_sys::constants::LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
            (*t).timeout = 1000;
            (*t).buffer = buf.as_mut_ptr();
            (*t).length = (FB_PACKETS * 4) as i32;
            (*t).num_iso_packets = FB_PACKETS as i32;
            (*t).user_data = shared_ptr;
            (*t).callback = uac2_feedback_cb;
            let descs = slice::from_raw_parts_mut((*t).iso_packet_desc.as_mut_ptr(), FB_PACKETS);
            for d in descs.iter_mut() {
                d.length = 4;
            }
            fb_buffers.push(buf);
            fb_transfers.push(t);
        }

        // Submit initial transfers
        for transfer in &out_transfers {
            let res = libusb1_sys::libusb_submit_transfer(*transfer);
            if res != 0 {
                log_error!("Initial libusb_submit_transfer failed: res={}", res);
                shared.disconnected.store(true, Ordering::Release);
                break;
            }
        }
        for t in &fb_transfers {
            let res = libusb1_sys::libusb_submit_transfer(*t);
            log_info!("Feedback EP 0x85 submit -> {}", res);
        }

        let timeval = libc::timeval {
            tv_sec: 0,
            tv_usec: 2_000, // 2ms event poll
        };

        log_info!("UAC2 event loop entered, listening for transfers...");

        // Dedicated hardware volume & mute worker thread so the isochronous audio
        // streaming loop is NEVER blocked by synchronous USB control transfers to EP 0.
        let ctrl_shared = Arc::clone(&shared);
        let devh_addr = devh as usize;
        let ctrl_handle = thread::Builder::new()
            .name("mobius-uac2-ctrl".to_string())
            .spawn(move || {
                let devh = devh_addr as *mut libusb1_sys::libusb_device_handle;
                let mut applied_hw_volume = initial_vol;
                let mut applied_mute = initial_mute;

                while ctrl_shared.running.load(Ordering::Relaxed) && !ctrl_shared.disconnected.load(Ordering::Relaxed) {
                    let target_mute = ctrl_shared.target_mute.load(Ordering::Acquire);
                    if target_mute != applied_mute {
                        let mut mute_val = [if target_mute { 1u8 } else { 0u8 }];
                        let res = libusb1_sys::libusb_control_transfer(
                            devh,
                            0x21,
                            0x01,
                            0x0100, // FU_MUTE_CONTROL (0x01), master channel (0)
                            0x0700, // Feature Unit 7, Interface 0
                            mute_val.as_mut_ptr(),
                            1,
                            20,
                        );
                        applied_mute = target_mute;
                        log_info!("UAC2 applied HW mute: {} -> res {}", applied_mute, res);
                    }

                    let target_vol = ctrl_shared.target_hw_volume_db.load(Ordering::Acquire) as i16;
                    if target_vol != applied_hw_volume {
                        let mut vol_bytes = target_vol.to_le_bytes();
                        let res = libusb1_sys::libusb_control_transfer(
                            devh,
                            0x21,
                            0x01,
                            0x0200, // FU_VOLUME_CONTROL (0x02), master channel (0)
                            0x0700, // Feature Unit 7, Interface 0
                            vol_bytes.as_mut_ptr(),
                            2,
                            20,
                        );
                        let _ = libusb1_sys::libusb_control_transfer(devh, 0x21, 0x01, 0x0201, 0x0700, vol_bytes.as_mut_ptr(), 2, 10);
                        let _ = libusb1_sys::libusb_control_transfer(devh, 0x21, 0x01, 0x0202, 0x0700, vol_bytes.as_mut_ptr(), 2, 10);
                        applied_hw_volume = target_vol;
                        log_info!("UAC2 applied HW volume: {:.1} dB (units {}) -> res {}", target_vol as f32 / 256.0, target_vol, res);
                    }

                    thread::sleep(Duration::from_millis(15));
                }
            });

        while shared.running.load(Ordering::Relaxed) && !shared.disconnected.load(Ordering::Relaxed) {
            let mut completed: libc::c_int = 0;
            libusb1_sys::libusb_handle_events_timeout_completed(ctx, &timeval, &mut completed);
        }

        if let Ok(handle) = ctrl_handle {
            let _ = handle.join();
        }

        log_info!("UAC2 event loop exiting, cleaning up transfers...");

        // Cleanup
        for transfer in out_transfers.iter().chain(fb_transfers.iter()) {
            let _ = libusb1_sys::libusb_cancel_transfer(*transfer);
        }

        let cleanup_start = std::time::Instant::now();
        while cleanup_start.elapsed() < Duration::from_millis(40) {
            let mut completed: libc::c_int = 0;
            libusb1_sys::libusb_handle_events_timeout_completed(ctx, &timeval, &mut completed);
        }

        for transfer in out_transfers.into_iter().chain(fb_transfers.into_iter()) {
            libusb1_sys::libusb_free_transfer(transfer);
        }
        drop(out_buffers);
        drop(fb_buffers);

        // Note: Do NOT call libusb_release_interface(devh, 2) or libusb_release_interface(devh, 0).
        // In Linux usbfs, release_interface resets the interface to Alt 0, which would break
        // continuous playback across tracks and require re-claiming.
        // Android's UsbDeviceConnection manages the device lifecycle and releases claims on detach.

        // Close devh (closes dup_fd; parent Java UsbDeviceConnection fd stays untouched!)
        libusb1_sys::libusb_close(devh);
        libusb1_sys::libusb_exit(ctx);
        log_info!("UAC2 audio thread finished cleanly.");
    }

    unsafe fn configure_dac_hardware(
        devh: *mut libusb1_sys::libusb_device_handle,
        sample_rate: u32,
        initial_vol: i16,
        initial_mute: bool,
    ) {
        // UAC2 Clock Source 6: CS_SAM_FREQ_CONTROL (0x01)
        // bmRequestType: 0x21 (Host to Device | Class | Interface)
        // bRequest: 0x01 (CUR)
        // wValue: (0x01 << 8) | 0x00
        // wIndex: (0x06 << 8) | 0x00 (Clock ID 6, Interface 0)
        let mut rate_bytes = sample_rate.to_le_bytes();
        let set_rate = libusb1_sys::libusb_control_transfer(
            devh,
            0x21,
            0x01,
            0x0100,
            0x0600,
            rate_bytes.as_mut_ptr(),
            4,
            1000,
        );
        log_info!("UAC2 Clock Source 6 set rate {} Hz -> res {}", sample_rate, set_rate);

        // Read back Clock Source 6 frequency
        let mut cur_rate_buf = [0u8; 4];
        let get_rate = libusb1_sys::libusb_control_transfer(
            devh,
            0xA1,
            0x01,
            0x0100,
            0x0600,
            cur_rate_buf.as_mut_ptr(),
            4,
            1000,
        );
        log_info!(
            "UAC2 Clock Source 6 read rate -> res {}, current_hz={}",
            get_rate,
            u32::from_le_bytes(cur_rate_buf)
        );

        // Query Feature Unit 7 Mute GET_CUR
        let mut mute_val = [0u8; 1];
        let get_mute = libusb1_sys::libusb_control_transfer(
            devh,
            0xA1,
            0x01,
            0x0100,
            0x0700,
            mute_val.as_mut_ptr(),
            1,
            1000,
        );
        log_info!("UAC2 Feature Unit 7 GET_CUR mute -> res {}, val={}", get_mute, mute_val[0]);

        // UAC2 Feature Unit 7: FU_MUTE_CONTROL (0x01), Master channel (0)
        let mut mute_buf = [if initial_mute { 1u8 } else { 0u8 }];
        let mute_res = libusb1_sys::libusb_control_transfer(
            devh,
            0x21,
            0x01,
            0x0100,
            0x0700,
            mute_buf.as_mut_ptr(),
            1,
            1000,
        );
        log_info!("UAC2 Feature Unit 7 set mute ({}, master) -> res {}", initial_mute, mute_res);

        // Also set mute on channels 1 & 2 explicitly
        let _ = libusb1_sys::libusb_control_transfer(devh, 0x21, 0x01, 0x0101, 0x0700, mute_buf.as_mut_ptr(), 1, 500);
        let _ = libusb1_sys::libusb_control_transfer(devh, 0x21, 0x01, 0x0102, 0x0700, mute_buf.as_mut_ptr(), 1, 500);

        // Query Feature Unit 7 Volume GET_RANGE
        let mut vol_range = [0u8; 32];
        let get_vol_range = libusb1_sys::libusb_control_transfer(
            devh,
            0xA1,
            0x02,
            0x0200,
            0x0700,
            vol_range.as_mut_ptr(),
            vol_range.len() as u16,
            1000,
        );
        log_info!(
            "UAC2 Feature Unit 7 GET_RANGE volume -> res {}, data={:02X?}",
            get_vol_range,
            if get_vol_range > 0 { &vol_range[..get_vol_range as usize] } else { &[] }
        );

        // Query Feature Unit 7 Volume GET_CUR
        let mut cur_vol = [0u8; 2];
        let get_cur_vol = libusb1_sys::libusb_control_transfer(
            devh,
            0xA1,
            0x01,
            0x0200,
            0x0700,
            cur_vol.as_mut_ptr(),
            2,
            1000,
        );
        log_info!(
            "UAC2 Feature Unit 7 GET_CUR volume -> res {}, val={} dB_units",
            get_cur_vol,
            i16::from_le_bytes(cur_vol)
        );

        // UAC2 Feature Unit 7: FU_VOLUME_CONTROL (0x02), Master channel (0)
        // Program the initial hardware volume BEFORE any audio stream transfer starts.
        let mut vol_bytes = initial_vol.to_le_bytes();
        let vol_res = libusb1_sys::libusb_control_transfer(
            devh,
            0x21,
            0x01,
            0x0200,
            0x0700,
            vol_bytes.as_mut_ptr(),
            2,
            1000,
        );
        log_info!(
            "UAC2 Feature Unit 7 set initial volume ({:.1} dB, units {}) -> res {}",
            initial_vol as f32 / 256.0,
            initial_vol,
            vol_res
        );

        // Also set volume channels 1 & 2 explicitly
        let _ = libusb1_sys::libusb_control_transfer(devh, 0x21, 0x01, 0x0201, 0x0700, vol_bytes.as_mut_ptr(), 2, 500);
        let _ = libusb1_sys::libusb_control_transfer(devh, 0x21, 0x01, 0x0202, 0x0700, vol_bytes.as_mut_ptr(), 2, 500);
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    pub fn channels(&self) -> u32 {
        self.channels
    }

    pub fn is_disconnected(&self) -> bool {
        self.shared.disconnected.load(Ordering::Acquire)
    }

    pub fn queued_source_samples(&self) -> u64 {
        self.shared.ring_fill_samples.load(Ordering::Relaxed)
    }

    pub fn start(&self) -> Result<(), String> {
        log_info!("Uac2Output::start requested");
        self.shared.playing.store(true, Ordering::Release);
        Ok(())
    }

    pub fn pause(&self) -> Result<(), String> {
        log_info!("Uac2Output::pause requested");
        self.shared.playing.store(false, Ordering::Release);
        Ok(())
    }

    pub fn stop(&self) -> Result<(), String> {
        log_info!("Uac2Output::stop requested");
        self.shared.playing.store(false, Ordering::Release);
        Ok(())
    }

    pub fn set_software_volume(&self, volume: f32) -> Result<(), String> {
        let v = volume.clamp(0.0, 1.0);
        if self.is_bit_perfect_mode() {
            self.shared.software_volume.store(1.0f32.to_bits(), Ordering::Release);
            log_info!("Uac2Output::set_software_volume: bit-perfect active, software volume locked at 1.0");
        } else {
            self.shared.software_volume.store(v.to_bits(), Ordering::Relaxed);
            log_info!("Uac2Output::set_software_volume: {:.2}", v);
        }
        Ok(())
    }

    pub fn set_hardware_volume(&self, volume: f32) -> Result<(), String> {
        let v = volume.clamp(0.0, 1.0);
        self.shared.hardware_volume.store(v.to_bits(), Ordering::Relaxed);
        let (units, mute) = volume_to_hw_db(v);
        self.shared.target_hw_volume_db.store(units as i32, Ordering::Release);
        self.shared.target_mute.store(mute, Ordering::Release);
        log_info!("Uac2Output::set_hardware_volume: input={:.2}, hw_db={:.1}, mute={}", v, units as f32 / 256.0, mute);
        Ok(())
    }

    pub fn set_bit_perfect_mode(&self, enabled: bool) -> Result<(), String> {
        self.shared.bit_perfect_mode.store(enabled, Ordering::Release);
        if enabled {
            // In bit-perfect mode, software volume is locked at 1.0 (unity gain)
            self.shared.software_volume.store(1.0f32.to_bits(), Ordering::Release);
            // Re-apply target hardware volume to ensure DAC HW register strictly matches hardware volume
            let hw_vol = f32::from_bits(self.shared.hardware_volume.load(Ordering::Relaxed));
            let (units, mute) = volume_to_hw_db(hw_vol);
            self.shared.target_hw_volume_db.store(units as i32, Ordering::Release);
            self.shared.target_mute.store(mute, Ordering::Release);
        }
        log_info!("Uac2Output::set_bit_perfect_mode: {}", enabled);
        Ok(())
    }

    pub fn is_bit_perfect_mode(&self) -> bool {
        self.shared.bit_perfect_mode.load(Ordering::Acquire)
    }

    pub fn software_volume(&self) -> f32 {
        f32::from_bits(self.shared.software_volume.load(Ordering::Relaxed))
    }

    pub fn hardware_volume(&self) -> f32 {
        f32::from_bits(self.shared.hardware_volume.load(Ordering::Relaxed))
    }

    pub fn set_volume(&self, volume: f32) -> Result<(), String> {
        let v = volume.clamp(0.0, 1.0);
        self.shared.volume.store(v.to_bits(), Ordering::Relaxed);
        self.set_software_volume(v)
    }

    pub fn telemetry(&self) -> PlaybackTelemetry {
        PlaybackTelemetry {
            callback_count: self.shared.callback_count.load(Ordering::Relaxed),
            requested_samples: self.shared.requested_samples.load(Ordering::Relaxed),
            consumed_samples: self.shared.consumed_samples.load(Ordering::Relaxed),
            underrun_samples: self.shared.underrun_samples.load(Ordering::Relaxed),
        }
    }
}

#[cfg(target_os = "android")]
impl Drop for Uac2Output {
    fn drop(&mut self) {
        log_info!("Uac2Output::drop called, signalling thread stop");
        self.shared.running.store(false, Ordering::Release);
        if let Some(handle) = self.thread_handle.take() {
            let _ = handle.join();
        }
    }
}
