//! `FgVad` —— ten-vad + 状态机 + 帧缓冲的对外入口。
//!
//! 设计要点：
//!
//! 1. **对外只认任意长度的 `&[i16]`**。ten-vad 要求固定帧长（256 样本 @ 16 kHz）。
//!    内部开 `pending` 缓冲，攒够 HOP 就跑一次。
//! 2. **不暴露 threshold / hop_size**。ten-vad 的概率阈值硬编码 0.5。
//! 3. **状态机始终在位**。未 `start()` 时停在 `Idle`，仍可拿到原始概率做可视化。
//! 4. **`Drop` 负责回收 ten-vad 句柄**。

use crate::state_machine::{Event, Mode, ShortModeConfig, State, StateMachine};
use crate::sys;

/// ten-vad 在 16 kHz 下要求每帧 256 样本。硬编码，不对外暴露。
const HOP_SIZE: usize = 256;
/// ten-vad 的概率二值化阈值。官方推荐 0.5，硬编码。
const THRESHOLD: f32 = 0.5;

/// 单帧 VAD 输出。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrameResult {
    /// ten-vad 输出的原始概率，范围 [0.0, 1.0]。
    pub probability: f32,
    /// 概率 ≥ 内部阈值时为 true。
    pub is_voice: bool,
    /// 本帧处理完后的状态机状态。
    pub state: State,
    /// 本帧触发的事件（若有）。
    pub event: Option<Event>,
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
    pending: Vec<i16>,
    state_machine: StateMachine,
}

impl FgVad {
    /// 使用默认模式创建（短时 + 默认计时）。未 `start()` 时状态机停在 `Idle`，
    /// `process` 仍会返回原始概率，便于"预览"使用。
    pub fn new() -> Result<Self, Error> {
        Self::with_mode(Mode::default())
    }

    /// 使用指定模式创建。
    pub fn with_mode(mode: Mode) -> Result<Self, Error> {
        let mut handle: sys::TenVadHandle = std::ptr::null_mut();
        let ret = unsafe { sys::ten_vad_create(&mut handle, HOP_SIZE, THRESHOLD) };
        if ret != 0 || handle.is_null() {
            return Err(Error::InitFailed);
        }
        let state_machine = match mode {
            Mode::Short(cfg) => StateMachine::new(cfg),
        };
        Ok(Self {
            handle,
            pending: Vec::with_capacity(HOP_SIZE * 4),
            state_machine,
        })
    }

    /// 便利构造器：短时模式 + 自定义计时。
    pub fn short(cfg: ShortModeConfig) -> Result<Self, Error> {
        Self::with_mode(Mode::Short(cfg))
    }

    /// 开启一次会话：状态机进入 `Detecting`，计时器清零。
    /// 可反复调用，每次都重开一次会话。
    pub fn start(&mut self) {
        self.state_machine.start();
    }

    /// 外部强制停止当前会话。状态机转入 `End(ExternalStop)`。
    /// Idle 或已 End 状态下调用无副作用。
    pub fn stop(&mut self) {
        self.state_machine.stop();
    }

    /// 清空内部缓冲和状态。下次使用前需再调 `start()`。
    pub fn reset(&mut self) {
        self.pending.clear();
        self.state_machine.reset();
    }

    /// 当前状态机状态。
    pub fn state(&self) -> State {
        self.state_machine.state()
    }

    /// 喂入任意长度的 16 kHz 单声道 i16 PCM。
    /// 返回本次调用中跑完的帧的 VAD 结果（可能为空）。
    ///
    /// 一旦状态机进入终态（`End(_)`），后续的 `process` 调用直接返回空 Vec；
    /// 需调用 `start()` 或 `reset()` 才能继续。
    pub fn process(&mut self, samples: &[i16]) -> Result<Vec<FrameResult>, Error> {
        if matches!(self.state_machine.state(), State::End(_)) {
            return Ok(Vec::new());
        }

        self.pending.extend_from_slice(samples);

        let available_frames = self.pending.len() / HOP_SIZE;
        let mut results = Vec::with_capacity(available_frames);
        let mut consumed = 0usize;
        let mut terminal = false;

        for i in 0..available_frames {
            if terminal {
                break;
            }
            let start = i * HOP_SIZE;
            let frame = &self.pending[start..start + HOP_SIZE];

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
            let is_voice = flag != 0;

            let event = self.state_machine.step(is_voice);
            let state = self.state_machine.state();
            if matches!(state, State::End(_)) {
                terminal = true;
            }

            consumed += HOP_SIZE;
            results.push(FrameResult {
                probability: prob,
                is_voice,
                state,
                event,
            });
        }

        self.pending.drain(..consumed);
        if terminal {
            // 会话已结束，丢弃此后剩余样本，避免混进下一次会话。
            self.pending.clear();
        }

        Ok(results)
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
    use crate::state_machine::{EndReason, ShortModeConfig};

    #[test]
    fn create_and_drop() {
        let _vad = FgVad::new().expect("create");
    }

    #[test]
    fn idle_without_start_but_process_still_returns_probability() {
        let mut vad = FgVad::new().expect("create");
        assert_eq!(vad.state(), State::Idle);
        let silence = vec![0i16; HOP_SIZE * 3];
        let out = vad.process(&silence).expect("process");
        assert_eq!(out.len(), 3);
        for r in &out {
            assert_eq!(r.state, State::Idle);
            assert!(r.event.is_none());
            assert!(!r.is_voice);
        }
    }

    #[test]
    fn start_puts_state_machine_into_detecting() {
        let mut vad = FgVad::new().expect("create");
        vad.start();
        assert_eq!(vad.state(), State::Detecting);
    }

    #[test]
    fn silence_after_start_triggers_head_timeout() {
        let cfg = ShortModeConfig {
            head_silence_timeout_ms: 100, // 7 帧
            ..Default::default()
        };
        let mut vad = FgVad::short(cfg).expect("create");
        vad.start();
        let silence = vec![0i16; HOP_SIZE * 10];
        let out = vad.process(&silence).expect("process");

        // 应该在第 7 帧触发 HeadSilenceTimeout 然后停
        assert!(out.len() == 7, "应处理 7 帧后停下，实得 {}", out.len());
        assert_eq!(
            out.last().unwrap().state,
            State::End(EndReason::HeadSilenceTimeout)
        );
        assert_eq!(out.last().unwrap().event, Some(Event::HeadSilenceTimeout));

        // End 后继续 process 应返回空
        let out2 = vad.process(&silence).expect("post-end");
        assert!(out2.is_empty());
    }

    #[test]
    fn partial_frame_is_buffered() {
        let mut vad = FgVad::new().expect("create");
        let half = vec![0i16; HOP_SIZE / 2];
        assert!(vad.process(&half).expect("h1").is_empty());
        assert_eq!(vad.process(&half).expect("h2").len(), 1);
    }

    #[test]
    fn reset_returns_state_to_idle() {
        let mut vad = FgVad::new().expect("create");
        vad.start();
        assert_eq!(vad.state(), State::Detecting);
        vad.reset();
        assert_eq!(vad.state(), State::Idle);
    }
}
