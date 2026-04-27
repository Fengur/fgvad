//! `FgVad` —— ten-vad + 状态机 + 角色切分的对外入口。
//!
//! ## 设计要点
//!
//! 1. 对外只认任意长度的 `&[i16]`；ten-vad 固定 256 样本/帧的要求由内部缓冲吸收。
//! 2. 不暴露 ten-vad 的 threshold / hop_size（硬编码）。
//! 3. 状态机始终在位。未 `start()` 时停在 `Idle`，`process` 仍可返回 Silence 段做可视化。
//! 4. 输出带角色标签的 `VadResult`：`Silence` / `SentenceStart` / `Active` / `SentenceEnd`。
//! 5. `SentenceStart` 在 Silence→Active 转换**那一刻独立发**，带 250ms pre-roll。
//! 6. Trailing 折叠进 Active；会话因 SpeechCompleted 结束时，Trailing 作为 SentenceEnd 的 tail padding。
//! 7. 子 chunk 切分：caller 一个输入若跨越角色边界或终态，输出多个 `VadResult`。
//! 8. `Drop` 回收 ten-vad 句柄。

use std::collections::VecDeque;

use crate::state_machine::{
    EndReason, Event, LongModeConfig, Mode, ShortModeConfig, State, StateMachine,
};
use crate::sys;

const HOP_SIZE: usize = 256;
/// ten-vad / Silero 业界默认 —— prob > THRESHOLD 即候选 voice 帧。
/// 噪声环境下对 pop 尖峰的抗性**不靠调这个值**，而是靠状态机层的多帧回退投票
/// (`RESUME_CONFIRM_FRAMES`)，防止单帧 spike 打乱 tail_silence 累积。
const THRESHOLD: f32 = 0.5;
/// pre-roll 帧数：对应 250ms（`ceil(250 / 16) = 16`）。
const PRE_ROLL_FRAMES: usize = 16;

// ———————— 对外类型 ————————

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FrameDiag {
    pub probability: f32,
    pub is_voice: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResultType {
    Silence,
    SentenceStart,
    Active,
    SentenceEnd,
}

#[derive(Debug, Clone)]
pub struct VadResult {
    pub audio: Vec<i16>,
    pub result_type: ResultType,
    pub frames: Vec<FrameDiag>,
    pub event: Option<Event>,
    pub state: State,
    pub is_sentence_begin: bool,
    pub is_sentence_end: bool,
    pub stream_offset_sample: u64,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("ten-vad 初始化失败")]
    InitFailed,
    #[error("ten-vad 处理单帧失败")]
    ProcessFailed,
}

// ———————— 内部辅助类型 ————————

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum SegmentRole {
    Silence,
    Active,
}

struct Segment {
    role: SegmentRole,
    audio: Vec<i16>,
    frames: Vec<FrameDiag>,
    start_offset: u64,
    latest_event: Option<Event>,
    latest_state: State,
}

impl Segment {
    fn new(role: SegmentRole, start_offset: u64, initial_state: State) -> Self {
        Self {
            role,
            audio: Vec::new(),
            frames: Vec::new(),
            start_offset,
            latest_event: None,
            latest_state: initial_state,
        }
    }

    fn is_empty(&self) -> bool {
        self.frames.is_empty()
    }
}

struct FrameBundle {
    audio: [i16; HOP_SIZE],
    diag: FrameDiag,
}

// ———————— FgVad ————————

pub struct FgVad {
    handle: sys::TenVadHandle,
    pending: Vec<i16>,
    state_machine: StateMachine,
    pre_roll: VecDeque<FrameBundle>,
    stream_samples: u64,
    segment: Option<Segment>,
}

impl FgVad {
    pub fn new() -> Result<Self, Error> {
        Self::with_mode(Mode::default())
    }

