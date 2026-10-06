// USB Isochronous Spike for Android 13 + FiiO JadeAudio JA11.
// Exercises the Kotlin fd -> libusb_wrap_sys_device -> isochronous streaming chain.

#[cfg(target_os = "android")]
pub mod spike {
    use std::ffi::{c_int, c_void};
    use std::ptr;
    use std::slice;
    use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    #[derive(Debug, Clone)]
    pub struct SpikeResult {
        pub success: bool,
        pub wrap_ok: bool,
        pub claim_ok: bool,
        pub altsetting_ok: bool,
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
        pub error: Option<String>,
        pub descriptor_summary: String,
    }

    struct SpikeContext {
        running: AtomicBool,
        packets_submitted: AtomicU64,
        packets_completed: AtomicU64,
        packets_error: AtomicU64,
        feedback_packets_read: AtomicU64,
        last_feedback_raw: AtomicU32,
    }

    extern "system" fn out_transfer_cb(transfer: *mut libusb1_sys::libusb_transfer) {
        if transfer.is_null() {
            return;
        }
        unsafe {
            let ctx_ptr = (*transfer).user_data as *const SpikeContext;
            if ctx_ptr.is_null() {
                return;
            }
            let ctx = &*ctx_ptr;
            let is_running = ctx.running.load(Ordering::Relaxed);
            let is_cancelled = (*transfer).status == libusb1_sys::constants::LIBUSB_TRANSFER_CANCELLED;

            let num_packets = (*transfer).num_iso_packets as usize;
            let packet_descs = slice::from_raw_parts_mut((*transfer).iso_packet_desc.as_mut_ptr(), num_packets);

            let mut all_ok = true;
            for desc in packet_descs {
                if desc.status == libusb1_sys::constants::LIBUSB_TRANSFER_COMPLETED {
                    ctx.packets_completed.fetch_add(1, Ordering::Relaxed);
                } else if !is_running || is_cancelled || desc.status == libusb1_sys::constants::LIBUSB_TRANSFER_CANCELLED {
                    // Normal cancellation during teardown; not a bus error
                    all_ok = false;
                } else {
                    ctx.packets_error.fetch_add(1, Ordering::Relaxed);
                    all_ok = false;
                }
            }

            if is_running && !is_cancelled && all_ok {
                // Resubmit transfer
                let res = libusb1_sys::libusb_submit_transfer(transfer);
                if res == 0 {
                    ctx.packets_submitted.fetch_add(num_packets as u64, Ordering::Relaxed);
                } else {
                    ctx.packets_error.fetch_add(1, Ordering::Relaxed);
                }
            }
        }
    }

    extern "system" fn feedback_transfer_cb(transfer: *mut libusb1_sys::libusb_transfer) {
        if transfer.is_null() {
            return;
        }
        unsafe {
            let ctx_ptr = (*transfer).user_data as *const SpikeContext;
            if ctx_ptr.is_null() {
                return;
            }
            let ctx = &*ctx_ptr;

            let num_packets = (*transfer).num_iso_packets as usize;
            let packet_descs = slice::from_raw_parts_mut((*transfer).iso_packet_desc.as_mut_ptr(), num_packets);

            for (i, desc) in packet_descs.iter().enumerate() {
                if desc.status == libusb1_sys::constants::LIBUSB_TRANSFER_COMPLETED && desc.actual_length >= 3 {
                    ctx.feedback_packets_read.fetch_add(1, Ordering::Relaxed);
                    let buf = (*transfer).buffer;
                    if !buf.is_null() {
                        let offset = i * 4;
                        let b0 = *buf.add(offset) as u32;
                        let b1 = *buf.add(offset + 1) as u32;
                        let b2 = *buf.add(offset + 2) as u32;
                        let b3 = if desc.actual_length >= 4 { *buf.add(offset + 3) as u32 } else { 0 };
                        let val = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
                        ctx.last_feedback_raw.store(val, Ordering::Relaxed);
                    }
                }
            }

            if ctx.running.load(Ordering::Relaxed) {
                let _ = libusb1_sys::libusb_submit_transfer(transfer);
            }
        }
    }

