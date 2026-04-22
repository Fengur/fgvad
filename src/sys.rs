//! 对 ten-vad C API 的最小 FFI 绑定。
//!
//! 和 `vendor/ten-vad/include/ten_vad.h` 一一对应，手写而非 bindgen，
//! 因为表面积极小（4 个函数），手写更可读、也少一个构建期依赖。

use std::os::raw::{c_char, c_float, c_int};

pub type TenVadHandle = *mut std::ffi::c_void;

#[link(name = "ten_vad", kind = "framework")]
extern "C" {
    pub fn ten_vad_create(
        handle: *mut TenVadHandle,
        hop_size: usize,
        threshold: c_float,
    ) -> c_int;

    pub fn ten_vad_process(
        handle: TenVadHandle,
        audio_data: *const i16,
        audio_data_length: usize,
        out_probability: *mut c_float,
        out_flag: *mut c_int,
    ) -> c_int;

    pub fn ten_vad_destroy(handle: *mut TenVadHandle) -> c_int;

    pub fn ten_vad_get_version() -> *const c_char;
}
