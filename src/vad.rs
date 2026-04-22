//! `FgVad` —— ten-vad 的安全 Rust 封装。
//!
//! 设计要点：
//!
//! 1. **对外只认任意长度的 `&[i16]`**。ten-vad 要求固定帧长（256 样本 @ 16 kHz），
//!    这是实现细节，不应泄漏给调用方。内部开一个 `pending` 缓冲，攒够 HOP 就跑一次。
//! 2. **不暴露 threshold**。ten-vad 的概率阈值是实现约定，硬编码 0.5。真有必要
//!    再包成 `Sensitivity::{Low, Normal, High}`。
//! 3. **不暴露 hop_size**。上面一条的直接结果。
//! 4. **`Drop` 负责回收句柄**。
//!
//! 本模块只做"逐帧概率"这层；状态机 / 计时 / 事件会在后续 commit 叠加在 `FgVad` 之上。

use crate::sys;

/// ten-vad 在 16 kHz 下要求每帧 256 样本（16 ms）。写死在库里，不对外暴露。
const HOP_SIZE: usize = 256;

/// ten-vad 的二值化阈值。0.5 是官方推荐，硬编码。
const THRESHOLD: f32 = 0.5;

/// 单帧 VAD 结果。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrameResult {
    /// ten-vad 输出的原始概率，范围 [0.0, 1.0]。
    pub probability: f32,
    /// 概率 ≥ 内部阈值时为 true。
    pub is_voice: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("ten-vad 初始化失败")]
    InitFailed,
    #[error("ten-vad 处理单帧失败")]
    ProcessFailed,
}

pub struct FgVad {
    handle: sys::TenVadHandle,
    /// 累积但还没凑够 HOP_SIZE 的样本。
    pending: Vec<i16>,
}

impl FgVad {
    /// 创建一个 VAD 实例。采样率固定 16 kHz。
    pub fn new() -> Result<Self, Error> {
        let mut handle: sys::TenVadHandle = std::ptr::null_mut();
        let ret = unsafe { sys::ten_vad_create(&mut handle, HOP_SIZE, THRESHOLD) };
        if ret != 0 || handle.is_null() {
            return Err(Error::InitFailed);
        }
        Ok(Self {
            handle,
            pending: Vec::with_capacity(HOP_SIZE * 4),
        })
    }

    /// 喂入任意长度的 16 kHz 单声道 i16 PCM 样本，
    /// 返回本次调用内凑出的所有完整帧的 VAD 结果（可能为空）。
    pub fn process(&mut self, samples: &[i16]) -> Result<Vec<FrameResult>, Error> {
        if samples.is_empty() && self.pending.len() < HOP_SIZE {
            return Ok(Vec::new());
        }

        self.pending.extend_from_slice(samples);

        let frame_count = self.pending.len() / HOP_SIZE;
        let mut results = Vec::with_capacity(frame_count);

        for i in 0..frame_count {
            let start = i * HOP_SIZE;
            let end = start + HOP_SIZE;
            let frame = &self.pending[start..end];

            let mut prob: f32 = 0.0;
            let mut flag: i32 = 0;
            let ret = unsafe {
                sys::ten_vad_process(
                    self.handle,
                    frame.as_ptr(),
                    HOP_SIZE,
                    &mut prob,
                    &mut flag,
                )
            };
            if ret != 0 {
                return Err(Error::ProcessFailed);
            }
            results.push(FrameResult {
                probability: prob,
                is_voice: flag != 0,
            });
        }

        // 丢掉已消费部分，保留尾巴未满一帧的样本
        let consumed = frame_count * HOP_SIZE;
        self.pending.drain(..consumed);

        Ok(results)
    }

    /// 清空内部缓冲。不重建 ten-vad 句柄，也不重置 ten-vad 内部状态。
    pub fn reset(&mut self) {
        self.pending.clear();
    }
}

impl Drop for FgVad {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                let _ = sys::ten_vad_destroy(&mut self.handle);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_and_drop() {
        let _vad = FgVad::new().expect("ten-vad 应可创建");
        // drop 时应无 panic
    }

    #[test]
    fn silence_produces_low_probability() {
        let mut vad = FgVad::new().expect("create");
        let silence = vec![0i16; HOP_SIZE * 5];
        let out = vad.process(&silence).expect("process");
        assert_eq!(out.len(), 5, "应产出 5 帧结果");
        for r in &out {
            assert!(
                r.probability < 0.3,
                "静音帧概率应明显低：{}",
                r.probability
            );
            assert!(!r.is_voice, "静音帧不该判为 voice");
        }
    }

    #[test]
    fn partial_frame_is_buffered() {
        let mut vad = FgVad::new().expect("create");
        // 喂一半帧
        let half = vec![0i16; HOP_SIZE / 2];
        let out = vad.process(&half).expect("half");
        assert!(out.is_empty(), "未凑够一帧时不应返回结果");

        // 再喂一半，应得 1 帧
        let out = vad.process(&half).expect("rest");
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn process_splits_multi_frame_input() {
        let mut vad = FgVad::new().expect("create");
        let buf = vec![0i16; HOP_SIZE * 3 + 100]; // 3 整帧 + 尾巴
        let out = vad.process(&buf).expect("multi");
        assert_eq!(out.len(), 3, "应跑出 3 帧");
    }
}
