use std::{
    env,
    ffi::{c_char, CStr, CString},
    fs, ptr, thread,
    time::Duration,
};

use offline_player_ffi::{
    offline_player_create, offline_player_current_frame, offline_player_current_seconds,
    offline_player_destroy, offline_player_duration_seconds, offline_player_library_track_count,
    offline_player_library_track_id_at, offline_player_load_track, offline_player_pause,
    offline_player_play, offline_player_scan_directory, offline_player_seek_to_frame,
    offline_player_state, offline_player_stop, offline_player_total_frames,
    offline_player_track_album, offline_player_track_artist, offline_player_track_asset_id,
    offline_player_track_bits_per_sample, offline_player_track_channels,
    offline_player_track_composer, offline_player_track_date, offline_player_track_genre,
    offline_player_track_id, offline_player_track_number, offline_player_track_path,
    offline_player_track_sample_rate, offline_player_track_title, offline_player_version,
    OfflinePlayerHandle, OfflinePlayerResult, OfflinePlayerState,
};

fn check(result: OfflinePlayerResult, operation: &str) {
    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "{operation} failed: {:?}",
        result
    );
}

unsafe fn read_string(
    handle: *mut OfflinePlayerHandle,
    read_fn: unsafe extern "C" fn(
        *mut OfflinePlayerHandle,
        *mut c_char,
        usize,
    ) -> OfflinePlayerResult,
) -> String {
    let mut buffer = vec![0i8; 4096];

    let result = read_fn(handle, buffer.as_mut_ptr().cast(), buffer.len());

    check(result, "read string");

    CStr::from_ptr(buffer.as_ptr().cast())
        .to_string_lossy()
        .into_owned()
}

