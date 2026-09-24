use std::{ffi::CString, fs, path::Path, ptr};

use offline_player_ffi::{
    offline_player_create, offline_player_destroy, offline_player_library_track_count,
    offline_player_library_track_id_at, offline_player_queue_advance_and_play,
    offline_player_queue_clear, offline_player_queue_current_index,
    offline_player_queue_current_track_id, offline_player_queue_length,
    offline_player_queue_next_and_play, offline_player_queue_previous_and_play,
    offline_player_queue_repeat_current_and_play, offline_player_queue_select_and_load,
    offline_player_queue_set, offline_player_queue_set_repeat_mode, OfflinePlayerRepeatMode,
    OfflinePlayerResult,
};

const MUSIC_DIR: &str = "/Users/bree/Downloads/Music/44kHz";
const DB_PATH: &str = "/tmp/offline-player-ffi-queue-smoke.sqlite3";

fn assert_ok(result: OfflinePlayerResult, operation: &str) {
    assert_eq!(
        result,
        OfflinePlayerResult::Ok,
        "{operation} failed with {result:?}"
    );
}

unsafe fn queue_index(handle: *mut offline_player_ffi::OfflinePlayerHandle) -> usize {
    let mut value = 0usize;

    assert_ok(
        offline_player_queue_current_index(handle, &mut value),
        "queue_current_index",
    );

    value
}

unsafe fn queue_track_id(handle: *mut offline_player_ffi::OfflinePlayerHandle) -> i64 {
    let mut value = 0i64;

    assert_ok(
        offline_player_queue_current_track_id(handle, &mut value),
        "queue_current_track_id",
    );

    value
}

unsafe fn queue_length(handle: *mut offline_player_ffi::OfflinePlayerHandle) -> usize {
    let mut value = 0usize;

    assert_ok(
        offline_player_queue_length(handle, &mut value),
        "queue_length",
    );

    value
}

unsafe fn enumerate_track_ids(handle: *mut offline_player_ffi::OfflinePlayerHandle) -> Vec<i64> {
    let mut count = 0i64;

    assert_ok(
        offline_player_library_track_count(handle, &mut count),
        "library_track_count",
    );

    assert!(count >= 2, "expected at least two tracks, found {count}");

    let mut ids = Vec::with_capacity(count as usize);

    for index in 0..count {
        let mut track_id = 0i64;

        assert_ok(
            offline_player_library_track_id_at(handle, index, &mut track_id),
            "library_track_id_at",
        );

        ids.push(track_id);
    }

    ids
}

#[test]
fn ffi_queue_controls_work_end_to_end() {
    unsafe {
        let _ = fs::remove_file(DB_PATH);

        assert!(
            Path::new(MUSIC_DIR).is_dir(),
            "music directory does not exist: {MUSIC_DIR}"
        );

        let db_path = CString::new(DB_PATH).expect("db path must be valid CString");

        let mut handle = ptr::null_mut();

        assert_ok(
            offline_player_create(db_path.as_ptr(), &mut handle),
            "offline_player_create",
        );

        assert!(!handle.is_null());

        let mut scanned_assets = 0i64;
        let mut ignored_files = 0i64;
        let mut scan_errors = 0i64;
        let mut persisted_assets = 0i64;

        let music_path = CString::new(MUSIC_DIR).expect("music path must be valid CString");

        assert_ok(
            offline_player_ffi::offline_player_scan_directory(
                handle,
                music_path.as_ptr(),
                &mut scanned_assets,
                &mut ignored_files,
                &mut scan_errors,
                &mut persisted_assets,
            ),
            "offline_player_scan_directory",
        );

        assert_eq!(scan_errors, 0, "scan reported errors");
        assert!(
            persisted_assets >= 2,
            "expected at least two persisted assets, got {persisted_assets}"
        );

        let track_ids = enumerate_track_ids(handle);

        let first = track_ids[0];
        let second = track_ids[1];

        let queue_ids = [first, second];

        assert_ok(
            offline_player_queue_set(handle, queue_ids.as_ptr(), queue_ids.len()),
            "queue_set",
        );

        assert_eq!(queue_length(handle), 2);
        assert_eq!(queue_index(handle), 0);
        assert_eq!(queue_track_id(handle), first);

        // Explicitly select and load the second track.
        assert_ok(
            offline_player_queue_select_and_load(handle, 1),
            "queue_select_and_load(second)",
        );

        assert_eq!(queue_index(handle), 1);
        assert_eq!(queue_track_id(handle), second);

        // Previous-and-play should move back to the first track.
        assert_ok(
            offline_player_queue_previous_and_play(handle),
            "queue_previous_and_play",
        );

        assert_eq!(queue_index(handle), 0);
        assert_eq!(queue_track_id(handle), first);

        // Repeat-current-and-play should stay on the first track.
        assert_ok(
            offline_player_queue_repeat_current_and_play(handle),
            "queue_repeat_current_and_play",
        );

        assert_eq!(queue_index(handle), 0);
        assert_eq!(queue_track_id(handle), first);

        // Default repeat mode is Off, so next-and-play moves to second.
        assert_ok(
            offline_player_queue_next_and_play(handle),
            "queue_next_and_play",
        );

        assert_eq!(queue_index(handle), 1);
        assert_eq!(queue_track_id(handle), second);

        // Repeat Track should keep the current queue position.
        assert_ok(
            offline_player_queue_set_repeat_mode(handle, OfflinePlayerRepeatMode::Track as i32),
            "queue_set_repeat_mode(track)",
        );

        assert_ok(
            offline_player_queue_advance_and_play(handle),
            "queue_advance_and_play(track-repeat)",
        );

        assert_eq!(queue_index(handle), 1);
        assert_eq!(queue_track_id(handle), second);

        // Repeat Queue should wrap from the last track to the first.
        assert_ok(
            offline_player_queue_set_repeat_mode(handle, OfflinePlayerRepeatMode::Queue as i32),
            "queue_set_repeat_mode(queue-repeat)",
        );

        assert_ok(
            offline_player_queue_advance_and_play(handle),
            "queue_advance_and_play(queue-repeat)",
        );

        assert_eq!(queue_index(handle), 0);
        assert_eq!(queue_track_id(handle), first);

        // Clear must remove both the queue and current position.
        assert_ok(offline_player_queue_clear(handle), "queue_clear");

        assert_eq!(queue_length(handle), 0);

        let mut current_index = 0usize;

        assert_eq!(
            offline_player_queue_current_index(handle, &mut current_index,),
            OfflinePlayerResult::NotFound
        );

        offline_player_destroy(handle);

        let _ = fs::remove_file(DB_PATH);
    }
}
