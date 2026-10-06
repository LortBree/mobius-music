//! Android-specific FFI exports: direct USB DAC control and hardware spike analysis.

#[cfg(target_os = "android")]
use std::os::raw::c_char;

#[cfg(target_os = "android")]
use crate::write_fixed_cstr;
use crate::OfflinePlayerResult;

#[cfg(target_os = "android")]
#[repr(C)]
pub struct OfflinePlayerUsbSpikeResult {
    pub success: u8,
    pub wrap_ok: u8,
    pub claim_ok: u8,
    pub altsetting_ok: u8,
    pub out_endpoint: u8,
    pub feedback_endpoint: u8,
    pub alt_setting: i32,
    pub packets_submitted: u64,
    pub packets_completed: u64,
    pub packets_error: u64,
    pub feedback_packets_read: u64,
    pub last_feedback_raw: u32,
    pub feedback_freq_khz: f64,
    pub duration_secs: f64,
    pub error_msg: [c_char; 256],
    pub descriptor_summary: [c_char; 2048],
}

#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "C" fn offline_player_run_usb_spike(
    fd: i32,
    vid: u16,
    pid: u16,
    target_interface: i32,
    duration_secs: u32,
    out_result: *mut OfflinePlayerUsbSpikeResult,
) -> OfflinePlayerResult {
    if out_result.is_null() {
        return OfflinePlayerResult::NullArgument;
    }

    let duration = std::time::Duration::from_secs(duration_secs.max(1) as u64);
    let res = offline_player_platform_android::usb_spike::spike::run_usb_spike(
        fd,
        vid,
        pid,
        target_interface,
        duration,
    );

    let target = &mut *out_result;
    target.success = if res.success { 1 } else { 0 };
    target.wrap_ok = if res.wrap_ok { 1 } else { 0 };
    target.claim_ok = if res.claim_ok { 1 } else { 0 };
    target.altsetting_ok = if res.altsetting_ok { 1 } else { 0 };
    target.out_endpoint = res.out_endpoint;
    target.feedback_endpoint = res.feedback_endpoint;
    target.alt_setting = res.alt_setting;
    target.packets_submitted = res.packets_submitted;
    target.packets_completed = res.packets_completed;
    target.packets_error = res.packets_error;
    target.feedback_packets_read = res.feedback_packets_read;
    target.last_feedback_raw = res.last_feedback_raw;
    target.feedback_freq_khz = res.feedback_freq_khz;
    target.duration_secs = res.duration_secs;

    target.error_msg = [0; 256];
    target.descriptor_summary = [0; 2048];

    if let Some(err) = res.error {
        let bytes = err.as_bytes();
        let len = bytes.len().min(255);
        for i in 0..len {
            target.error_msg[i] = bytes[i] as c_char;
        }
    }

    let summary_bytes = res.descriptor_summary.as_bytes();
    let sum_len = summary_bytes.len().min(2047);
    for i in 0..sum_len {
        target.descriptor_summary[i] = summary_bytes[i] as c_char;
    }

    OfflinePlayerResult::Ok
}

#[no_mangle]
pub unsafe extern "C" fn offline_player_set_usb_dac(
    fd: i32,
    vid: u16,
    pid: u16,
) -> OfflinePlayerResult {
    #[cfg(target_os = "android")]
    {
        if fd >= 0 {
            offline_player_platform_android::uac2_driver::set_active_usb_dac(Some(
                offline_player_platform_android::uac2_driver::UsbDacConfig { fd, vid, pid },
            ));
        } else {
            offline_player_platform_android::uac2_driver::set_active_usb_dac(None);
        }
        OfflinePlayerResult::Ok
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = (fd, vid, pid);
        OfflinePlayerResult::Ok
    }
}
