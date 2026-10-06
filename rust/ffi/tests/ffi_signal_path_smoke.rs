//! Signal-path FFI export smoke test.
//!
//! Exercises the ADDITIVE `offline_player_signal_path` export on a fresh,
//! empty library (nothing loaded) without touching any audio device, so it
//! runs on CI hosts. The populated path is covered by the integration/UI
//! tests that actually load a track.

use std::{
    env, fs,
    mem::MaybeUninit,
    ptr,
};

use offline_player_ffi::{
    offline_player_create, offline_player_destroy, offline_player_signal_path,
    OfflinePlayerHandle, OfflinePlayerResult, OfflinePlayerSignalPath,
};

#[test]
fn signal_path_rejects_null_out() {
    // Null output pointer is caught before any handle work.
    let result =
        unsafe { offline_player_signal_path(ptr::null_mut(), ptr::null_mut()) };
    assert_eq!(result, OfflinePlayerResult::NullArgument);
}

#[test]
fn signal_path_not_found_when_nothing_loaded() {
    let db_path = env::temp_dir().join(format!(
        "offline-player-signal-path-smoke-{}.sqlite",
        std::process::id()
    ));
    let _ = fs::remove_file(&db_path);

    let db_path_c =
        std::ffi::CString::new(db_path.to_str().expect("temp db path is UTF-8"))
            .expect("db path has no NUL");

    let mut handle: *mut OfflinePlayerHandle = ptr::null_mut();
    assert_eq!(
        offline_player_create(db_path_c.as_ptr(), &mut handle),
        OfflinePlayerResult::Ok,
    );
    assert!(!handle.is_null());

    // No track has been loaded, so the engine has no signal path.
    let mut out = MaybeUninit::<OfflinePlayerSignalPath>::zeroed();
    let result = unsafe { offline_player_signal_path(handle, out.as_mut_ptr()) };
    assert_eq!(
        result,
        OfflinePlayerResult::NotFound,
        "signal path with nothing loaded must report NotFound",
    );

    unsafe { offline_player_destroy(handle) };
    let _ = fs::remove_file(&db_path);
}
