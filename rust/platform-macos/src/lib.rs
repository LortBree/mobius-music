#![cfg(target_os = "macos")]

use std::{
    f32::consts::TAU,
    ffi::c_void,
    ptr::NonNull,
    slice,
    sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering},
};

use objc2_core_audio::{
    kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyStreams,
    kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices,
    kAudioObjectPropertyElementMain, kAudioObjectPropertyScopeGlobal,
    kAudioObjectPropertyScopeOutput, kAudioStreamPropertyAvailableVirtualFormats,
    kAudioStreamPropertyPhysicalFormat, kAudioStreamPropertyVirtualFormat,
    AudioDeviceCreateIOProcID, AudioDeviceDestroyIOProcID, AudioDeviceIOProc, AudioDeviceStart,
    AudioDeviceStop, AudioObjectGetPropertyData, AudioObjectGetPropertyDataSize, AudioObjectID,
    AudioObjectIsPropertySettable, AudioObjectPropertyAddress, AudioObjectSetPropertyData,
    AudioStreamRangedDescription,
};

use objc2_core_audio_types::{AudioBufferList, AudioStreamBasicDescription, AudioTimeStamp};

use offline_player_audio_core::PcmConsumer;

#[derive(Debug)]
pub enum MacAudioError {
    CoreAudio(i32),
    PropertyNotSettable,
    MissingIOProcID,
    NoOutputDevice,
    NoOutputStream,
    InvalidOutputFormat,
    SourceFormatMismatch {
        source_sample_rate: u32,
        source_channels: u32,
        source_bits: u32,
        output_sample_rate: u32,
        output_channels: u32,
        output_bits: u32,
    },
}

impl std::fmt::Display for MacAudioError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::CoreAudio(status) => {
                write!(f, "CoreAudio OSStatus: {status}")
            }

            Self::PropertyNotSettable => {
                write!(f, "CoreAudio nominal sample-rate property is not settable")
            }

            Self::MissingIOProcID => {
                write!(f, "CoreAudio did not return an IOProc ID")
            }

            Self::NoOutputDevice => {
                write!(f, "No CoreAudio playback device found")
            }

            Self::NoOutputStream => {
                write!(f, "CoreAudio device has no output stream")
            }

            Self::InvalidOutputFormat => {
                write!(f, "CoreAudio output stream is unsupported")
            }

            Self::SourceFormatMismatch {
                source_sample_rate,
                source_channels,
                source_bits,
                output_sample_rate,
                output_channels,
                output_bits,
            } => {
                write!(
                    f,
                    "source/output format mismatch: \
                     source={} Hz / {} ch / {} bit, \
                     output={} Hz / {} ch / {} bit",
                    source_sample_rate,
                    source_channels,
                    source_bits,
                    output_sample_rate,
                    output_channels,
                    output_bits,
                )
            }
        }
    }
}

impl std::error::Error for MacAudioError {}

fn check_status(status: i32) -> Result<(), MacAudioError> {
    if status == 0 {
        Ok(())
    } else {
        Err(MacAudioError::CoreAudio(status))
    }
}

fn property_address(selector: u32, scope: u32, element: u32) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress {
        mSelector: selector,
        mScope: scope,
        mElement: element,
    }
}

fn read_object_id_array(
    object_id: AudioObjectID,
    address: &mut AudioObjectPropertyAddress,
) -> Result<Vec<AudioObjectID>, MacAudioError> {
    let mut data_size = 0u32;

    let status = unsafe {
        AudioObjectGetPropertyDataSize(
            object_id,
            NonNull::from(&mut *address),
            0,
            std::ptr::null(),
            NonNull::from(&mut data_size),
        )
    };

    check_status(status)?;

    if data_size == 0 {
        return Ok(Vec::new());
    }

    let item_size = std::mem::size_of::<AudioObjectID>();

    if data_size as usize % item_size != 0 {
        return Err(MacAudioError::CoreAudio(-1));
    }

    let item_count = data_size as usize / item_size;

    let mut values = vec![0 as AudioObjectID; item_count];

    let mut actual_size = data_size;

    let out_data = NonNull::new(values.as_mut_ptr().cast::<c_void>())
        .expect("non-empty vector must have non-null pointer");

    let status = unsafe {
        AudioObjectGetPropertyData(
            object_id,
            NonNull::from(&mut *address),
            0,
            std::ptr::null(),
            NonNull::from(&mut actual_size),
            out_data,
        )
    };

    check_status(status)?;

    let actual_count = (actual_size as usize).min(values.len() * item_size) / item_size;

    values.truncate(actual_count);

    Ok(values)
}

