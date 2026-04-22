//! fgvad — intelligent VAD library.
//!
//! 当前阶段：最小安全封装。对外只暴露逐帧的 `probability` 与 `is_voice`，
//! 状态机、计时和事件会在后续 commit 加入。

#[cfg(target_os = "macos")]
pub mod sys;

#[cfg(target_os = "macos")]
mod vad;

#[cfg(target_os = "macos")]
pub use vad::{Error, FgVad, FrameResult};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// 读取底层 ten-vad 的版本字符串。
#[cfg(target_os = "macos")]
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

    #[cfg(target_os = "macos")]
    #[test]
    fn ten_vad_is_linked_and_reports_version() {
        let v = ten_vad_version();
        assert!(!v.is_empty(), "ten_vad_get_version 返回空字符串");
        println!("ten-vad version = {v}");
    }
}
