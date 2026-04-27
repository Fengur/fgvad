//! fgvad 的 C ABI 封装。
//!
//! 对外暴露与 `vad::FgVad` 等价的操作，但以 opaque handle + C 兼容枚举/结构体
//! 的形式。由 `cbindgen` 据此生成 `include/fgvad.h`，供 Swift / Obj-C / C / C++
//! 通过 bridging header 或直接 include 使用。
//!
//! 内存所有权约定：
//! - `fgvad_new_short` / `fgvad_new_long` 返回的 `*mut FgVad` 必须用 `fgvad_free` 释放；
//! - `fgvad_process` 返回的 `*mut FgVadResults` 必须用 `fgvad_results_free` 释放；
//! - `FgVadResultView` 里的指针在 `FgVadResults` 释放后失效，caller 若需长期
//!   持有须自行 memcpy。

use std::slice;

use crate::state_machine::{
    EndReason, Event, LongModeConfig, Mode, ShortModeConfig, State,
};
use crate::vad::{FgVad as RustFgVad, ResultType as RustResultType, VadResult};

// ———————— 公开给 C 的枚举（都用 u32） ————————

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum FgVadResultType {
    Silence = 0,
    SentenceStart = 1,
    Active = 2,
    SentenceEnd = 3,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum FgVadState {
    Idle = 0,
    Detecting = 1,
    Started = 2,
    Voiced = 3,
    Trailing = 4,
    End = 5,
}

/// 仅当 `state == FgVadState::End` 时有意义；否则为 `None_`。
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum FgVadEndReason {
    None_ = 0,
    SpeechCompleted = 1,
    HeadSilenceTimeout = 2,
    MaxDurationReached = 3,
    ExternalStop = 4,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum FgVadEvent {
    None_ = 0,
    SentenceStarted = 1,
    SentenceEnded = 2,
    SentenceForceCut = 3,
    HeadSilenceTimeout = 4,
    MaxDurationReached = 5,
}

// ———————— opaque 句柄 & 结果集 ————————

/// opaque 句柄（C 里只以 `struct FgVad *` 形式出现）。
pub struct FgVad {
    inner: RustFgVad,
}

/// opaque 结果集，内部持有 `Vec<VadResult>` 与逐帧概率 / is_voice 的 SoA 缓存
/// （方便 C 侧直接拿连续指针画波形）。
pub struct FgVadResults {
    items: Vec<VadResult>,
    probabilities: Vec<Vec<f32>>,
    is_voice_flags: Vec<Vec<u8>>,
}

impl FgVadResults {
    fn new(items: Vec<VadResult>) -> Self {
        let probabilities: Vec<Vec<f32>> = items
            .iter()
            .map(|r| r.frames.iter().map(|d| d.probability).collect())
            .collect();
        let is_voice_flags: Vec<Vec<u8>> = items
            .iter()
            .map(|r| r.frames.iter().map(|d| u8::from(d.is_voice)).collect())
            .collect();
        Self {
            items,
            probabilities,
            is_voice_flags,
        }
    }
}

/// 一条结果的只读视图。指针生命周期绑定 `FgVadResults`。
#[repr(C)]
pub struct FgVadResultView {
    pub result_type: FgVadResultType,
    /// 本段音频起始指针（Silence 段可能为空——此时 ptr 为空、len=0）。
    pub audio_ptr: *const i16,
    pub audio_len: usize,
    /// 本段覆盖的每 16ms 帧的 probability（连续数组）。
    pub probabilities_ptr: *const f32,
    /// 本段覆盖的每 16ms 帧的 is_voice（0 或 1）。
    pub is_voice_ptr: *const u8,
    pub frames_count: usize,
    pub event: FgVadEvent,
    pub state: FgVadState,
    pub end_reason: FgVadEndReason,
    pub is_sentence_begin: bool,
    pub is_sentence_end: bool,
    pub stream_offset_sample: u64,
}

// ———————— 枚举转换辅助 ————————

fn map_result_type(r: RustResultType) -> FgVadResultType {
    match r {
        RustResultType::Silence => FgVadResultType::Silence,
        RustResultType::SentenceStart => FgVadResultType::SentenceStart,
        RustResultType::Active => FgVadResultType::Active,
        RustResultType::SentenceEnd => FgVadResultType::SentenceEnd,
    }
}

fn map_state(s: State) -> (FgVadState, FgVadEndReason) {
    match s {
        State::Idle => (FgVadState::Idle, FgVadEndReason::None_),
        State::Detecting => (FgVadState::Detecting, FgVadEndReason::None_),
        State::Started => (FgVadState::Started, FgVadEndReason::None_),
        State::Voiced => (FgVadState::Voiced, FgVadEndReason::None_),
        State::Trailing => (FgVadState::Trailing, FgVadEndReason::None_),
        State::End(reason) => (FgVadState::End, map_end_reason(reason)),
    }
}

fn map_end_reason(r: EndReason) -> FgVadEndReason {
    match r {
        EndReason::SpeechCompleted => FgVadEndReason::SpeechCompleted,
        EndReason::HeadSilenceTimeout => FgVadEndReason::HeadSilenceTimeout,
        EndReason::MaxDurationReached => FgVadEndReason::MaxDurationReached,
        EndReason::ExternalStop => FgVadEndReason::ExternalStop,
    }
}

fn map_event(e: Option<Event>) -> FgVadEvent {
    match e {
        None => FgVadEvent::None_,
        Some(Event::SentenceStarted) => FgVadEvent::SentenceStarted,
        Some(Event::SentenceEnded) => FgVadEvent::SentenceEnded,
        Some(Event::SentenceForceCut) => FgVadEvent::SentenceForceCut,
        Some(Event::HeadSilenceTimeout) => FgVadEvent::HeadSilenceTimeout,
        Some(Event::MaxDurationReached) => FgVadEvent::MaxDurationReached,
    }
}

// ———————— 构造 / 释放 ————————

/// 创建短时模式实例。失败返回 NULL。
/// 参数单位：毫秒。
#[no_mangle]
pub extern "C" fn fgvad_new_short(
    head_silence_timeout_ms: u32,
    tail_silence_ms: u32,
    max_duration_ms: u32,
) -> *mut FgVad {
    let cfg = ShortModeConfig {
        head_silence_timeout_ms,
        tail_silence_ms,
        max_duration_ms,
    };
    match RustFgVad::with_mode(Mode::Short(cfg)) {
        Ok(v) => Box::into_raw(Box::new(FgVad { inner: v })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 创建长时模式实例。失败返回 NULL。
/// `max_session_duration_ms = 0` 表示会话时长不限。
#[no_mangle]
pub extern "C" fn fgvad_new_long(
    head_silence_timeout_ms: u32,
    max_sentence_duration_ms: u32,
    max_session_duration_ms: u32,
    tail_silence_ms_initial: u32,
    tail_silence_ms_min: u32,
    enable_dynamic_tail: bool,
) -> *mut FgVad {
    let cfg = LongModeConfig {
        head_silence_timeout_ms,
        max_sentence_duration_ms,
        max_session_duration_ms,
        tail_silence_ms_initial,
        tail_silence_ms_min,
        enable_dynamic_tail,
    };
    match RustFgVad::with_mode(Mode::Long(cfg)) {
        Ok(v) => Box::into_raw(Box::new(FgVad { inner: v })),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 释放 VAD 实例。接收 NULL 为 no-op。
#[no_mangle]
pub extern "C" fn fgvad_free(vad: *mut FgVad) {
    if !vad.is_null() {
        unsafe {
            drop(Box::from_raw(vad));
        }
    }
}

// ———————— 会话控制 ————————

#[no_mangle]
pub extern "C" fn fgvad_start(vad: *mut FgVad) {
    if let Some(v) = unsafe { vad.as_mut() } {
        v.inner.start();
    }
}

#[no_mangle]
pub extern "C" fn fgvad_stop(vad: *mut FgVad) {
    if let Some(v) = unsafe { vad.as_mut() } {
        v.inner.stop();
    }
}

#[no_mangle]
pub extern "C" fn fgvad_reset(vad: *mut FgVad) {
    if let Some(v) = unsafe { vad.as_mut() } {
        v.inner.reset();
    }
}

/// 查询当前状态机状态。NULL 返回 `Idle`。
#[no_mangle]
pub extern "C" fn fgvad_state(vad: *const FgVad) -> FgVadState {
    match unsafe { vad.as_ref() } {
        Some(v) => map_state(v.inner.state()).0,
        None => FgVadState::Idle,
    }
}

/// 查询终态原因（仅 `state == End` 时有意义）。
#[no_mangle]
pub extern "C" fn fgvad_end_reason(vad: *const FgVad) -> FgVadEndReason {
    match unsafe { vad.as_ref() } {
        Some(v) => map_state(v.inner.state()).1,
        None => FgVadEndReason::None_,
    }
}

// ———————— 处理与结果访问 ————————

/// 喂入 16 kHz mono i16 PCM。返回一个 opaque 结果集；
/// 失败（传 NULL、ten-vad 处理失败等）返回 NULL。
///
/// `sample_count` 为 0 时依然返回有效（空）结果集。
#[no_mangle]
pub extern "C" fn fgvad_process(
    vad: *mut FgVad,
    samples: *const i16,
    sample_count: usize,
) -> *mut FgVadResults {
    let v = match unsafe { vad.as_mut() } {
        Some(v) => v,
        None => return std::ptr::null_mut(),
    };
    let slice: &[i16] = if sample_count == 0 || samples.is_null() {
        &[]
    } else {
        unsafe { slice::from_raw_parts(samples, sample_count) }
    };
    match v.inner.process(slice) {
        Ok(items) => Box::into_raw(Box::new(FgVadResults::new(items))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn fgvad_results_free(results: *mut FgVadResults) {
    if !results.is_null() {
        unsafe {
            drop(Box::from_raw(results));
        }
    }
}

#[no_mangle]
pub extern "C" fn fgvad_results_count(results: *const FgVadResults) -> usize {
    match unsafe { results.as_ref() } {
        Some(r) => r.items.len(),
        None => 0,
    }
}

/// 按索引取一条结果的只读视图。越界或 NULL 返回全零视图。
/// 视图内所有指针的生命周期绑定到 `FgVadResults`；调用 `fgvad_results_free` 之后失效。
#[no_mangle]
pub extern "C" fn fgvad_result_view(
    results: *const FgVadResults,
    index: usize,
) -> FgVadResultView {
    let empty = FgVadResultView {
        result_type: FgVadResultType::Silence,
        audio_ptr: std::ptr::null(),
        audio_len: 0,
        probabilities_ptr: std::ptr::null(),
        is_voice_ptr: std::ptr::null(),
        frames_count: 0,
        event: FgVadEvent::None_,
        state: FgVadState::Idle,
        end_reason: FgVadEndReason::None_,
        is_sentence_begin: false,
        is_sentence_end: false,
        stream_offset_sample: 0,
    };
    let r = match unsafe { results.as_ref() } {
        Some(r) => r,
        None => return empty,
    };
    let item = match r.items.get(index) {
        Some(i) => i,
        None => return empty,
    };
    let (state, end_reason) = map_state(item.state);
    let probs = &r.probabilities[index];
    let flags = &r.is_voice_flags[index];
    FgVadResultView {
        result_type: map_result_type(item.result_type),
        audio_ptr: if item.audio.is_empty() {
            std::ptr::null()
        } else {
            item.audio.as_ptr()
        },
        audio_len: item.audio.len(),
        probabilities_ptr: if probs.is_empty() {
            std::ptr::null()
        } else {
            probs.as_ptr()
        },
        is_voice_ptr: if flags.is_empty() {
            std::ptr::null()
        } else {
            flags.as_ptr()
        },
        frames_count: item.frames.len(),
        event: map_event(item.event),
        state,
        end_reason,
        is_sentence_begin: item.is_sentence_begin,
        is_sentence_end: item.is_sentence_end,
        stream_offset_sample: item.stream_offset_sample,
    }
}

// ———————— 内部测试：用 extern "C" 路径打一遍 API ————————

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_short_mode_smoke() {
        // 创建
        let vad = fgvad_new_short(3000, 700, 30_000);
        assert!(!vad.is_null());
        // 未 start，state 应为 Idle
        let s = fgvad_state(vad);
        assert!(matches!(s, FgVadState::Idle));
        // 喂 256 样本静音，应出一段 Silence 结果
        let zeros = vec![0i16; 256 * 3];
        let results = fgvad_process(vad, zeros.as_ptr(), zeros.len());
        assert!(!results.is_null());
        let n = fgvad_results_count(results);
        assert_eq!(n, 1);
        let view = fgvad_result_view(results, 0);
        assert!(matches!(view.result_type, FgVadResultType::Silence));
        assert_eq!(view.frames_count, 3);
        assert!(!view.probabilities_ptr.is_null());
        // 清理
        fgvad_results_free(results);
        fgvad_free(vad);
    }

    #[test]
    fn long_mode_constructor() {
        let vad = fgvad_new_long(3000, 60_000, 0, 1000, 500, true);
        assert!(!vad.is_null());
        fgvad_start(vad);
        assert!(matches!(fgvad_state(vad), FgVadState::Detecting));
        fgvad_stop(vad);
        assert!(matches!(fgvad_state(vad), FgVadState::End));
        assert!(matches!(
            fgvad_end_reason(vad),
            FgVadEndReason::ExternalStop
        ));
        fgvad_free(vad);
    }

    #[test]
    fn null_handles_are_safe() {
        fgvad_free(std::ptr::null_mut());
        fgvad_results_free(std::ptr::null_mut());
        fgvad_start(std::ptr::null_mut());
        fgvad_stop(std::ptr::null_mut());
        fgvad_reset(std::ptr::null_mut());
        assert!(matches!(fgvad_state(std::ptr::null()), FgVadState::Idle));
        let out = fgvad_process(std::ptr::null_mut(), std::ptr::null(), 0);
        assert!(out.is_null());
    }
}