pub fn list_devices() -> Result<Vec<AudioObjectID>, MacAudioError> {
    let system_object_id: AudioObjectID = 1;

    let mut address = property_address(
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    read_object_id_array(system_object_id, &mut address)
}

pub fn list_output_devices() -> Result<Vec<AudioObjectID>, MacAudioError> {
    let devices = list_devices()?;

    let mut output_devices = Vec::new();

    for device_id in devices {
        let mut address = property_address(
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyElementMain,
        );

        let streams = read_object_id_array(device_id, &mut address)?;

        if !streams.is_empty() {
            output_devices.push(device_id);
        }
    }

    Ok(output_devices)
}

/// Return macOS's actual default output device.
pub fn default_output_device() -> Result<AudioObjectID, MacAudioError> {
    let system_object_id: AudioObjectID = 1;

    let mut address = property_address(
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    let mut device_id: AudioObjectID = 0;

    let mut data_size = std::mem::size_of::<AudioObjectID>() as u32;

    let device_ptr = NonNull::new((&mut device_id as *mut AudioObjectID).cast::<c_void>())
        .expect("device pointer cannot be null");

    let status = unsafe {
        AudioObjectGetPropertyData(
            system_object_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            NonNull::from(&mut data_size),
            device_ptr,
        )
    };

    check_status(status)?;

    if device_id == 0 {
        return Err(MacAudioError::NoOutputDevice);
    }

    Ok(device_id)
}

fn output_stream_for_device(device_id: AudioObjectID) -> Result<AudioObjectID, MacAudioError> {
    let mut address = property_address(
        kAudioDevicePropertyStreams,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain,
    );

    read_object_id_array(device_id, &mut address)?
        .into_iter()
        .next()
        .ok_or(MacAudioError::NoOutputStream)
}

fn read_stream_physical_format(
    stream_id: AudioObjectID,
) -> Result<AudioStreamBasicDescription, MacAudioError> {
    let mut address = property_address(
        kAudioStreamPropertyPhysicalFormat,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    let mut format = AudioStreamBasicDescription {
        mSampleRate: 0.0,
        mFormatID: 0,
        mFormatFlags: 0,
        mBytesPerPacket: 0,
        mFramesPerPacket: 0,
        mBytesPerFrame: 0,
        mChannelsPerFrame: 0,
        mBitsPerChannel: 0,
        mReserved: 0,
    };

    let mut data_size = std::mem::size_of::<AudioStreamBasicDescription>() as u32;

    let format_ptr =
        NonNull::new((&mut format as *mut AudioStreamBasicDescription).cast::<c_void>())
            .expect("format pointer cannot be null");

    let status = unsafe {
        AudioObjectGetPropertyData(
            stream_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            NonNull::from(&mut data_size),
            format_ptr,
        )
    };

    check_status(status)?;

    Ok(format)
}

fn read_stream_virtual_format(
    stream_id: AudioObjectID,
) -> Result<AudioStreamBasicDescription, MacAudioError> {
    let mut address = property_address(
        kAudioStreamPropertyVirtualFormat,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    let mut format = AudioStreamBasicDescription {
        mSampleRate: 0.0,
        mFormatID: 0,
        mFormatFlags: 0,
        mBytesPerPacket: 0,
        mFramesPerPacket: 0,
        mBytesPerFrame: 0,
        mChannelsPerFrame: 0,
        mBitsPerChannel: 0,
        mReserved: 0,
    };

    let mut data_size = std::mem::size_of::<AudioStreamBasicDescription>() as u32;

    let format_ptr =
        NonNull::new((&mut format as *mut AudioStreamBasicDescription).cast::<c_void>())
            .expect("format pointer cannot be null");

    let status = unsafe {
        AudioObjectGetPropertyData(
            stream_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            NonNull::from(&mut data_size),
            format_ptr,
        )
    };

    check_status(status)?;

    Ok(format)
}

#[derive(Debug, Clone, Copy)]
pub struct OutputFormat {
    pub sample_rate: u32,
    pub channels: u32,
    pub bits_per_channel: u32,
    pub bytes_per_frame: u32,
    pub format_id: u32,
    pub format_flags: u32,
}

impl OutputFormat {
    fn from_asbd(asbd: AudioStreamBasicDescription) -> Result<Self, MacAudioError> {
        if asbd.mSampleRate <= 0.0
            || asbd.mChannelsPerFrame == 0
            || asbd.mBitsPerChannel == 0
            || asbd.mBytesPerFrame == 0
        {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        Ok(Self {
            sample_rate: asbd.mSampleRate as u32,
            channels: asbd.mChannelsPerFrame,
            bits_per_channel: asbd.mBitsPerChannel,
            bytes_per_frame: asbd.mBytesPerFrame,
            format_id: asbd.mFormatID,
            format_flags: asbd.mFormatFlags,
        })
    }
}

pub fn output_format(device_id: AudioObjectID) -> Result<OutputFormat, MacAudioError> {
    let stream_id = output_stream_for_device(device_id)?;

    let asbd = read_stream_physical_format(stream_id)?;

    OutputFormat::from_asbd(asbd)
}

pub fn output_virtual_format(device_id: AudioObjectID) -> Result<OutputFormat, MacAudioError> {
    let stream_id = output_stream_for_device(device_id)?;

    let asbd = read_stream_virtual_format(stream_id)?;

    OutputFormat::from_asbd(asbd)
}

/// Read all virtual formats advertised by the output stream.
///
/// Discovery only. This function does not change
/// the current device format.
pub fn available_virtual_formats(
    device_id: AudioObjectID,
) -> Result<Vec<AudioStreamRangedDescription>, MacAudioError> {
    let stream_id = output_stream_for_device(device_id)?;

    let mut address = property_address(
        kAudioStreamPropertyAvailableVirtualFormats,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    let mut data_size = 0u32;

    let status = unsafe {
        AudioObjectGetPropertyDataSize(
            stream_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            NonNull::from(&mut data_size),
        )
    };

    check_status(status)?;

    if data_size == 0 {
        return Ok(Vec::new());
    }

    let item_size = std::mem::size_of::<AudioStreamRangedDescription>();

    if data_size as usize % item_size != 0 {
        return Err(MacAudioError::CoreAudio(-1));
    }

    let item_count = data_size as usize / item_size;

    let mut formats = Vec::<AudioStreamRangedDescription>::with_capacity(item_count);

    unsafe {
        formats.set_len(item_count);
    }

    let mut actual_size = data_size;

    let out_data = NonNull::new(formats.as_mut_ptr().cast::<c_void>())
        .expect("non-empty vector must have non-null pointer");

    let status = unsafe {
        AudioObjectGetPropertyData(
            stream_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            NonNull::from(&mut actual_size),
            out_data,
        )
    };

    check_status(status)?;

    let actual_count = (actual_size as usize) / item_size;

    formats.truncate(actual_count);

    Ok(formats)
}

/// Return the unique sample rates exposed by
/// the output stream's virtual formats.
///
/// This is a non-realtime capability query.
pub fn supported_virtual_sample_rates(device_id: AudioObjectID) -> Result<Vec<u32>, MacAudioError> {
    let formats = available_virtual_formats(device_id)?;

    let mut rates = Vec::with_capacity(formats.len());

    for ranged in formats {
        let rate = ranged.mFormat.mSampleRate;

        if rate <= 0.0 {
            continue;
        }

        let rate = rate.round() as u32;

        if !rates.contains(&rate) {
            rates.push(rate);
        }
    }

    rates.sort_unstable();

    Ok(rates)
}

pub fn dump_available_virtual_formats(device_id: AudioObjectID) -> Result<(), MacAudioError> {
    let formats = available_virtual_formats(device_id)?;

    println!("=== AVAILABLE VIRTUAL FORMATS ===");

    if formats.is_empty() {
        println!("No virtual formats reported.");
        return Ok(());
    }

    for (index, ranged) in formats.iter().enumerate() {
        let format = ranged.mFormat;

        let min_rate = ranged.mSampleRateRange.mMinimum;

        let max_rate = ranged.mSampleRateRange.mMaximum;

        println!("Format #{index}");

        println!("  Sample rate     : {:.0} Hz", format.mSampleRate);

        if (min_rate - max_rate).abs() < f64::EPSILON {
            println!("  Rate range      : {:.0} Hz", min_rate);
        } else {
            println!("  Rate range      : {:.0} - {:.0} Hz", min_rate, max_rate);
        }

        println!("  Channels/frame  : {}", format.mChannelsPerFrame);

        println!("  Bits/channel    : {}", format.mBitsPerChannel);

        println!("  Bytes/frame     : {}", format.mBytesPerFrame);

        println!("  Format ID       : 0x{:08X}", format.mFormatID);

        println!("  Format flags    : 0x{:08X}", format.mFormatFlags);

        println!();
    }

    Ok(())
}

pub fn nominal_sample_rate(device_id: AudioObjectID) -> Result<f64, MacAudioError> {
    let mut address = property_address(
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    let mut value = 0.0f64;

    let mut data_size = std::mem::size_of::<f64>() as u32;

    let value_ptr = NonNull::new((&mut value as *mut f64).cast::<c_void>())
        .expect("sample-rate pointer cannot be null");

    let status = unsafe {
        AudioObjectGetPropertyData(
            device_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            NonNull::from(&mut data_size),
            value_ptr,
        )
    };

    check_status(status)?;

    Ok(value)
}

pub fn set_nominal_sample_rate(
    device_id: AudioObjectID,
    sample_rate: f64,
) -> Result<(), MacAudioError> {
    let mut address = property_address(
        kAudioDevicePropertyNominalSampleRate,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    );

    let mut settable = 0u8;

    let status = unsafe {
        AudioObjectIsPropertySettable(
            device_id,
            NonNull::from(&mut address),
            NonNull::from(&mut settable),
        )
    };

    check_status(status)?;

    if settable == 0 {
        return Err(MacAudioError::PropertyNotSettable);
    }

    let mut requested_rate = sample_rate;

    let value_ptr = NonNull::new((&mut requested_rate as *mut f64).cast::<c_void>())
        .expect("sample-rate pointer cannot be null");

    let status = unsafe {
        AudioObjectSetPropertyData(
            device_id,
            NonNull::from(&mut address),
            0,
            std::ptr::null(),
            std::mem::size_of::<f64>() as u32,
            value_ptr,
        )
    };

    check_status(status)
}

struct PlaybackState {
    consumer: PcmConsumer,
    source_bits: u32,
    volume: AtomicU32,

    callback_count: AtomicU64,

    requested_samples: AtomicU64,

    consumed_samples: AtomicU64,

    underrun_samples: AtomicU64,

    first_buffer_captured: AtomicBool,

    first_buffer_count: AtomicU32,

    first_buffer_channels: AtomicU32,

    first_buffer_bytes: AtomicU32,

    first_buffer_alignment: AtomicU32,

    first_bytes: [AtomicU32; 16],
}

#[derive(Debug, Clone, Copy)]
pub struct PlaybackTelemetry {
    pub callback_count: u64,
    pub requested_samples: u64,
    pub consumed_samples: u64,
    pub underrun_samples: u64,

    pub first_buffer_count: u32,
    pub first_buffer_channels: u32,
    pub first_buffer_bytes: u32,
    pub first_buffer_alignment: u32,

    pub first_bytes: [u8; 16],
}

unsafe extern "C-unwind" fn pcm_io_proc(
    _device: AudioObjectID,
    _now: NonNull<AudioTimeStamp>,
    _input_data: NonNull<AudioBufferList>,
    _input_time: NonNull<AudioTimeStamp>,
    output_data: NonNull<AudioBufferList>,
    _output_time: NonNull<AudioTimeStamp>,
    client_data: *mut c_void,
) -> i32 {
    if client_data.is_null() {
        return -1;
    }

    let state = unsafe { &mut *(client_data as *mut PlaybackState) };

    state.callback_count.fetch_add(1, Ordering::Relaxed);

    let list = unsafe { output_data.as_ref() };

    let buffer_count = list.mNumberBuffers as usize;

    if buffer_count != 1 {
        for index in 0..buffer_count {
            let buffer_ptr = unsafe { list.mBuffers.as_ptr().add(index) };

            let buffer = unsafe { &*buffer_ptr };

            if buffer.mData.is_null() {
                continue;
            }

            let bytes = unsafe {
                slice::from_raw_parts_mut(buffer.mData.cast::<u8>(), buffer.mDataByteSize as usize)
            };

            bytes.fill(0);
        }

        return 0;
    }

    let buffer = unsafe { &*list.mBuffers.as_ptr() };

    if buffer.mData.is_null() {
        return 0;
    }

    let byte_count = buffer.mDataByteSize as usize;

    let sample_size = std::mem::size_of::<f32>();

    if byte_count % sample_size != 0 {
        let bytes = unsafe { slice::from_raw_parts_mut(buffer.mData.cast::<u8>(), byte_count) };

        bytes.fill(0);

        return 0;
    }

    let sample_count = byte_count / sample_size;

    state
        .requested_samples
        .fetch_add(sample_count as u64, Ordering::Relaxed);

    let output = unsafe { slice::from_raw_parts_mut(buffer.mData.cast::<f32>(), sample_count) };

    let divisor = if state.source_bits == 32 {
        2_147_483_648.0f32
    } else {
        (1u64 << (state.source_bits - 1)) as f32
    };

    let mut consumed = 0usize;

    while consumed < output.len() {
        let sample = match state.consumer.try_pop() {
            Ok(sample) => sample,
            Err(_) => break,
        };

        let volume = f32::from_bits(state.volume.load(Ordering::Relaxed));
        output[consumed] = (sample as f32 / divisor) * volume;

        consumed += 1;
    }

    state
        .consumed_samples
        .fetch_add(consumed as u64, Ordering::Relaxed);

    if consumed < output.len() {
        let missing = output.len() - consumed;

        state
            .underrun_samples
            .fetch_add(missing as u64, Ordering::Relaxed);

        output[consumed..].fill(0.0);
    }

    if state
        .first_buffer_captured
        .compare_exchange(false, true, Ordering::Relaxed, Ordering::Relaxed)
        .is_ok()
    {
        state
            .first_buffer_count
            .store(list.mNumberBuffers, Ordering::Relaxed);

        state
            .first_buffer_channels
            .store(buffer.mNumberChannels, Ordering::Relaxed);

        state
            .first_buffer_bytes
            .store(byte_count as u32, Ordering::Relaxed);

        state
            .first_buffer_alignment
            .store((buffer.mData as usize & 0x0f) as u32, Ordering::Relaxed);

        let dump_len = byte_count.min(16);

        let bytes = unsafe { slice::from_raw_parts(buffer.mData.cast::<u8>(), dump_len) };

        for (index, byte) in bytes.iter().enumerate() {
            state.first_bytes[index].store(*byte as u32, Ordering::Relaxed);
        }
    }

    0
}

pub struct PcmOutput {
    device_id: AudioObjectID,
    io_proc_id: AudioDeviceIOProc,

    #[allow(dead_code)]
    state: Box<PlaybackState>,
}

impl PcmOutput {
    pub fn open(
        device_id: AudioObjectID,
        consumer: PcmConsumer,
        source_sample_rate: u32,
        source_channels: u32,
        source_bits: u32,
    ) -> Result<Self, MacAudioError> {
        let format = output_virtual_format(device_id)?;

        //
        // Native mode:
        // no implicit sample-rate conversion.
        //
        if source_sample_rate != format.sample_rate || source_channels != format.channels {
            return Err(MacAudioError::SourceFormatMismatch {
                source_sample_rate,
                source_channels,
                source_bits,
                output_sample_rate: format.sample_rate,
                output_channels: format.channels,
                output_bits: format.bits_per_channel,
            });
        }

        //
        // Linear PCM: 'lpcm'
        //
        const LINEAR_PCM: u32 = 0x6C70636D;

        if format.format_id != LINEAR_PCM {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        //
        // 32-bit packed:
        // channels × 4 bytes/frame.
        //
        let expected_bytes_per_frame = format.channels * 4;

        if format.bytes_per_frame != expected_bytes_per_frame {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        //
        // kAudioFormatFlagIsFloat
        //
        const FLOAT: u32 = 0x0001;

        //
        // kAudioFormatFlagIsPacked
        //
        const PACKED: u32 = 0x0008;

        //
        // kAudioFormatFlagIsNonInterleaved
        //
        const NON_INTERLEAVED: u32 = 0x0020;

        if format.format_flags & FLOAT == 0 || format.format_flags & PACKED == 0 {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        if format.format_flags & NON_INTERLEAVED != 0 {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        if format.bits_per_channel != 32 {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        let state = Box::new(PlaybackState {
            consumer,
            source_bits,
            volume: AtomicU32::new(1.0f32.to_bits()),

            callback_count: AtomicU64::new(0),

            requested_samples: AtomicU64::new(0),

            consumed_samples: AtomicU64::new(0),

            underrun_samples: AtomicU64::new(0),

            first_buffer_captured: AtomicBool::new(false),

            first_buffer_count: AtomicU32::new(0),

            first_buffer_channels: AtomicU32::new(0),

            first_buffer_bytes: AtomicU32::new(0),

            first_buffer_alignment: AtomicU32::new(0),

            first_bytes: std::array::from_fn(|_| AtomicU32::new(0)),
        });

        let client_data = (&*state as *const PlaybackState)
            .cast_mut()
            .cast::<c_void>();

        let io_proc: AudioDeviceIOProc = Some(pcm_io_proc);

        let mut created_io_proc_id: AudioDeviceIOProc = None;

        let out_io_proc_id = NonNull::from(&mut created_io_proc_id);

        let status =
            unsafe { AudioDeviceCreateIOProcID(device_id, io_proc, client_data, out_io_proc_id) };

        check_status(status)?;

        let io_proc_id = created_io_proc_id.ok_or(MacAudioError::MissingIOProcID)?;

        Ok(Self {
            device_id,
            io_proc_id: Some(io_proc_id),
            state,
        })
    }

    pub fn start(&self) -> Result<(), MacAudioError> {
        let status = unsafe { AudioDeviceStart(self.device_id, self.io_proc_id) };

        check_status(status)
    }

    pub fn stop(&self) -> Result<(), MacAudioError> {
        let status = unsafe { AudioDeviceStop(self.device_id, self.io_proc_id) };

        check_status(status)
    }

    pub fn set_volume(&self, volume: f32) {
        self.state.volume.store(volume.to_bits(), Ordering::Relaxed);
    }

    pub fn telemetry(&self) -> PlaybackTelemetry {
        let mut first_bytes = [0u8; 16];

        for (index, byte) in first_bytes.iter_mut().enumerate() {
            *byte = self.state.first_bytes[index].load(Ordering::Relaxed) as u8;
        }

        PlaybackTelemetry {
            callback_count: self.state.callback_count.load(Ordering::Relaxed),

            requested_samples: self.state.requested_samples.load(Ordering::Relaxed),

            consumed_samples: self.state.consumed_samples.load(Ordering::Relaxed),

            underrun_samples: self.state.underrun_samples.load(Ordering::Relaxed),

            first_buffer_count: self.state.first_buffer_count.load(Ordering::Relaxed),

            first_buffer_channels: self.state.first_buffer_channels.load(Ordering::Relaxed),

            first_buffer_bytes: self.state.first_buffer_bytes.load(Ordering::Relaxed),

            first_buffer_alignment: self.state.first_buffer_alignment.load(Ordering::Relaxed),

            first_bytes,
        }
    }

    pub fn device_id(&self) -> AudioObjectID {
        self.device_id
    }
}

impl Drop for PcmOutput {
    fn drop(&mut self) {
        let _ = unsafe { AudioDeviceStop(self.device_id, self.io_proc_id) };

        let _ = unsafe { AudioDeviceDestroyIOProcID(self.device_id, self.io_proc_id) };
    }
}

unsafe extern "C-unwind" fn silence_io_proc(
    _device: AudioObjectID,
    _now: NonNull<AudioTimeStamp>,
    _input_data: NonNull<AudioBufferList>,
    _input_time: NonNull<AudioTimeStamp>,
    output_data: NonNull<AudioBufferList>,
    _output_time: NonNull<AudioTimeStamp>,
    _client_data: *mut c_void,
) -> i32 {
    let list = unsafe { output_data.as_ref() };

    let buffer_count = list.mNumberBuffers as usize;

    for index in 0..buffer_count {
        let buffer_ptr = unsafe { list.mBuffers.as_ptr().add(index) };

        let buffer = unsafe { &*buffer_ptr };

        if buffer.mData.is_null() {
            continue;
        }

        let bytes = unsafe {
            slice::from_raw_parts_mut(buffer.mData.cast::<u8>(), buffer.mDataByteSize as usize)
        };

        bytes.fill(0);
    }

    0
}

pub struct SilenceOutput {
    device_id: AudioObjectID,
    io_proc_id: AudioDeviceIOProc,
}

impl SilenceOutput {
    pub fn open(device_id: AudioObjectID) -> Result<Self, MacAudioError> {
        let io_proc: AudioDeviceIOProc = Some(silence_io_proc);

        let mut created_io_proc_id: AudioDeviceIOProc = None;

        let out_io_proc_id = NonNull::from(&mut created_io_proc_id);

        let status = unsafe {
            AudioDeviceCreateIOProcID(device_id, io_proc, std::ptr::null_mut(), out_io_proc_id)
        };

        check_status(status)?;

        let io_proc_id = created_io_proc_id.ok_or(MacAudioError::MissingIOProcID)?;

        Ok(Self {
            device_id,
            io_proc_id: Some(io_proc_id),
        })
    }

    pub fn start(&self) -> Result<(), MacAudioError> {
        let status = unsafe { AudioDeviceStart(self.device_id, self.io_proc_id) };

        check_status(status)
    }

    pub fn stop(&self) -> Result<(), MacAudioError> {
        let status = unsafe { AudioDeviceStop(self.device_id, self.io_proc_id) };

        check_status(status)
    }

    pub fn device_id(&self) -> AudioObjectID {
        self.device_id
    }
}

impl Drop for SilenceOutput {
    fn drop(&mut self) {
        let _ = unsafe { AudioDeviceStop(self.device_id, self.io_proc_id) };

        let _ = unsafe { AudioDeviceDestroyIOProcID(self.device_id, self.io_proc_id) };
    }
}

struct SineState {
    phase: f32,
    sample_rate: f32,
    frequency: f32,
    amplitude: f32,
}

unsafe extern "C-unwind" fn sine_io_proc(
    _device: AudioObjectID,
    _now: NonNull<AudioTimeStamp>,
    _input_data: NonNull<AudioBufferList>,
    _input_time: NonNull<AudioTimeStamp>,
    output_data: NonNull<AudioBufferList>,
    _output_time: NonNull<AudioTimeStamp>,
    client_data: *mut c_void,
) -> i32 {
    if client_data.is_null() {
        return -1;
    }

    let state = unsafe { &mut *(client_data as *mut SineState) };

    let list = unsafe { output_data.as_ref() };

    let buffer_count = list.mNumberBuffers as usize;

    if buffer_count != 1 {
        for index in 0..buffer_count {
            let buffer_ptr = unsafe { list.mBuffers.as_ptr().add(index) };

            let buffer = unsafe { &*buffer_ptr };

            if buffer.mData.is_null() {
                continue;
            }

            let bytes = unsafe {
                slice::from_raw_parts_mut(buffer.mData.cast::<u8>(), buffer.mDataByteSize as usize)
            };

            bytes.fill(0);
        }

        return 0;
    }

    let buffer = unsafe { &*list.mBuffers.as_ptr() };

    if buffer.mData.is_null() {
        return 0;
    }

    let byte_count = buffer.mDataByteSize as usize;

    if byte_count % std::mem::size_of::<f32>() != 0 {
        let bytes = unsafe { slice::from_raw_parts_mut(buffer.mData.cast::<u8>(), byte_count) };

        bytes.fill(0);

        return 0;
    }

    let sample_count = byte_count / std::mem::size_of::<f32>();

    let output = unsafe { slice::from_raw_parts_mut(buffer.mData.cast::<f32>(), sample_count) };

    let channel_count = buffer.mNumberChannels.max(1) as usize;

    let phase_step = TAU * state.frequency / state.sample_rate;

    for frame in output.chunks_exact_mut(channel_count) {
        let sample = state.phase.sin() * state.amplitude;

        for channel_sample in frame.iter_mut() {
            *channel_sample = sample;
        }

        state.phase += phase_step;

        if state.phase >= TAU {
            state.phase -= TAU;
        }
    }

    0
}

pub struct SineOutput {
    device_id: AudioObjectID,
    io_proc_id: AudioDeviceIOProc,

    #[allow(dead_code)]
    state: Box<SineState>,
}

impl SineOutput {
    pub fn open(
        device_id: AudioObjectID,
        frequency: f32,
        amplitude: f32,
    ) -> Result<Self, MacAudioError> {
        let format = output_virtual_format(device_id)?;

        const LINEAR_PCM: u32 = 0x6C70636D;

        const FLOAT: u32 = 0x0001;

        const PACKED: u32 = 0x0008;

        const NON_INTERLEAVED: u32 = 0x0020;

        if format.format_id != LINEAR_PCM
            || format.bits_per_channel != 32
            || format.bytes_per_frame != format.channels * 4
            || format.format_flags & FLOAT == 0
            || format.format_flags & PACKED == 0
            || format.format_flags & NON_INTERLEAVED != 0
        {
            return Err(MacAudioError::InvalidOutputFormat);
        }

        let state = Box::new(SineState {
            phase: 0.0,
            sample_rate: format.sample_rate as f32,
            frequency,
            amplitude: amplitude.clamp(0.0, 1.0),
        });

        let client_data = (&*state as *const SineState).cast_mut().cast::<c_void>();

        let io_proc: AudioDeviceIOProc = Some(sine_io_proc);

        let mut created_io_proc_id: AudioDeviceIOProc = None;

        let out_io_proc_id = NonNull::from(&mut created_io_proc_id);

        let status =
            unsafe { AudioDeviceCreateIOProcID(device_id, io_proc, client_data, out_io_proc_id) };

        check_status(status)?;

        let io_proc_id = created_io_proc_id.ok_or(MacAudioError::MissingIOProcID)?;

        Ok(Self {
            device_id,
            io_proc_id: Some(io_proc_id),
            state,
        })
    }

    pub fn start(&self) -> Result<(), MacAudioError> {
        let status = unsafe { AudioDeviceStart(self.device_id, self.io_proc_id) };

        check_status(status)
    }

    pub fn stop(&self) -> Result<(), MacAudioError> {
        let status = unsafe { AudioDeviceStop(self.device_id, self.io_proc_id) };

        check_status(status)
    }

    pub fn device_id(&self) -> AudioObjectID {
        self.device_id
    }
}

impl Drop for SineOutput {
    fn drop(&mut self) {
        let _ = unsafe { AudioDeviceStop(self.device_id, self.io_proc_id) };

        let _ = unsafe { AudioDeviceDestroyIOProcID(self.device_id, self.io_proc_id) };
    }
}