    pub fn with_mode(mode: Mode) -> Result<Self, Error> {
        let mut handle: sys::TenVadHandle = std::ptr::null_mut();
        let ret = unsafe { sys::ten_vad_create(&mut handle, HOP_SIZE, THRESHOLD) };
        if ret != 0 || handle.is_null() {
            return Err(Error::InitFailed);
        }
        Ok(Self {
            handle,
            pending: Vec::with_capacity(HOP_SIZE * 4),
            state_machine: StateMachine::new(mode),
            pre_roll: VecDeque::with_capacity(PRE_ROLL_FRAMES),
            stream_samples: 0,
            segment: None,
        })
    }

    pub fn short(cfg: ShortModeConfig) -> Result<Self, Error> {
        Self::with_mode(Mode::Short(cfg))
    }

    pub fn long(cfg: LongModeConfig) -> Result<Self, Error> {
        Self::with_mode(Mode::Long(cfg))
    }

    pub fn start(&mut self) {
        self.state_machine.start();
        self.stream_samples = 0;
        self.segment = None;
        self.pre_roll.clear();
    }

    pub fn stop(&mut self) {
        self.state_machine.stop();
    }

    pub fn reset(&mut self) {
        self.pending.clear();
        self.pre_roll.clear();
        self.state_machine.reset();
        self.stream_samples = 0;
        self.segment = None;
    }

    pub fn state(&self) -> State {
        self.state_machine.state()
    }

    pub fn process(&mut self, samples: &[i16]) -> Result<Vec<VadResult>, Error> {
        if matches!(self.state_machine.state(), State::End(_)) {
            return Ok(Vec::new());
        }

        self.pending.extend_from_slice(samples);
        let mut results = Vec::new();
        let mut terminal = false;

        while self.pending.len() >= HOP_SIZE && !terminal {
            let mut frame = [0i16; HOP_SIZE];
            frame.copy_from_slice(&self.pending[..HOP_SIZE]);
            self.pending.drain(..HOP_SIZE);

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
            let diag = FrameDiag {
                probability: prob,
                is_voice: flag != 0,
            };

            let event = self.state_machine.step(diag.is_voice);
            let new_state = self.state_machine.state();
            let prev_role = self.segment.as_ref().map(|s| s.role);
            let new_role = role_for(new_state, event, prev_role);

            let frame_offset = self.stream_samples;

            // Silence → Active：此帧触发 SentenceStart；立即把当前段 flush（Silence），
            // 然后用 pre-roll + 当前帧组装并 emit SentenceStart，当前帧"被 SentenceStart 吃掉"。
            if prev_role != Some(SegmentRole::Active) && new_role == SegmentRole::Active {
                if let Some(seg) = self.segment.take() {
                    if !seg.is_empty() {
                        results.push(finalize_silence(seg));
                    }
                }

                let pre_roll_sample_count = (self.pre_roll.len() * HOP_SIZE) as u64;
                let mut audio = Vec::with_capacity((self.pre_roll.len() + 1) * HOP_SIZE);
                let mut frames_vec = Vec::with_capacity(self.pre_roll.len() + 1);
                for b in &self.pre_roll {
                    audio.extend_from_slice(&b.audio);
                    frames_vec.push(b.diag);
                }
                audio.extend_from_slice(&frame);
                frames_vec.push(diag);

                let start_offset = frame_offset.saturating_sub(pre_roll_sample_count);
                results.push(VadResult {
                    audio,
                    result_type: ResultType::SentenceStart,
                    frames: frames_vec,
                    event,
                    state: new_state,
                    is_sentence_begin: true,
                    is_sentence_end: false,
                    stream_offset_sample: start_offset,
                });

                // 当前帧已在 SentenceStart 里输出；开一个全新的空 Active 段供后续帧累加。
                self.segment = Some(Segment::new(
                    SegmentRole::Active,
                    frame_offset + HOP_SIZE as u64,
                    new_state,
                ));
                self.push_pre_roll(frame, diag);
                self.stream_samples += HOP_SIZE as u64;

                // 极罕见：同一帧同时触发 SentenceStart 和终态——补一个空 SentenceEnd 标记。
                if matches!(new_state, State::End(_)) {
                    terminal = true;
                    self.segment = None;
                    results.push(VadResult {
                        audio: Vec::new(),
                        result_type: ResultType::SentenceEnd,
                        frames: Vec::new(),
                        event: None,
                        state: new_state,
                        is_sentence_begin: false,
                        is_sentence_end: true,
                        stream_offset_sample: self.stream_samples,
                    });
                }
                continue;
            }

            // 其它角色切换（Active → Silence，短时模式罕见但保留）
            if let Some(pr) = prev_role {
                if pr != new_role {
                    let old = self.segment.take().unwrap();
                    results.push(finalize_by_role(old, false));
                    self.segment = Some(Segment::new(new_role, frame_offset, new_state));
                }
            } else {
                self.segment = Some(Segment::new(new_role, frame_offset, new_state));
            }

            {
                let seg = self.segment.as_mut().unwrap();
                seg.audio.extend_from_slice(&frame);
                seg.frames.push(diag);
                seg.latest_state = new_state;
                if event.is_some() {
                    seg.latest_event = event;
                }
            }

            self.push_pre_roll(frame, diag);
            self.stream_samples += HOP_SIZE as u64;

            if matches!(new_state, State::End(_)) {
                terminal = true;
                if let Some(seg) = self.segment.take() {
                    results.push(finalize_by_role(seg, true));
                }
            }
        }

        // 非终态、chunk 边界：flush 当前段让调用方及时拿到进度，
        // 同时保留"同一角色继续累加"的上下文。
        if !terminal {
            if let Some(seg) = self.segment.take() {
                if !seg.is_empty() {
                    let role = seg.role;
                    let state = seg.latest_state;
                    let next_offset = seg.start_offset + seg.audio.len() as u64;
                    // 长时模式里，若本段以 SentenceEnded/ForceCut 结束，不要延续
                    // 为下一段的起始——让下一帧（Silence）自己开 Silence 段。
                    let ended_sentence = matches!(
                        seg.latest_event,
                        Some(Event::SentenceEnded) | Some(Event::SentenceForceCut)
                    );
                    results.push(finalize_by_role(seg, false));
                    if !ended_sentence {
                        self.segment = Some(Segment::new(role, next_offset, state));
                    }
                } else {
                    self.segment = Some(seg);
                }
            }
        }

        if terminal {
            self.pending.clear();
        }

        Ok(results)
    }