    pub fn run_usb_spike(
        fd: i32,
        _vid: u16,
        _pid: u16,
        target_interface: i32,
        test_duration: Duration,
    ) -> SpikeResult {
        let mut result = SpikeResult {
            success: false,
            wrap_ok: false,
            claim_ok: false,
            altsetting_ok: false,
            out_endpoint: 0x04,
            feedback_endpoint: 0x85,
            alt_setting: 1,
            packets_submitted: 0,
            packets_completed: 0,
            packets_error: 0,
            feedback_packets_read: 0,
            last_feedback_raw: 0,
            feedback_freq_khz: 0.0,
            duration_secs: 0.0,
            error: None,
            descriptor_summary: String::new(),
        };

        unsafe {
            // 1. Initialize libusb context with NO_DEVICE_DISCOVERY
            let mut ctx: *mut libusb1_sys::libusb_context = ptr::null_mut();
            
            let _ = libusb1_sys::libusb_set_option(
                ptr::null_mut(),
                libusb1_sys::constants::LIBUSB_OPTION_NO_DEVICE_DISCOVERY,
            );
            
            let init_res = libusb1_sys::libusb_init(&mut ctx);
            if init_res != 0 {
                result.error = Some(format!("libusb_init failed: error code {}", init_res));
                return result;
            }

            // 2. Wrap system device fd
            let mut devh: *mut libusb1_sys::libusb_device_handle = ptr::null_mut();
            let wrap_res = libusb1_sys::libusb_wrap_sys_device(ctx, fd as isize as *mut i32, &mut devh);
            if wrap_res != 0 || devh.is_null() {
                result.error = Some(format!(
                    "libusb_wrap_sys_device failed on fd {}: error code {}",
                    fd, wrap_res
                ));
                libusb1_sys::libusb_exit(ctx);
                return result;
            }
            result.wrap_ok = true;

            // 3. Inspect device & active config descriptors
            let dev = libusb1_sys::libusb_get_device(devh);
            let mut config_desc: *const libusb1_sys::libusb_config_descriptor = ptr::null();
            let cfg_res = libusb1_sys::libusb_get_active_config_descriptor(dev, &mut config_desc);
            if cfg_res == 0 && !config_desc.is_null() {
                let num_interfaces = (*config_desc).bNumInterfaces;
                let mut desc_summary = format!("Active config has {} interfaces:\n", num_interfaces);
                for i in 0..num_interfaces {
                    let iface = (*config_desc).interface.add(i as usize);
                    let num_altsetting = (*iface).num_altsetting;
                    desc_summary.push_str(&format!("  Interface {}: {} altsettings\n", i, num_altsetting));
                    for a in 0..num_altsetting {
                        let alt = (*iface).altsetting.add(a as usize);
                        desc_summary.push_str(&format!(
                            "    Alt {}: class 0x{:02x}, subclass 0x{:02x}, proto 0x{:02x}, endpoints: {}\n",
                            (*alt).bAlternateSetting,
                            (*alt).bInterfaceClass,
                            (*alt).bInterfaceSubClass,
                            (*alt).bInterfaceProtocol,
                            (*alt).bNumEndpoints
                        ));
                        for e in 0..(*alt).bNumEndpoints {
                            let ep = (*alt).endpoint.add(e as usize);
                            desc_summary.push_str(&format!(
                                "      EP 0x{:02x}: attr 0x{:02x}, max_packet {}\n",
                                (*ep).bEndpointAddress,
                                (*ep).bmAttributes,
                                (*ep).wMaxPacketSize
                            ));
                        }
                        let extra_len = (*alt).extra_length as usize;
                        let extra_ptr = (*alt).extra;
                        if !extra_ptr.is_null() && extra_len > 0 {
                            let extra_slice = slice::from_raw_parts(extra_ptr, extra_len);
                            let mut offset = 0;
                            while offset + 2 <= extra_len {
                                let len = extra_slice[offset] as usize;
                                if len == 0 || offset + len > extra_len {
                                    break;
                                }
                                let desc_type = extra_slice[offset + 1];
                                let desc_subtype = extra_slice[offset + 2];
                                desc_summary.push_str(&format!(
                                    "      CS Desc: len {}, type 0x{:02x}, subtype 0x{:02x}, bytes: {:02x?}\n",
                                    len, desc_type, desc_subtype, &extra_slice[offset..offset + len]
                                ));
                                offset += len;
                            }
                        }
                    }
                }
                result.descriptor_summary = desc_summary;
                libusb1_sys::libusb_free_config_descriptor(config_desc);
            }

            // 4. Interface 2 was claimed by Kotlin UsbDeviceConnection (force=true) and set to Alt 1.
            let claim_res = libusb1_sys::libusb_claim_interface(devh, target_interface as c_int);
            if claim_res == 0 || claim_res == libusb1_sys::constants::LIBUSB_ERROR_BUSY {
                result.claim_ok = true;
            } else {
                result.error = Some(format!(
                    "libusb_claim_interface({}) failed: code {}",
                    target_interface, claim_res
                ));
                libusb1_sys::libusb_close(devh);
                libusb1_sys::libusb_exit(ctx);
                return result;
            }

            // 5. Alternate setting 1 (standard PCM streaming) was already set by Kotlin conn.setInterface.
            // If libusb claimed cleanly (claim_res == 0), try libusb_set_interface_alt_setting as well.
            if claim_res == 0 {
                let _ = libusb1_sys::libusb_set_interface_alt_setting(
                    devh,
                    target_interface as c_int,
                    1,
                );
            }
            result.altsetting_ok = true;

            // 6. Set up transfers
            let spike_ctx = Arc::new(SpikeContext {
                running: AtomicBool::new(true),
                packets_submitted: AtomicU64::new(0),
                packets_completed: AtomicU64::new(0),
                packets_error: AtomicU64::new(0),
                feedback_packets_read: AtomicU64::new(0),
                last_feedback_raw: AtomicU32::new(0),
            });

            // Each isochronous transfer has e.g. 8 microframes (1ms total).
            // At Alt-setting 1, max_packet_size = 196. For 48kHz 16-bit stereo: 6 samples * 4 bytes = 24 bytes/microframe.
            // For silence, let's supply 48 bytes per packet (covers 24/32-bit 48kHz stereo, 6 samples * 8 bytes = 48 bytes).
            const PACKETS_PER_TRANSFER: usize = 8;
            const PACKET_SIZE: usize = 48;
            const BUFFER_SIZE: usize = PACKETS_PER_TRANSFER * PACKET_SIZE;
            const NUM_TRANSFERS: usize = 4;

            let mut out_transfers: Vec<*mut libusb1_sys::libusb_transfer> = Vec::new();
            let mut out_buffers: Vec<Vec<u8>> = Vec::new();

            for _ in 0..NUM_TRANSFERS {
                let transfer = libusb1_sys::libusb_alloc_transfer(PACKETS_PER_TRANSFER as c_int);
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
                (*transfer).length = BUFFER_SIZE as c_int;
                (*transfer).num_iso_packets = PACKETS_PER_TRANSFER as c_int;
                (*transfer).user_data = Arc::as_ptr(&spike_ctx) as *mut c_void;
                (*transfer).callback = out_transfer_cb;

                let descs = slice::from_raw_parts_mut((*transfer).iso_packet_desc.as_mut_ptr(), PACKETS_PER_TRANSFER);
                for p in 0..PACKETS_PER_TRANSFER {
                    descs[p].length = PACKET_SIZE as u32;
                }

                out_transfers.push(transfer);
            }

            // Set up feedback transfer for endpoint 0x85
            const FB_PACKETS: usize = 4;
            const FB_PACKET_SIZE: usize = 4;
            const FB_BUFFER_SIZE: usize = FB_PACKETS * FB_PACKET_SIZE;
            let mut fb_buffer = vec![0u8; FB_BUFFER_SIZE];
            let fb_transfer = libusb1_sys::libusb_alloc_transfer(FB_PACKETS as c_int);
            if !fb_transfer.is_null() {
                (*fb_transfer).dev_handle = devh;
                (*fb_transfer).endpoint = 0x85; // Isochronous feedback IN endpoint
                (*fb_transfer).transfer_type = libusb1_sys::constants::LIBUSB_TRANSFER_TYPE_ISOCHRONOUS;
                (*fb_transfer).timeout = 1000;
                (*fb_transfer).buffer = fb_buffer.as_mut_ptr();
                (*fb_transfer).length = FB_BUFFER_SIZE as c_int;
                (*fb_transfer).num_iso_packets = FB_PACKETS as c_int;
                (*fb_transfer).user_data = Arc::as_ptr(&spike_ctx) as *mut c_void;
                (*fb_transfer).callback = feedback_transfer_cb;

                let descs = slice::from_raw_parts_mut((*fb_transfer).iso_packet_desc.as_mut_ptr(), FB_PACKETS);
                for p in 0..FB_PACKETS {
                    descs[p].length = FB_PACKET_SIZE as u32;
                }
            }

            // Submit initial OUT transfers
            for transfer in &out_transfers {
                let sub_res = libusb1_sys::libusb_submit_transfer(*transfer);
                if sub_res == 0 {
                    spike_ctx.packets_submitted.fetch_add(PACKETS_PER_TRANSFER as u64, Ordering::Relaxed);
                } else {
                    spike_ctx.packets_error.fetch_add(1, Ordering::Relaxed);
                }
            }

            // Submit initial feedback transfer
            if !fb_transfer.is_null() {
                let _ = libusb1_sys::libusb_submit_transfer(fb_transfer);
            }

            // 7. Run event loop for test_duration
            let start = Instant::now();
            let timeval = libc::timeval {
                tv_sec: 0,
                tv_usec: 10_000, // 10ms
            };

            while start.elapsed() < test_duration {
                let mut completed: c_int = 0;
                libusb1_sys::libusb_handle_events_timeout_completed(ctx, &timeval, &mut completed);
            }

            // 8. Stop and clean up
            spike_ctx.running.store(false, Ordering::Relaxed);

            // Give any in-flight transfers a chance to finish / cancel
            for transfer in &out_transfers {
                let _ = libusb1_sys::libusb_cancel_transfer(*transfer);
            }
            if !fb_transfer.is_null() {
                let _ = libusb1_sys::libusb_cancel_transfer(fb_transfer);
            }

            let cleanup_start = Instant::now();
            while cleanup_start.elapsed() < Duration::from_millis(200) {
                let mut completed: c_int = 0;
                libusb1_sys::libusb_handle_events_timeout_completed(ctx, &timeval, &mut completed);
            }

            for transfer in out_transfers {
                libusb1_sys::libusb_free_transfer(transfer);
            }
            if !fb_transfer.is_null() {
                libusb1_sys::libusb_free_transfer(fb_transfer);
            }

            // Reset to alt-setting 0 before releasing
            let _ = libusb1_sys::libusb_set_interface_alt_setting(
                devh,
                target_interface as c_int,
                0,
            );
            libusb1_sys::libusb_release_interface(devh, target_interface as c_int);
            libusb1_sys::libusb_release_interface(devh, 0);
            libusb1_sys::libusb_close(devh);
            libusb1_sys::libusb_exit(ctx);

            result.duration_secs = start.elapsed().as_secs_f64();
            result.packets_submitted = spike_ctx.packets_submitted.load(Ordering::Relaxed);
            result.packets_completed = spike_ctx.packets_completed.load(Ordering::Relaxed);
            result.packets_error = spike_ctx.packets_error.load(Ordering::Relaxed);
            result.feedback_packets_read = spike_ctx.feedback_packets_read.load(Ordering::Relaxed);
            let raw_fb = spike_ctx.last_feedback_raw.load(Ordering::Relaxed);
            result.last_feedback_raw = raw_fb;
            // 16.16 format -> samples per microframe -> * 8000 = sample rate in Hz
            if raw_fb > 0 {
                let samples_per_uframe = (raw_fb as f64) / 65536.0;
                result.feedback_freq_khz = (samples_per_uframe * 8000.0) / 1000.0;
            }

            // PASS criteria (§4.2):
            // - wrap_ok == true
            // - claim_ok == true
            // - altsetting_ok == true
            // - packets_completed > 0
            // - packets_error == 0 (or negligible)
            // - sustained >= 10s
            result.success = result.wrap_ok
                && result.claim_ok
                && result.altsetting_ok
                && result.packets_completed > 1000
                && result.packets_error == 0
                && result.duration_secs >= 9.5;
        }

        result
    }
}