#[test]
fn ffi_smoke_test() {
    let root = env::var_os("OFFLINE_PLAYER_MUSIC_ROOT")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| "/Users/bree/Downloads/Music".into());

    assert!(
        root.is_dir(),
        "music root does not exist: {}",
        root.display()
    );

    let db_path = env::temp_dir().join(format!(
        "offline-player-ffi-smoke-{}.sqlite",
        std::process::id()
    ));

    let _ = fs::remove_file(&db_path);

    let db_path_c = CString::new(db_path.to_str().expect("temporary db path is not UTF-8"))
        .expect("db path contains NUL");

    let version_ptr = offline_player_version();

    assert!(!version_ptr.is_null());

    let version = unsafe { CStr::from_ptr(version_ptr).to_string_lossy().into_owned() };

    assert_eq!(version, "0.1.0");

    let mut handle: *mut OfflinePlayerHandle = ptr::null_mut();

    check(
        offline_player_create(db_path_c.as_ptr(), &mut handle),
        "create",
    );

    assert!(!handle.is_null());

    let root_c = CString::new(root.to_str().expect("music root is not UTF-8"))
        .expect("music root contains NUL");

    let mut scanned_assets = 0i64;
    let mut ignored_files = 0i64;
    let mut scan_errors = 0i64;
    let mut persisted_assets = 0i64;

    check(
        unsafe {
            offline_player_scan_directory(
                handle,
                root_c.as_ptr(),
                &mut scanned_assets,
                &mut ignored_files,
                &mut scan_errors,
                &mut persisted_assets,
            )
        },
        "scan directory",
    );

    assert!(scanned_assets > 0);
    assert_eq!(scan_errors, 0);
    assert_eq!(scanned_assets, persisted_assets);

    let mut track_count = 0i64;

    check(
        unsafe { offline_player_library_track_count(handle, &mut track_count) },
        "library track count",
    );

    assert!(track_count > 0);

    let mut emc_track_id = None;

    for index in 0..track_count {
        let mut candidate_id = 0i64;

        check(
            unsafe { offline_player_library_track_id_at(handle, index, &mut candidate_id) },
            "library track id",
        );

        check(
            unsafe { offline_player_load_track(handle, candidate_id) },
            "load candidate track",
        );

        let title = unsafe { read_string(handle, offline_player_track_title) };
        let artist = unsafe { read_string(handle, offline_player_track_artist) };

        if title == "EMC_01_Nu" && artist == "Shiro Sagisu" {
            emc_track_id = Some(candidate_id);
            break;
        }
    }

    let emc_track_id = emc_track_id.expect("EMC_01_Nu / Shiro Sagisu track not found");

    check(
        unsafe { offline_player_load_track(handle, emc_track_id) },
        "load EMC track",
    );

    let mut state = OfflinePlayerState::Idle;

    check(
        unsafe { offline_player_state(handle, &mut state) },
        "state after load",
    );

    assert_eq!(state, OfflinePlayerState::Loaded);

    let mut track_id = 0i64;
    let mut asset_id = 0i64;
    let mut sample_rate = 0u32;
    let mut channels = 0u16;
    let mut bits = 0u16;
    let mut total_frames = 0u64;
    let mut duration = 0.0f64;
    let mut track_number = 0u32;

    check(
        unsafe { offline_player_track_id(handle, &mut track_id) },
        "track id",
    );

    check(
        unsafe { offline_player_track_asset_id(handle, &mut asset_id) },
        "asset id",
    );

    check(
        unsafe { offline_player_track_sample_rate(handle, &mut sample_rate) },
        "sample rate",
    );

    check(
        unsafe { offline_player_track_channels(handle, &mut channels) },
        "channels",
    );

    check(
        unsafe { offline_player_track_bits_per_sample(handle, &mut bits) },
        "bits",
    );

    check(
        unsafe { offline_player_total_frames(handle, &mut total_frames) },
        "total frames",
    );

    check(
        unsafe { offline_player_duration_seconds(handle, &mut duration) },
        "duration",
    );

    let path = unsafe { read_string(handle, offline_player_track_path) };
    let title = unsafe { read_string(handle, offline_player_track_title) };
    let artist = unsafe { read_string(handle, offline_player_track_artist) };

    let _album = unsafe { read_string(handle, offline_player_track_album) };
    let _composer = unsafe { read_string(handle, offline_player_track_composer) };
    let _date = unsafe { read_string(handle, offline_player_track_date) };
    let _genre = unsafe { read_string(handle, offline_player_track_genre) };

    check(
        unsafe { offline_player_track_number(handle, &mut track_number) },
        "track number",
    );

    assert_eq!(track_id, emc_track_id);

    assert_eq!(sample_rate, 44_100);
    assert_eq!(channels, 2);
    assert_eq!(bits, 16);

    assert_eq!(total_frames, 2_551_618);

    assert!(duration > 57.0 && duration < 59.0);

    assert!(!path.is_empty());

    assert_eq!(title, "EMC_01_Nu");
    assert_eq!(artist, "Shiro Sagisu");

    let mut frame = 0u64;
    let mut seconds = 0.0f64;

    check(
        unsafe { offline_player_current_frame(handle, &mut frame) },
        "initial frame",
    );

    check(
        unsafe { offline_player_current_seconds(handle, &mut seconds) },
        "initial seconds",
    );

    assert_eq!(frame, 0);
    assert!(seconds.abs() < f64::EPSILON);

    check(unsafe { offline_player_play(handle) }, "play");

    check(
        unsafe { offline_player_state(handle, &mut state) },
        "state after play",
    );

    assert_eq!(state, OfflinePlayerState::Playing);

    thread::sleep(Duration::from_millis(500));

    check(
        unsafe { offline_player_current_frame(handle, &mut frame) },
        "frame after play",
    );

    assert!(frame > 0);

    check(unsafe { offline_player_pause(handle) }, "pause");

    check(
        unsafe { offline_player_state(handle, &mut state) },
        "state after pause",
    );

    assert_eq!(state, OfflinePlayerState::Paused);

    let paused_frame = frame;

    thread::sleep(Duration::from_millis(250));

    check(
        unsafe { offline_player_current_frame(handle, &mut frame) },
        "frame while paused",
    );

    assert_eq!(frame, paused_frame);

    let target_frame = u64::from(sample_rate)
        .checked_mul(20)
        .expect("seek overflow");

    check(
        unsafe { offline_player_seek_to_frame(handle, target_frame) },
        "seek",
    );

    check(
        unsafe { offline_player_current_frame(handle, &mut frame) },
        "frame after seek",
    );

    assert_eq!(frame, target_frame);

    check(unsafe { offline_player_play(handle) }, "resume");

    thread::sleep(Duration::from_millis(500));

    check(
        unsafe { offline_player_current_frame(handle, &mut frame) },
        "frame after resume",
    );

    assert!(frame > target_frame);

    check(unsafe { offline_player_stop(handle) }, "stop");

    check(
        unsafe { offline_player_state(handle, &mut state) },
        "state after stop",
    );

    assert_eq!(state, OfflinePlayerState::Stopped);

    unsafe {
        offline_player_destroy(handle);
    }

    let _ = fs::remove_file(&db_path);
}