    fn push_pre_roll(&mut self, audio: [i16; HOP_SIZE], diag: FrameDiag) {
        self.pre_roll.push_back(FrameBundle { audio, diag });
        while self.pre_roll.len() > PRE_ROLL_FRAMES {
            self.pre_roll.pop_front();
        }
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

/// 依状态与事件判定帧的角色。
///
/// 长时模式下 `SentenceEnded` / `SentenceForceCut` 事件伴随 state 回到
/// `Detecting`，但**该帧本身是上一句的最后一帧**，语义上属 Active。
/// 短时终态按"往哪里去"推断：SpeechCompleted 来自 Trailing（Active），
/// HeadSilenceTimeout 来自 Detecting（Silence），其它继承当前段。
fn role_for(state: State, event: Option<Event>, prev_role: Option<SegmentRole>) -> SegmentRole {
    if matches!(
        event,
        Some(Event::SentenceEnded) | Some(Event::SentenceForceCut)
    ) {
        return SegmentRole::Active;
    }
    match state {
        State::Voiced | State::Trailing => SegmentRole::Active,
        State::End(reason) => match reason {
            EndReason::SpeechCompleted => SegmentRole::Active,
            EndReason::HeadSilenceTimeout => SegmentRole::Silence,
            EndReason::MaxDurationReached | EndReason::ExternalStop => {
                prev_role.unwrap_or(SegmentRole::Silence)
            }
        },
        _ => SegmentRole::Silence,
    }
}

fn finalize_silence(seg: Segment) -> VadResult {
    VadResult {
        audio: seg.audio,
        result_type: ResultType::Silence,
        frames: seg.frames,
        event: seg.latest_event,
        state: seg.latest_state,
        is_sentence_begin: false,
        is_sentence_end: false,
        stream_offset_sample: seg.start_offset,
    }
}

/// 把一个段转成 VadResult。`terminal=true` 表示会话终态；
/// 长时模式里 `SentenceEnded` / `SentenceForceCut` 也会让 Active 段
/// 发成 `SentenceEnd`（即便 session 未终结）。
fn finalize_by_role(seg: Segment, terminal: bool) -> VadResult {
    match seg.role {
        SegmentRole::Silence => finalize_silence(seg),
        SegmentRole::Active => {
            let ended_by_event = matches!(
                seg.latest_event,
                Some(Event::SentenceEnded) | Some(Event::SentenceForceCut)
            );
            let ended_by_terminal = terminal && matches!(seg.latest_state, State::End(_));
            let is_end = ended_by_event || ended_by_terminal;
            VadResult {
                audio: seg.audio,
                result_type: if is_end {
                    ResultType::SentenceEnd
                } else {
                    ResultType::Active
                },
                frames: seg.frames,
                event: seg.latest_event,
                state: seg.latest_state,
                is_sentence_begin: false,
                is_sentence_end: is_end,
                stream_offset_sample: seg.start_offset,
            }
        }
    }
}

// ———————— 单测 ————————

#[cfg(test)]
mod tests {
    use super::*;

    fn silence(n_frames: usize) -> Vec<i16> {
        vec![0i16; n_frames * HOP_SIZE]
    }

    #[test]
    fn create_and_drop() {
        let _vad = FgVad::new().expect("create");
    }

    #[test]
    fn idle_returns_silence() {
        let mut vad = FgVad::new().expect("create");
        let out = vad.process(&silence(5)).expect("process");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].result_type, ResultType::Silence);
        assert_eq!(out[0].state, State::Idle);
        assert_eq!(out[0].frames.len(), 5);
    }

