#ifndef OFFLINE_PLAYER_H
#define OFFLINE_PLAYER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OfflinePlayerHandle OfflinePlayerHandle;

const char *offline_player_version(void);

typedef enum OfflinePlayerState {
    OFFLINE_PLAYER_STATE_IDLE = 0,
    OFFLINE_PLAYER_STATE_LOADED = 1,
    OFFLINE_PLAYER_STATE_PLAYING = 2,
    OFFLINE_PLAYER_STATE_PAUSED = 3,
    OFFLINE_PLAYER_STATE_STOPPED = 4
} OfflinePlayerState;

typedef enum OfflinePlayerOutputMode {
    OFFLINE_PLAYER_OUTPUT_MODE_AUTO = 0,
    OFFLINE_PLAYER_OUTPUT_MODE_FIXED_44100 = 1,
    OFFLINE_PLAYER_OUTPUT_MODE_FIXED_48000 = 2,
    OFFLINE_PLAYER_OUTPUT_MODE_FIXED_96000 = 3
} OfflinePlayerOutputMode;

typedef enum OfflinePlayerResult {
    OFFLINE_PLAYER_RESULT_OK = 0,
    OFFLINE_PLAYER_RESULT_NULL_ARGUMENT = 1,
    OFFLINE_PLAYER_RESULT_INVALID_UTF8 = 2,
    OFFLINE_PLAYER_RESULT_INVALID_ARGUMENT = 3,
    OFFLINE_PLAYER_RESULT_NOT_FOUND = 4,
    OFFLINE_PLAYER_RESULT_LIBRARY_ERROR = 5,
    OFFLINE_PLAYER_RESULT_PLAYBACK_ERROR = 6,
    OFFLINE_PLAYER_RESULT_BUFFER_TOO_SMALL = 7,
    OFFLINE_PLAYER_RESULT_INTERNAL_ERROR = 8
} OfflinePlayerResult;

OfflinePlayerResult offline_player_create(
    const char *db_path,
    OfflinePlayerHandle **out_handle
);

void offline_player_destroy(OfflinePlayerHandle *handle);

OfflinePlayerResult offline_player_scan_directory(
    OfflinePlayerHandle *handle,
    const char *root_path,
    int64_t *out_scanned_assets,
    int64_t *out_ignored_files,
    int64_t *out_scan_errors,
    int64_t *out_persisted_assets
);

OfflinePlayerResult offline_player_library_track_count(
    OfflinePlayerHandle *handle,
    int64_t *out_count
);

OfflinePlayerResult offline_player_library_track_id_at(
    OfflinePlayerHandle *handle,
    int64_t index,
    int64_t *out_track_id
);

typedef struct OfflinePlayerTrackMetadata {
    int64_t track_id;
    char *title;
    size_t title_capacity;
    char *artist;
    size_t artist_capacity;
    char *album;
    size_t album_capacity;
    char *album_artist;
    size_t album_artist_capacity;
    char *composer;
    size_t composer_capacity;
    char *date;
    size_t date_capacity;
    char *genre;
    size_t genre_capacity;
    uint32_t track_number;
    uint32_t disc_number;
    uint8_t has_disc_number;
} OfflinePlayerTrackMetadata;

OfflinePlayerResult offline_player_library_track_metadata(
    OfflinePlayerHandle *handle,
    int64_t track_id,
    OfflinePlayerTrackMetadata *out_metadata
);

/*
 * Embedded/cached artwork for an arbitrary library track.
 *
 * First call with mime_type/data buffers set to NULL and capacities set to 0
 * to obtain mime_type_size and data_size. Then allocate both buffers and call
 * again. mime_type_size includes the terminating NUL byte.
 */
typedef struct OfflinePlayerTrackArtwork {
    int64_t track_id;
    char *mime_type;
    size_t mime_type_capacity;
    size_t mime_type_size;
    uint8_t *data;
    size_t data_capacity;
    size_t data_size;
} OfflinePlayerTrackArtwork;

OfflinePlayerResult offline_player_library_track_artwork(
    OfflinePlayerHandle *handle,
    int64_t track_id,
    OfflinePlayerTrackArtwork *out_artwork
);

OfflinePlayerResult offline_player_load_track(
    OfflinePlayerHandle *handle,
    int64_t track_id
);

OfflinePlayerResult offline_player_play(OfflinePlayerHandle *handle);
OfflinePlayerResult offline_player_pause(OfflinePlayerHandle *handle);
OfflinePlayerResult offline_player_stop(OfflinePlayerHandle *handle);

OfflinePlayerResult offline_player_seek_to_frame(
    OfflinePlayerHandle *handle,
    uint64_t frame
);

OfflinePlayerResult offline_player_set_output_mode(
    OfflinePlayerHandle *handle,
    int32_t mode
);

OfflinePlayerResult offline_player_output_mode(
    OfflinePlayerHandle *handle,
    OfflinePlayerOutputMode *out_mode
);

