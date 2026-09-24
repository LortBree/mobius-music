use std::{
    ffi::{c_char, CStr, CString},
    path::Path,
    ptr,
};

use offline_player_app_core::{
    playback_queue::RepeatMode,
    playback_service::{PlaybackService, PlaybackServiceError},
    PlaybackOutputMode, PlaybackQueue, PlaybackState,
};

const API_VERSION: &[u8] = b"0.1.0\0";

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OfflinePlayerState {
    Idle = 0,
    Loaded = 1,
    Playing = 2,
    Paused = 3,
    Stopped = 4,
}

impl From<PlaybackState> for OfflinePlayerState {
    fn from(value: PlaybackState) -> Self {
        match value {
            PlaybackState::Idle => Self::Idle,
            PlaybackState::Loaded => Self::Loaded,
            PlaybackState::Playing => Self::Playing,
            PlaybackState::Paused => Self::Paused,
            PlaybackState::Stopped => Self::Stopped,
        }
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OfflinePlayerOutputMode {
    Auto = 0,
    Fixed44100 = 1,
    Fixed48000 = 2,
    Fixed96000 = 3,
}

impl From<PlaybackOutputMode> for OfflinePlayerOutputMode {
    fn from(value: PlaybackOutputMode) -> Self {
        match value {
            PlaybackOutputMode::Auto => Self::Auto,
            PlaybackOutputMode::Fixed44100 => Self::Fixed44100,
            PlaybackOutputMode::Fixed48000 => Self::Fixed48000,
            PlaybackOutputMode::Fixed96000 => Self::Fixed96000,
        }
    }
}

fn output_mode_from_raw(value: i32) -> Result<PlaybackOutputMode, OfflinePlayerResult> {
    match value {
        0 => Ok(PlaybackOutputMode::Auto),
        1 => Ok(PlaybackOutputMode::Fixed44100),
        2 => Ok(PlaybackOutputMode::Fixed48000),
        3 => Ok(PlaybackOutputMode::Fixed96000),
        _ => Err(OfflinePlayerResult::InvalidArgument),
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OfflinePlayerRepeatMode {
    Off = 0,
    Track = 1,
    Queue = 2,
}

impl From<RepeatMode> for OfflinePlayerRepeatMode {
    fn from(value: RepeatMode) -> Self {
        match value {
            RepeatMode::Off => Self::Off,
            RepeatMode::Track => Self::Track,
            RepeatMode::Queue => Self::Queue,
        }
    }
}

fn repeat_mode_from_raw(value: i32) -> Result<RepeatMode, OfflinePlayerResult> {
    match value {
        0 => Ok(RepeatMode::Off),
        1 => Ok(RepeatMode::Track),
        2 => Ok(RepeatMode::Queue),
        _ => Err(OfflinePlayerResult::InvalidArgument),
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OfflinePlayerResult {
    Ok = 0,
    NullArgument = 1,
    InvalidUtf8 = 2,
    InvalidArgument = 3,
    NotFound = 4,
    LibraryError = 5,
    PlaybackError = 6,
    BufferTooSmall = 7,
    InternalError = 8,
}

#[repr(C)]
pub struct OfflinePlayerTrackMetadata {
    pub track_id: i64,
    pub title: *mut c_char,
    pub title_capacity: usize,
    pub artist: *mut c_char,
    pub artist_capacity: usize,
    pub album: *mut c_char,
    pub album_capacity: usize,
    pub album_artist: *mut c_char,
    pub album_artist_capacity: usize,
    pub composer: *mut c_char,
    pub composer_capacity: usize,
    pub date: *mut c_char,
    pub date_capacity: usize,
    pub genre: *mut c_char,
    pub genre_capacity: usize,
    pub track_number: u32,
    pub disc_number: u32,
    pub has_disc_number: u8,
}

#[repr(C)]
pub struct OfflinePlayerTrackArtwork {
    pub track_id: i64,
    pub mime_type: *mut c_char,
    pub mime_type_capacity: usize,
    pub mime_type_size: usize,
    pub data: *mut u8,
    pub data_capacity: usize,
    pub data_size: usize,
}

impl OfflinePlayerResult {
    fn from_service_error(error: &PlaybackServiceError) -> Self {
        match error {
            PlaybackServiceError::TrackNotFound { .. } => Self::NotFound,
            PlaybackServiceError::Library(_) => Self::LibraryError,
            PlaybackServiceError::Playback(_) => Self::PlaybackError,
        }
    }
}

struct OfflinePlayer {
    service: PlaybackService,
    queue: PlaybackQueue,
    last_error: Option<CString>,
}

impl OfflinePlayer {
    fn new(db_path: &Path) -> Result<Self, PlaybackServiceError> {
        Ok(Self {
            service: PlaybackService::open(db_path)?,
            queue: PlaybackQueue::new(),
            last_error: None,
        })
    }

    fn set_error(&mut self, message: impl Into<String>) {
        let message = message.into();

        self.last_error = Some(
            CString::new(message)
                .unwrap_or_else(|_| CString::new("FFI error").expect("static string is valid")),
        );
    }

    fn clear_error(&mut self) {
        self.last_error = None;
    }

    fn fail(
        &mut self,
        code: OfflinePlayerResult,
        message: impl Into<String>,
    ) -> OfflinePlayerResult {
        self.set_error(message);
        code
    }

    fn write_string(
        &mut self,
        value: &str,
        buffer: *mut c_char,
        capacity: usize,
    ) -> OfflinePlayerResult {
        if buffer.is_null() {
            return self.fail(OfflinePlayerResult::NullArgument, "output buffer is null");
        }

        let bytes = value.as_bytes();

        let required = match bytes.len().checked_add(1) {
            Some(value) => value,
            None => return self.fail(OfflinePlayerResult::InternalError, "string length overflow"),
        };

        if capacity < required {
            return self.fail(
                OfflinePlayerResult::BufferTooSmall,
                format!("buffer too small; required {required} bytes"),
            );
        }

        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr().cast::<c_char>(), buffer, bytes.len());
            *buffer.add(bytes.len()) = 0;
        }

        self.clear_error();
        OfflinePlayerResult::Ok
    }
    fn write_bytes(
        &mut self,
        value: &[u8],
        buffer: *mut u8,
        capacity: usize,
    ) -> OfflinePlayerResult {
        if value.len() > capacity {
            return self.fail(
                OfflinePlayerResult::BufferTooSmall,
                format!("buffer too small; required {} bytes", value.len()),
            );
        }

        if !value.is_empty() {
            if buffer.is_null() {
                return self.fail(OfflinePlayerResult::NullArgument, "output buffer is null");
            }

            unsafe {
                ptr::copy_nonoverlapping(value.as_ptr(), buffer, value.len());
            }
        }

        self.clear_error();
        OfflinePlayerResult::Ok
    }
}

unsafe fn handle_ref<'a>(
    handle: *mut OfflinePlayerHandle,
) -> Result<&'a mut OfflinePlayer, OfflinePlayerResult> {
    if handle.is_null() {
        return Err(OfflinePlayerResult::NullArgument);
    }

    Ok(&mut (*handle).inner)
}

#[repr(C)]
pub struct OfflinePlayerHandle {
    inner: OfflinePlayer,
}

fn read_utf8_string(value: *const c_char) -> Result<String, OfflinePlayerResult> {
    if value.is_null() {
        return Err(OfflinePlayerResult::NullArgument);
    }

    let c_string = unsafe { CStr::from_ptr(value) };

    let string = c_string
        .to_str()
        .map_err(|_| OfflinePlayerResult::InvalidUtf8)?;

    if string.is_empty() {
        return Err(OfflinePlayerResult::InvalidArgument);
    }

    Ok(string.to_owned())
}

fn load_current_track_metadata_value(
    player: &mut OfflinePlayer,
    selector: fn(&offline_player_app_core::library_store::TrackMetadata) -> Option<&str>,
) -> Result<String, OfflinePlayerResult> {
    let track_id = match player.service.current_track() {
        Some(track) => track.track_id,
        None => return Err(OfflinePlayerResult::NotFound),
    };

    let metadata = match player.service.library().track_metadata(track_id) {
        Ok(Some(value)) => value,
        Ok(None) => return Err(OfflinePlayerResult::NotFound),
        Err(error) => {
            player.set_error(error.to_string());

            return Err(OfflinePlayerResult::LibraryError);
        }
    };

    Ok(selector(&metadata).unwrap_or("").to_owned())
}

#[no_mangle]
pub extern "C" fn offline_player_version() -> *const c_char {
    API_VERSION.as_ptr().cast()
}

#[no_mangle]
pub extern "C" fn offline_player_create(
    db_path: *const c_char,
    out_handle: *mut *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    if out_handle.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    unsafe {
        *out_handle = ptr::null_mut();
    }

    let db_path = match read_utf8_string(db_path) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let player = match OfflinePlayer::new(Path::new(&db_path)) {
        Ok(value) => value,
        Err(error) => return OfflinePlayerResult::from_service_error(&error),
    };

    let handle = Box::new(OfflinePlayerHandle { inner: player });

    unsafe {
        *out_handle = Box::into_raw(handle);
    }

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_destroy(handle: *mut OfflinePlayerHandle) {
    if handle.is_null() {
        return;
    }

    drop(Box::from_raw(handle));
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_scan_directory(
    handle: *mut OfflinePlayerHandle,
    root_path: *const c_char,
    out_scanned_assets: *mut i64,
    out_ignored_files: *mut i64,
    out_scan_errors: *mut i64,
    out_persisted_assets: *mut i64,
) -> OfflinePlayerResult {
    if out_scanned_assets.is_null()
        || out_ignored_files.is_null()
        || out_scan_errors.is_null()
        || out_persisted_assets.is_null()
    {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let root_path = match read_utf8_string(root_path) {
        Ok(value) => value,
        Err(code) => {
            player.set_error("invalid root path");
            return code;
        }
    };

    let report = match player.service.scan_directory(Path::new(&root_path)) {
        Ok(value) => value,
        Err(error) => {
            let code = OfflinePlayerResult::from_service_error(&error);

            player.set_error(error.to_string());

            return code;
        }
    };

    let scanned_assets = match i64::try_from(report.scanned_assets()) {
        Ok(value) => value,
        Err(_) => {
            return player.fail(
                OfflinePlayerResult::InternalError,
                "scanned asset count exceeds i64",
            )
        }
    };

    let ignored_files = match i64::try_from(report.ignored_files()) {
        Ok(value) => value,
        Err(_) => {
            return player.fail(
                OfflinePlayerResult::InternalError,
                "ignored file count exceeds i64",
            )
        }
    };

    let scan_errors = match i64::try_from(report.scan_errors()) {
        Ok(value) => value,
        Err(_) => {
            return player.fail(
                OfflinePlayerResult::InternalError,
                "scan error count exceeds i64",
            )
        }
    };

    let persisted_assets = match i64::try_from(report.persisted_assets()) {
        Ok(value) => value,
        Err(_) => {
            return player.fail(
                OfflinePlayerResult::InternalError,
                "persisted asset count exceeds i64",
            )
        }
    };

    unsafe {
        *out_scanned_assets = scanned_assets;
        *out_ignored_files = ignored_files;
        *out_scan_errors = scan_errors;
        *out_persisted_assets = persisted_assets;
    }

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_library_track_count(
    handle: *mut OfflinePlayerHandle,
    out_count: *mut i64,
) -> OfflinePlayerResult {
    if out_count.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.library().track_count() {
        Ok(count) => {
            *out_count = count;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => {
            player.set_error(error.to_string());
            OfflinePlayerResult::LibraryError
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_library_track_id_at(
    handle: *mut OfflinePlayerHandle,
    index: i64,
    out_track_id: *mut i64,
) -> OfflinePlayerResult {
    if out_track_id.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    if index < 0 {
        let player = match handle_ref(handle) {
            Ok(value) => value,
            Err(code) => return code,
        };

        return player.fail(
            OfflinePlayerResult::InvalidArgument,
            "track index must not be negative",
        );
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let tracks = match player.service.library().playback_tracks() {
        Ok(value) => value,
        Err(error) => {
            player.set_error(error.to_string());
            return OfflinePlayerResult::LibraryError;
        }
    };

    let index = match usize::try_from(index) {
        Ok(value) => value,
        Err(_) => {
            return player.fail(
                OfflinePlayerResult::InvalidArgument,
                "track index is out of range",
            )
        }
    };

    match tracks.get(index) {
        Some(track) => {
            *out_track_id = track.track_id;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(OfflinePlayerResult::NotFound, "track index is out of range"),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_library_track_artwork(
    handle: *mut OfflinePlayerHandle,
    track_id: i64,
    out_artwork: *mut OfflinePlayerTrackArtwork,
) -> OfflinePlayerResult {
    if out_artwork.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let artwork = match player.service.library().track_artwork(track_id) {
        Ok(Some(value)) => value,
        Ok(None) => return player.fail(OfflinePlayerResult::NotFound, "track artwork not found"),
        Err(error) => {
            player.set_error(error.to_string());
            return OfflinePlayerResult::LibraryError;
        }
    };

    let out = &mut *out_artwork;

    let mime_type = artwork.mime_type.as_deref().unwrap_or("");
    let mime_bytes = mime_type.as_bytes();

    let mime_required = match mime_bytes.len().checked_add(1) {
        Some(value) => value,
        None => {
            return player.fail(
                OfflinePlayerResult::InternalError,
                "MIME type length overflow",
            )
        }
    };

    out.track_id = track_id;
    out.mime_type_size = mime_required;
    out.data_size = artwork.data.len();

    if out.mime_type_capacity < mime_required {
        return player.fail(
            OfflinePlayerResult::BufferTooSmall,
            format!("MIME type buffer too small; required {mime_required} bytes"),
        );
    }

    if artwork.data.len() > out.data_capacity {
        return player.fail(
            OfflinePlayerResult::BufferTooSmall,
            format!(
                "artwork buffer too small; required {} bytes",
                artwork.data.len()
            ),
        );
    }

    let result = player.write_string(mime_type, out.mime_type, out.mime_type_capacity);

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_bytes(&artwork.data, out.data, out.data_capacity);

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_load_track(
    handle: *mut OfflinePlayerHandle,
    track_id: i64,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.load_track(track_id) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => {
            let code = OfflinePlayerResult::from_service_error(&error);

            player.set_error(error.to_string());

            code
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_play(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.play() {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => {
            let code = OfflinePlayerResult::from_service_error(&error);

            player.set_error(error.to_string());

            code
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_pause(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.pause() {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => {
            let code = OfflinePlayerResult::from_service_error(&error);

            player.set_error(error.to_string());

            code
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_stop(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.stop() {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => {
            let code = OfflinePlayerResult::from_service_error(&error);

            player.set_error(error.to_string());

            code
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_seek_to_frame(
    handle: *mut OfflinePlayerHandle,
    frame: u64,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.seek_to_frame(frame) {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => {
            let code = OfflinePlayerResult::from_service_error(&error);

            player.set_error(error.to_string());

            code
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_set_output_mode(
    handle: *mut OfflinePlayerHandle,
    mode: i32,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let mode = match output_mode_from_raw(mode) {
        Ok(value) => value,
        Err(code) => return player.fail(code, "invalid output mode"),
    };

    player.service.set_output_mode(mode);

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_output_mode(
    handle: *mut OfflinePlayerHandle,
    out_mode: *mut OfflinePlayerOutputMode,
) -> OfflinePlayerResult {
    if out_mode.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    *out_mode = player.service.output_mode().into();

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_set_volume(
    handle: *mut OfflinePlayerHandle,
    volume: f32,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    if !volume.is_finite() {
        return player.fail(
            OfflinePlayerResult::InvalidArgument,
            "volume must be finite",
        );
    }

    player.service.set_volume(volume.clamp(0.0, 1.0));
    player.clear_error();
    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_set_equalizer_gains(
    handle: *mut OfflinePlayerHandle,
    gains_db: *const f32,
    band_count: usize,
) -> OfflinePlayerResult {
    if gains_db.is_null() {
        return OfflinePlayerResult::NullArgument;
    }
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };
    if band_count != 10 {
        return player.fail(
            OfflinePlayerResult::InvalidArgument,
            "equalizer expects exactly ten bands",
        );
    }
    let values = std::slice::from_raw_parts(gains_db, band_count);
    let mut gains = [0.0_f32; 10];
    gains.copy_from_slice(values);
    if gains.iter().any(|gain| !gain.is_finite()) {
        return player.fail(
            OfflinePlayerResult::InvalidArgument,
            "equalizer gains must be finite",
        );
    }
    player.service.set_equalizer_gains(gains);
    player.clear_error();
    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_state(
    handle: *mut OfflinePlayerHandle,
    out_state: *mut OfflinePlayerState,
) -> OfflinePlayerResult {
    if out_state.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    *out_state = player.service.state().into();

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_current_frame(
    handle: *mut OfflinePlayerHandle,
    out_frame: *mut u64,
) -> OfflinePlayerResult {
    if out_frame.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_frame() {
        Some(frame) => {
            *out_frame = frame;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::PlaybackError,
            "current playback frame is unavailable",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_current_source_frame(
    handle: *mut OfflinePlayerHandle,
    out_frame: *mut u64,
) -> OfflinePlayerResult {
    if out_frame.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_source_frame() {
        Some(frame) => {
            *out_frame = frame;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::PlaybackError,
            "current source frame is unavailable",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_current_seconds(
    handle: *mut OfflinePlayerHandle,
    out_seconds: *mut f64,
) -> OfflinePlayerResult {
    if out_seconds.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_seconds() {
        Some(seconds) => {
            *out_seconds = seconds;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::PlaybackError,
            "current playback position is unavailable",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_duration_seconds(
    handle: *mut OfflinePlayerHandle,
    out_seconds: *mut f64,
) -> OfflinePlayerResult {
    if out_seconds.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.duration_seconds() {
        Some(seconds) => {
            *out_seconds = seconds;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::PlaybackError,
            "track duration is unavailable",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_total_frames(
    handle: *mut OfflinePlayerHandle,
    out_frames: *mut u64,
) -> OfflinePlayerResult {
    if out_frames.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.total_frames() {
        Some(frames) => {
            *out_frames = frames;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::PlaybackError,
            "track frame count is unavailable",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_id(
    handle: *mut OfflinePlayerHandle,
    out_track_id: *mut i64,
) -> OfflinePlayerResult {
    if out_track_id.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_track() {
        Some(track) => {
            *out_track_id = track.track_id;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::NotFound,
            "no track is currently loaded",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_asset_id(
    handle: *mut OfflinePlayerHandle,
    out_asset_id: *mut i64,
) -> OfflinePlayerResult {
    if out_asset_id.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_track() {
        Some(track) => {
            *out_asset_id = track.asset_id;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::NotFound,
            "no track is currently loaded",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_sample_rate(
    handle: *mut OfflinePlayerHandle,
    out_sample_rate: *mut u32,
) -> OfflinePlayerResult {
    if out_sample_rate.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_track() {
        Some(track) => {
            *out_sample_rate = track.sample_rate;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::NotFound,
            "no track is currently loaded",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_channels(
    handle: *mut OfflinePlayerHandle,
    out_channels: *mut u16,
) -> OfflinePlayerResult {
    if out_channels.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_track() {
        Some(track) => {
            *out_channels = track.channels;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::NotFound,
            "no track is currently loaded",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_bits_per_sample(
    handle: *mut OfflinePlayerHandle,
    out_bits: *mut u16,
) -> OfflinePlayerResult {
    if out_bits.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.service.current_track() {
        Some(track) => {
            *out_bits = track.bits_per_sample;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::NotFound,
            "no track is currently loaded",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_path(
    handle: *mut OfflinePlayerHandle,
    buffer: *mut c_char,
    capacity: usize,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let path = match player.service.current_track() {
        Some(track) => track.path.to_string_lossy().into_owned(),
        None => {
            return player.fail(
                OfflinePlayerResult::NotFound,
                "no track is currently loaded",
            )
        }
    };

    player.write_string(&path, buffer, capacity)
}

macro_rules! define_string_metadata_fn {
    ($name:ident, $field:ident) => {
        #[no_mangle]
        pub unsafe extern "C" fn $name(
            handle: *mut OfflinePlayerHandle,
            buffer: *mut c_char,
            capacity: usize,
        ) -> OfflinePlayerResult {
            let player = match handle_ref(handle) {
                Ok(value) => value,
                Err(code) => return code,
            };

            let value = match load_current_track_metadata_value(player, |metadata| {
                metadata.$field.as_deref()
            }) {
                Ok(value) => value,
                Err(code) => {
                    if player.last_error.is_none() {
                        player.set_error("track metadata is unavailable");
                    }

                    return code;
                }
            };

            player.write_string(&value, buffer, capacity)
        }
    };
}

define_string_metadata_fn!(offline_player_track_title, title);
define_string_metadata_fn!(offline_player_track_artist, artist);
define_string_metadata_fn!(offline_player_track_album, album);
define_string_metadata_fn!(offline_player_track_album_artist, album_artist);
define_string_metadata_fn!(offline_player_track_composer, composer);
define_string_metadata_fn!(offline_player_track_date, date);
define_string_metadata_fn!(offline_player_track_genre, genre);

#[no_mangle]
pub unsafe extern "C" fn offline_player_library_track_metadata(
    handle: *mut OfflinePlayerHandle,
    track_id: i64,
    out_metadata: *mut OfflinePlayerTrackMetadata,
) -> OfflinePlayerResult {
    if out_metadata.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let metadata = match player.service.library().track_metadata(track_id) {
        Ok(Some(value)) => value,
        Ok(None) => return player.fail(OfflinePlayerResult::NotFound, "track metadata not found"),
        Err(error) => {
            player.set_error(error.to_string());
            return OfflinePlayerResult::LibraryError;
        }
    };

    let out = &mut *out_metadata;

    out.track_id = track_id;

    let result = player.write_string(
        metadata.title.as_deref().unwrap_or(""),
        out.title,
        out.title_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_string(
        metadata.artist.as_deref().unwrap_or(""),
        out.artist,
        out.artist_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_string(
        metadata.album.as_deref().unwrap_or(""),
        out.album,
        out.album_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_string(
        metadata.album_artist.as_deref().unwrap_or(""),
        out.album_artist,
        out.album_artist_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_string(
        metadata.composer.as_deref().unwrap_or(""),
        out.composer,
        out.composer_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_string(
        metadata.date.as_deref().unwrap_or(""),
        out.date,
        out.date_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    let result = player.write_string(
        metadata.genre.as_deref().unwrap_or(""),
        out.genre,
        out.genre_capacity,
    );

    if result != OfflinePlayerResult::Ok {
        return result;
    }

    out.track_number = metadata.track_number;

    match metadata.disc_number {
        Some(value) => {
            out.disc_number = value;
            out.has_disc_number = 1;
        }
        None => {
            out.disc_number = 0;
            out.has_disc_number = 0;
        }
    }

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_number(
    handle: *mut OfflinePlayerHandle,
    out_track_number: *mut u32,
) -> OfflinePlayerResult {
    if out_track_number.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let track_id = match player.service.current_track() {
        Some(track) => track.track_id,
        None => {
            return player.fail(
                OfflinePlayerResult::NotFound,
                "no track is currently loaded",
            )
        }
    };

    let metadata = match player.service.library().track_metadata(track_id) {
        Ok(Some(value)) => value,
        Ok(None) => return player.fail(OfflinePlayerResult::NotFound, "track metadata not found"),
        Err(error) => {
            player.set_error(error.to_string());

            return OfflinePlayerResult::LibraryError;
        }
    };

    *out_track_number = metadata.track_number;

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_track_disc_number(
    handle: *mut OfflinePlayerHandle,
    out_disc_number: *mut u32,
) -> OfflinePlayerResult {
    if out_disc_number.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let track_id = match player.service.current_track() {
        Some(track) => track.track_id,
        None => {
            return player.fail(
                OfflinePlayerResult::NotFound,
                "no track is currently loaded",
            )
        }
    };

    let metadata = match player.service.library().track_metadata(track_id) {
        Ok(Some(value)) => value,
        Ok(None) => return player.fail(OfflinePlayerResult::NotFound, "track metadata not found"),
        Err(error) => {
            player.set_error(error.to_string());

            return OfflinePlayerResult::LibraryError;
        }
    };

    match metadata.disc_number {
        Some(number) => {
            *out_disc_number = number;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(OfflinePlayerResult::NotFound, "disc number is unavailable"),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_set(
    handle: *mut OfflinePlayerHandle,
    track_ids: *const i64,
    track_count: usize,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    if track_count > 0 && track_ids.is_null() {
        return player.fail(
            OfflinePlayerResult::NullArgument,
            "track_ids is null while track_count is non-zero",
        );
    }

    let ids = if track_count == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(track_ids, track_count).to_vec() }
    };

    match player.queue.set_queue(&player.service, ids) {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_add(
    handle: *mut OfflinePlayerHandle,
    track_id: i64,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.add_to_queue(&player.service, track_id) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_clear(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    player.queue.clear();
    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_length(
    handle: *mut OfflinePlayerHandle,
    out_length: *mut usize,
) -> OfflinePlayerResult {
    if out_length.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    *out_length = player.queue.len();

    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_track_id_at(
    handle: *mut OfflinePlayerHandle,
    index: usize,
    out_track_id: *mut i64,
) -> OfflinePlayerResult {
    if out_track_id.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.track_id_at(index) {
        Some(track_id) => {
            *out_track_id = track_id;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(OfflinePlayerResult::NotFound, "queue index is out of range"),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_up_next_count(
    handle: *mut OfflinePlayerHandle,
    out_count: *mut usize,
) -> OfflinePlayerResult {
    if out_count.is_null() {
        return OfflinePlayerResult::NullArgument;
    }
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };
    *out_count = player.queue.queued_count();
    player.clear_error();
    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_reorder_segment(
    handle: *mut OfflinePlayerHandle,
    start: usize,
    track_ids: *const i64,
    track_count: usize,
) -> OfflinePlayerResult {
    if track_count > 0 && track_ids.is_null() {
        return OfflinePlayerResult::NullArgument;
    }
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };
    let ids = if track_count == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(track_ids, track_count).to_vec() }
    };
    match player.queue.reorder_segment(start, ids) {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_current_index(
    handle: *mut OfflinePlayerHandle,
    out_index: *mut usize,
) -> OfflinePlayerResult {
    if out_index.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.current_index() {
        Some(index) => {
            *out_index = index;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(
            OfflinePlayerResult::NotFound,
            "queue has no current position",
        ),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_current_track_id(
    handle: *mut OfflinePlayerHandle,
    out_track_id: *mut i64,
) -> OfflinePlayerResult {
    if out_track_id.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.current_position() {
        Some(position) => {
            *out_track_id = position.track_id;
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        None => player.fail(OfflinePlayerResult::NotFound, "queue has no current track"),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_set_repeat_mode(
    handle: *mut OfflinePlayerHandle,
    mode: i32,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let mode = match repeat_mode_from_raw(mode) {
        Ok(value) => value,
        Err(code) => return player.fail(code, "invalid repeat mode"),
    };

    player.queue.set_repeat_mode(mode);
    player.clear_error();

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_repeat_mode(
    handle: *mut OfflinePlayerHandle,
    out_mode: *mut OfflinePlayerRepeatMode,
) -> OfflinePlayerResult {
    if out_mode.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    *out_mode = player.queue.repeat_mode().into();

    player.clear_error();

    OfflinePlayerResult::Ok
}

fn map_queue_error(
    player: &mut OfflinePlayer,
    error: offline_player_app_core::playback_queue::PlaybackQueueError,
) -> OfflinePlayerResult {
    let code = match &error {
        offline_player_app_core::playback_queue::PlaybackQueueError::TrackNotFound { .. } => {
            OfflinePlayerResult::NotFound
        }

        offline_player_app_core::playback_queue::PlaybackQueueError::Library(_) => {
            OfflinePlayerResult::LibraryError
        }

        offline_player_app_core::playback_queue::PlaybackQueueError::Playback(_) => {
            OfflinePlayerResult::PlaybackError
        }

        offline_player_app_core::playback_queue::PlaybackQueueError::Empty
        | offline_player_app_core::playback_queue::PlaybackQueueError::IndexOutOfRange { .. }
        | offline_player_app_core::playback_queue::PlaybackQueueError::InvalidReorder => {
            OfflinePlayerResult::InvalidArgument
        }
    };

    player.set_error(error.to_string());

    code
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_select(
    handle: *mut OfflinePlayerHandle,
    index: usize,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.select(&player.service, index) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_select_and_load(
    handle: *mut OfflinePlayerHandle,
    index: usize,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.select_and_load(&mut player.service, index) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_play_current(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.play_current(&mut player.service) {
        Ok(()) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_select_and_play(
    handle: *mut OfflinePlayerHandle,
    index: usize,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.select_and_play(&mut player.service, index) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_next(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.next(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_next_and_play(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.next_and_play(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_previous(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.previous(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_previous_and_play(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.previous_and_play(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_repeat_current_and_play(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.repeat_current_and_play(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_advance_and_play(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.advance_and_play(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_queue_advance_if_at_end(
    handle: *mut OfflinePlayerHandle,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    match player.queue.advance_if_at_end(&mut player.service) {
        Ok(_) => {
            player.clear_error();
            OfflinePlayerResult::Ok
        }
        Err(error) => map_queue_error(player, error),
    }
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_last_error(
    handle: *mut OfflinePlayerHandle,
    buffer: *mut c_char,
    capacity: usize,
) -> OfflinePlayerResult {
    let player = match handle_ref(handle) {
        Ok(value) => value,
        Err(code) => return code,
    };

    let message = match &player.last_error {
        Some(message) => message.to_string_lossy().into_owned(),
        None => String::new(),
    };

    player.write_string(&message, buffer, capacity)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_mapping_is_stable() {
        assert_eq!(
            OfflinePlayerState::from(PlaybackState::Idle),
            OfflinePlayerState::Idle
        );

        assert_eq!(
            OfflinePlayerState::from(PlaybackState::Loaded),
            OfflinePlayerState::Loaded
        );

        assert_eq!(
            OfflinePlayerState::from(PlaybackState::Playing),
            OfflinePlayerState::Playing
        );

        assert_eq!(
            OfflinePlayerState::from(PlaybackState::Paused),
            OfflinePlayerState::Paused
        );

        assert_eq!(
            OfflinePlayerState::from(PlaybackState::Stopped),
            OfflinePlayerState::Stopped
        );
    }

    #[test]
    fn output_mode_mapping_is_stable() {
        assert_eq!(
            OfflinePlayerOutputMode::from(PlaybackOutputMode::Auto),
            OfflinePlayerOutputMode::Auto
        );

        assert_eq!(
            OfflinePlayerOutputMode::from(PlaybackOutputMode::Fixed44100),
            OfflinePlayerOutputMode::Fixed44100
        );

        assert_eq!(
            OfflinePlayerOutputMode::from(PlaybackOutputMode::Fixed48000),
            OfflinePlayerOutputMode::Fixed48000
        );

        assert_eq!(
            OfflinePlayerOutputMode::from(PlaybackOutputMode::Fixed96000),
            OfflinePlayerOutputMode::Fixed96000
        );
    }

    #[test]
    fn output_mode_values_are_stable() {
        assert_eq!(OfflinePlayerOutputMode::Auto as i32, 0);
        assert_eq!(OfflinePlayerOutputMode::Fixed44100 as i32, 1);
        assert_eq!(OfflinePlayerOutputMode::Fixed48000 as i32, 2);
        assert_eq!(OfflinePlayerOutputMode::Fixed96000 as i32, 3);
    }

    #[test]
    fn output_mode_raw_values_are_validated() {
        assert_eq!(output_mode_from_raw(0), Ok(PlaybackOutputMode::Auto));

        assert_eq!(output_mode_from_raw(1), Ok(PlaybackOutputMode::Fixed44100));

        assert_eq!(output_mode_from_raw(2), Ok(PlaybackOutputMode::Fixed48000));

        assert_eq!(output_mode_from_raw(3), Ok(PlaybackOutputMode::Fixed96000));

        assert_eq!(
            output_mode_from_raw(99),
            Err(OfflinePlayerResult::InvalidArgument)
        );
    }

    #[test]
    fn repeat_mode_mapping_is_stable() {
        assert_eq!(
            OfflinePlayerRepeatMode::from(RepeatMode::Off),
            OfflinePlayerRepeatMode::Off
        );

        assert_eq!(
            OfflinePlayerRepeatMode::from(RepeatMode::Track),
            OfflinePlayerRepeatMode::Track
        );

        assert_eq!(
            OfflinePlayerRepeatMode::from(RepeatMode::Queue),
            OfflinePlayerRepeatMode::Queue
        );
    }

    #[test]
    fn repeat_mode_values_are_stable() {
        assert_eq!(OfflinePlayerRepeatMode::Off as i32, 0);
        assert_eq!(OfflinePlayerRepeatMode::Track as i32, 1);
        assert_eq!(OfflinePlayerRepeatMode::Queue as i32, 2);
    }

    #[test]
    fn repeat_mode_raw_values_are_validated() {
        assert_eq!(repeat_mode_from_raw(0), Ok(RepeatMode::Off));
        assert_eq!(repeat_mode_from_raw(1), Ok(RepeatMode::Track));
        assert_eq!(repeat_mode_from_raw(2), Ok(RepeatMode::Queue));

        assert_eq!(
            repeat_mode_from_raw(99),
            Err(OfflinePlayerResult::InvalidArgument)
        );
    }

    #[test]
    fn version_is_nul_terminated() {
        let ptr = offline_player_version();

        assert!(!ptr.is_null());

        let version = unsafe { CStr::from_ptr(ptr) };

        assert_eq!(version.to_bytes(), b"0.1.0");
    }

    #[test]
    fn result_codes_are_stable() {
        assert_eq!(OfflinePlayerResult::Ok as i32, 0);
        assert_eq!(OfflinePlayerResult::NullArgument as i32, 1);
        assert_eq!(OfflinePlayerResult::InvalidUtf8 as i32, 2);
        assert_eq!(OfflinePlayerResult::InvalidArgument as i32, 3);
        assert_eq!(OfflinePlayerResult::NotFound as i32, 4);
        assert_eq!(OfflinePlayerResult::LibraryError as i32, 5);
        assert_eq!(OfflinePlayerResult::PlaybackError as i32, 6);
        assert_eq!(OfflinePlayerResult::BufferTooSmall as i32, 7);
        assert_eq!(OfflinePlayerResult::InternalError as i32, 8);
    }

    #[test]
    fn null_utf8_pointer_is_rejected() {
        assert_eq!(
            read_utf8_string(ptr::null()),
            Err(OfflinePlayerResult::NullArgument)
        );
    }

    #[test]
    fn empty_string_is_rejected() {
        let value = CString::new("").expect("empty CString should be valid");

        assert_eq!(
            read_utf8_string(value.as_ptr()),
            Err(OfflinePlayerResult::InvalidArgument)
        );
    }

    #[test]
    fn destroy_accepts_null() {
        unsafe {
            offline_player_destroy(ptr::null_mut());
        }
    }
}