    #[test]
    fn head_silence_timeout_emits_silence_with_event() {
        let cfg = ShortModeConfig {
            head_silence_timeout_ms: 100, // 7 帧
            ..Default::default()
        };
        let mut vad = FgVad::short(cfg).expect("create");
        vad.start();
        let out = vad.process(&silence(15)).expect("process");

        let last = out.last().unwrap();
        assert_eq!(last.state, State::End(EndReason::HeadSilenceTimeout));
        assert_eq!(last.event, Some(Event::HeadSilenceTimeout));
        assert_eq!(last.result_type, ResultType::Silence);

        assert!(vad.process(&silence(5)).expect("post-end").is_empty());
    }

    #[test]
    fn partial_frame_buffers() {
        let mut vad = FgVad::new().expect("create");
        let half = vec![0i16; HOP_SIZE / 2];
        assert!(vad.process(&half).expect("h1").is_empty());
        let out = vad.process(&half).expect("h2");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].frames.len(), 1);
    }

    #[test]
    fn chunk_boundary_flushes_within_same_role() {
        let mut vad = FgVad::new().expect("create");
        vad.start();
        let out1 = vad.process(&silence(3)).expect("c1");
        let out2 = vad.process(&silence(3)).expect("c2");
        assert_eq!(out1.len(), 1);
        assert_eq!(out2.len(), 1);
        // offset 连续
        assert_eq!(
            out1[0].stream_offset_sample + (out1[0].frames.len() * HOP_SIZE) as u64,
            out2[0].stream_offset_sample
        );
    }

    #[test]
    fn reset_clears_state() {
        let mut vad = FgVad::new().expect("create");
        vad.start();
        vad.process(&silence(3)).expect("process");
        vad.reset();
        assert_eq!(vad.state(), State::Idle);
        assert_eq!(vad.stream_samples, 0);
    }

    #[test]
    fn stop_marks_external_stop() {
        let mut vad = FgVad::new().expect("create");
        vad.start();
        vad.process(&silence(1)).expect("p");
        vad.stop();
        assert_eq!(vad.state(), State::End(EndReason::ExternalStop));
    }
}
