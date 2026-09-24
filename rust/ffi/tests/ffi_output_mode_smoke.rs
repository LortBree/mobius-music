use std::{
    ffi::{CStr, CString},
    ptr,
};

use offline_player_ffi::{
    offline_player_create, offline_player_destroy, offline_player_last_error,
    offline_player_output_mode, offline_player_set_output_mode, OfflinePlayerHandle,
    OfflinePlayerOutputMode, OfflinePlayerResult,
};

const DB_PATH: &str = "/tmp/mobius-ffi-output-mode-test.sqlite3";

fn last_error(handle: *mut OfflinePlayerHandle) -> String {
    const CAPACITY: usize = 4096;

    let mut buffer = vec![0u8; CAPACITY];

    let result =
        unsafe { offline_player_last_error(handle, buffer.as_mut_ptr().cast(), buffer.len()) };

    if result != OfflinePlayerResult::Ok && result != OfflinePlayerResult::BufferTooSmall {
        return format!("unknown native error: {result:?}");
    }

    unsafe {
        CStr::from_ptr(buffer.as_ptr().cast())
            .to_string_lossy()
            .into_owned()
    }
}

fn create_player() -> *mut OfflinePlayerHandle {
    let db_path = CString::new(DB_PATH).expect("DB path must be valid CString");

    let mut handle: *mut OfflinePlayerHandle = ptr::null_mut();

    let result = unsafe { offline_player_create(db_path.as_ptr(), &mut handle) };

    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "offline_player_create failed: {result:?}"
    );

    assert!(
        !handle.is_null(),
        "offline_player_create returned null handle"
    );

    handle
}

fn assert_mode(handle: *mut OfflinePlayerHandle, expected: OfflinePlayerOutputMode) {
    let mut actual = OfflinePlayerOutputMode::Auto;

    let result = unsafe { offline_player_output_mode(handle, &mut actual) };

    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "offline_player_output_mode failed: {result:?}; error={}",
        last_error(handle),
    );

    assert_eq!(
        actual, expected,
        "unexpected output mode: expected {expected:?}, got {actual:?}"
    );
}

#[test]
fn ffi_output_mode_round_trip() {
    let handle = create_player();

    assert_mode(handle, OfflinePlayerOutputMode::Auto);

    let result = unsafe { offline_player_set_output_mode(handle, 1) };

    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "set 44.1 kHz failed: {result:?}; error={}",
        last_error(handle),
    );

    assert_mode(handle, OfflinePlayerOutputMode::Fixed44100);

    let result = unsafe { offline_player_set_output_mode(handle, 2) };

    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "set 48 kHz failed: {result:?}; error={}",
        last_error(handle),
    );

    assert_mode(handle, OfflinePlayerOutputMode::Fixed48000);

    let result = unsafe { offline_player_set_output_mode(handle, 3) };

    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "set 96 kHz failed: {result:?}; error={}",
        last_error(handle),
    );

    assert_mode(handle, OfflinePlayerOutputMode::Fixed96000);

    unsafe {
        offline_player_destroy(handle);
    }
}

#[test]
fn ffi_output_mode_rejects_invalid_value() {
    let handle = create_player();

    let result = unsafe { offline_player_set_output_mode(handle, 99) };

    assert_eq!(
        result,
        OfflinePlayerResult::InvalidArgument,
        "expected InvalidArgument, got {result:?}; error={}",
        last_error(handle),
    );

    unsafe {
        offline_player_destroy(handle);
    }
}

#[test]
fn ffi_output_mode_rejects_negative_value() {
    let handle = create_player();

    let result = unsafe { offline_player_set_output_mode(handle, -1) };

    assert_eq!(
        result,
        OfflinePlayerResult::InvalidArgument,
        "expected InvalidArgument, got {result:?}; error={}",
        last_error(handle),
    );

    unsafe {
        offline_player_destroy(handle);
    }
}
