use std::{
    ffi::CString,
    ptr,
};

use offline_player_ffi::{
    offline_player_create, offline_player_destroy,
    offline_player_get_volume_normalization, offline_player_set_volume_normalization,
    offline_player_track_gain_db, OfflinePlayerHandle, OfflinePlayerResult,
};

const DB_PATH: &str = "/tmp/mobius-ffi-vol-norm-test.sqlite3";

fn create_player() -> *mut OfflinePlayerHandle {
    let db_path = CString::new(DB_PATH).expect("DB path must be valid CString");
    let mut handle: *mut OfflinePlayerHandle = ptr::null_mut();
    let result = unsafe { offline_player_create(db_path.as_ptr(), &mut handle) };
    assert_eq!(result, OfflinePlayerResult::Ok);
    assert!(!handle.is_null());
    handle
}

#[test]
fn volume_normalization_ffi_smoke() {
    let handle = create_player();

    // 1. Defaults to disabled (0)
    let mut enabled = 1u8;
    let res = unsafe { offline_player_get_volume_normalization(handle, &mut enabled) };
    assert_eq!(res, OfflinePlayerResult::Ok);
    assert_eq!(enabled, 0);

    // 2. Enable volume normalization
    let res = unsafe { offline_player_set_volume_normalization(handle, 1) };
    assert_eq!(res, OfflinePlayerResult::Ok);

    let mut enabled = 0u8;
    let res = unsafe { offline_player_get_volume_normalization(handle, &mut enabled) };
    assert_eq!(res, OfflinePlayerResult::Ok);
    assert_eq!(enabled, 1);

    // 3. Disable volume normalization
    let res = unsafe { offline_player_set_volume_normalization(handle, 0) };
    assert_eq!(res, OfflinePlayerResult::Ok);

    let mut enabled = 1u8;
    let res = unsafe { offline_player_get_volume_normalization(handle, &mut enabled) };
    assert_eq!(res, OfflinePlayerResult::Ok);
    assert_eq!(enabled, 0);

    // 4. Track gain dB when no track loaded returns 0.0
    let mut gain_db = 999.0f32;
    let res = unsafe { offline_player_track_gain_db(handle, &mut gain_db) };
    assert_eq!(res, OfflinePlayerResult::Ok);
    assert_eq!(gain_db, 0.0);

    // 5. Null argument returns error
    let res = unsafe { offline_player_get_volume_normalization(handle, ptr::null_mut()) };
    assert_eq!(res, OfflinePlayerResult::NullArgument);

    let res = unsafe { offline_player_track_gain_db(handle, ptr::null_mut()) };
    assert_eq!(res, OfflinePlayerResult::NullArgument);

    unsafe { offline_player_destroy(handle) };
}
