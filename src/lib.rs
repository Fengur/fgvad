//! fgvad — intelligent VAD library.
//!
//! 在 ten-vad 之上叠加状态机和动态端点策略。当前 ten-vad 链接支持
//! macOS、iOS 和 Android 三个平台；其他平台只编出 state machine（无 FFI）。

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
pub(crate) mod sys;

pub mod state_machine;

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
mod vad;

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
pub mod ffi;

pub use state_machine::{EndReason, Event, LongModeConfig, Mode, ShortModeConfig, State};

#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
pub use vad::{Error, FgVad, FrameDiag, ResultType, VadResult};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// 读取底层 ten-vad 的版本字符串。
#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
pub fn ten_vad_version() -> String {
    use std::ffi::CStr;
    unsafe {
        let ptr = sys::ten_vad_get_version();
        if ptr.is_null() {
            return String::new();
        }
        CStr::from_ptr(ptr).to_string_lossy().into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_matches_cargo() {
        assert_eq!(version(), env!("CARGO_PKG_VERSION"));
    }

    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
    #[test]
    fn ten_vad_is_linked_and_reports_version() {
        let v = ten_vad_version();
        assert!(!v.is_empty(), "ten_vad_get_version 返回空字符串");
        println!("ten-vad version = {v}");
    }
}