OfflinePlayerResult offline_player_set_volume(
    OfflinePlayerHandle *handle,
    float volume
);

OfflinePlayerResult offline_player_set_equalizer_gains(
    OfflinePlayerHandle *handle,
    const float *gains_db,
    size_t band_count
);

OfflinePlayerResult offline_player_state(
    OfflinePlayerHandle *handle,
    OfflinePlayerState *out_state
);

OfflinePlayerResult offline_player_current_frame(
    OfflinePlayerHandle *handle,
    uint64_t *out_frame
);

OfflinePlayerResult offline_player_current_source_frame(
    OfflinePlayerHandle *handle,
    uint64_t *out_frame
);

OfflinePlayerResult offline_player_current_seconds(
    OfflinePlayerHandle *handle,
    double *out_seconds
);

OfflinePlayerResult offline_player_duration_seconds(
    OfflinePlayerHandle *handle,
    double *out_seconds
);

OfflinePlayerResult offline_player_total_frames(
    OfflinePlayerHandle *handle,
    uint64_t *out_frames
);

OfflinePlayerResult offline_player_track_id(
    OfflinePlayerHandle *handle,
    int64_t *out_track_id
);

OfflinePlayerResult offline_player_track_asset_id(
    OfflinePlayerHandle *handle,
    int64_t *out_asset_id
);

OfflinePlayerResult offline_player_track_sample_rate(
    OfflinePlayerHandle *handle,
    uint32_t *out_sample_rate
);

OfflinePlayerResult offline_player_track_channels(
    OfflinePlayerHandle *handle,
    uint16_t *out_channels
);

OfflinePlayerResult offline_player_track_bits_per_sample(
    OfflinePlayerHandle *handle,
    uint16_t *out_bits
);

OfflinePlayerResult offline_player_track_path(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_title(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_artist(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_album(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_album_artist(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_composer(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_date(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_genre(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

OfflinePlayerResult offline_player_track_number(
    OfflinePlayerHandle *handle,
    uint32_t *out_track_number
);

OfflinePlayerResult offline_player_track_disc_number(
    OfflinePlayerHandle *handle,
    uint32_t *out_disc_number
);

typedef enum OfflinePlayerRepeatMode {
    OFFLINE_PLAYER_REPEAT_OFF = 0,
    OFFLINE_PLAYER_REPEAT_TRACK = 1,
    OFFLINE_PLAYER_REPEAT_QUEUE = 2
} OfflinePlayerRepeatMode;

OfflinePlayerResult offline_player_queue_set(
    OfflinePlayerHandle *handle,
    const int64_t *track_ids,
    size_t track_count
);

OfflinePlayerResult offline_player_queue_add(
    OfflinePlayerHandle *handle,
    int64_t track_id
);

OfflinePlayerResult offline_player_queue_clear(OfflinePlayerHandle *handle);

OfflinePlayerResult offline_player_queue_length(
    OfflinePlayerHandle *handle,
    size_t *out_length
);

OfflinePlayerResult offline_player_queue_track_id_at(
    OfflinePlayerHandle *handle,
    size_t index,
    int64_t *out_track_id
);

OfflinePlayerResult offline_player_queue_up_next_count(
    OfflinePlayerHandle *handle,
    size_t *out_count
);

OfflinePlayerResult offline_player_queue_reorder_segment(
    OfflinePlayerHandle *handle,
    size_t start,
    const int64_t *track_ids,
    size_t track_count
);

OfflinePlayerResult offline_player_queue_current_index(
    OfflinePlayerHandle *handle,
    size_t *out_index
);

OfflinePlayerResult offline_player_queue_current_track_id(
    OfflinePlayerHandle *handle,
    int64_t *out_track_id
);

OfflinePlayerResult offline_player_queue_set_repeat_mode(
    OfflinePlayerHandle *handle,
    int32_t mode
);

OfflinePlayerResult offline_player_queue_repeat_mode(
    OfflinePlayerHandle *handle,
    OfflinePlayerRepeatMode *out_mode
);

OfflinePlayerResult offline_player_queue_select(
    OfflinePlayerHandle *handle,
    size_t index
);

OfflinePlayerResult offline_player_queue_select_and_load(
    OfflinePlayerHandle *handle,
    size_t index
);

OfflinePlayerResult offline_player_queue_play_current(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_select_and_play(
    OfflinePlayerHandle *handle,
    size_t index
);

OfflinePlayerResult offline_player_queue_next(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_next_and_play(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_previous(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_previous_and_play(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_repeat_current_and_play(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_advance_and_play(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_queue_advance_if_at_end(
    OfflinePlayerHandle *handle
);

OfflinePlayerResult offline_player_last_error(
    OfflinePlayerHandle *handle,
    char *buffer,
    size_t capacity
);

#ifdef __cplusplus
}
#endif

#endif /* OFFLINE_PLAYER_H */
