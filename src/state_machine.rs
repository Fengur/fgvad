//! 短时模式状态机。
//!
//! 纯逻辑，不依赖底层 VAD；输入是二值化后的 `is_voice` 帧序列，
//! 输出每帧之后的状态和（若有）触发的事件。测试可脱离 ten-vad 独立跑。

const SAMPLE_RATE: u32 = 16_000;
const HOP_SAMPLES: u32 = 256;
/// 每帧的时长（毫秒）：`256 * 1000 / 16_000 = 16`。
pub(crate) const FRAME_MS: u32 = HOP_SAMPLES * 1000 / SAMPLE_RATE;

/// `Started → Voiced` 所需的连续语音帧数（含触发帧本身）。
/// 3 帧 ≈ 48 ms，足以滤掉偶发的单帧误触，对延迟的影响几乎感知不到。
const CONFIRM_FRAMES: u32 = 3;

/// 短时模式的计时参数。
#[derive(Debug, Clone, Copy)]
pub struct ShortModeConfig {
    /// 开始后连续多久没检测到人声就放弃（单位 ms）。
    pub head_silence_timeout_ms: u32,
    /// 后端点阈值：进入说话后，尾部静音达此时长即判定本句结束（ms）。
    pub tail_silence_ms: u32,
    /// 单次会话的最大总时长（ms），超过即强制截断。
    pub max_duration_ms: u32,
}

impl Default for ShortModeConfig {
    fn default() -> Self {
        Self {
            head_silence_timeout_ms: 3000,
            tail_silence_ms: 700,
            max_duration_ms: 30_000,
        }
    }
}

/// 顶层模式选择。后续 `Long(LongModeConfig)` 会在独立 commit 加入。
#[derive(Debug, Clone, Copy)]
pub enum Mode {
    Short(ShortModeConfig),
}

impl Default for Mode {
    fn default() -> Self {
        Mode::Short(ShortModeConfig::default())
    }
}

/// 状态机的可见状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// 未 `start()`，或已 `reset()`。
    Idle,
    /// 已开始，等待人声出现；计头部静音。
    Detecting,
    /// 第一帧语音已到，正在确认是否稳定开口（过渡态，通常几十毫秒）。
    Started,
    /// 确认开口，主体说话中。
    Voiced,
    /// 说话暂停，尾部静音计时中；随时可能回 `Voiced`。
    Trailing,
    /// 会话终结，附带终结原因。
    End(EndReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndReason {
    /// 正常完成：尾部静音达阈值。
    SpeechCompleted,
    /// 头部静音超时，没人开口。
    HeadSilenceTimeout,
    /// 总时长达上限被强制截断。
    MaxDurationReached,
    /// 调用方主动 `stop()`。
    ExternalStop,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    /// `Started → Voiced` 那一帧触发。业务侧可据此启动识别、动 UI。
    SentenceStarted,
    /// 尾静音达阈值、正常结束时触发。
    SentenceEnded,
    /// 头部超时，会话结束。
    HeadSilenceTimeout,
    /// 总时长达上限，会话结束。
    MaxDurationReached,
}

pub(crate) struct StateMachine {
    config: ShortModeConfig,
    state: State,
    /// 在 `Detecting` 中连续非语音帧数；`Started → Detecting` 撤销时保留不清零。
    detecting_silent_frames: u32,
    /// 在 `Started` 中已累计的连续语音帧数。
    started_voice_frames: u32,
    /// 在 `Trailing` 中累计的连续非语音帧数。
    trailing_silent_frames: u32,
    /// 自 `start()` 起的总帧数。
    session_frames: u32,
}

impl StateMachine {
    pub(crate) fn new(config: ShortModeConfig) -> Self {
        Self {
            config,
            state: State::Idle,
            detecting_silent_frames: 0,
            started_voice_frames: 0,
            trailing_silent_frames: 0,
            session_frames: 0,
        }
    }

    pub(crate) fn state(&self) -> State {
        self.state
    }

    pub(crate) fn start(&mut self) {
        self.state = State::Detecting;
        self.clear_counters();
    }

    pub(crate) fn reset(&mut self) {
        self.state = State::Idle;
        self.clear_counters();
    }

    pub(crate) fn stop(&mut self) {
        if !matches!(self.state, State::Idle | State::End(_)) {
            self.state = State::End(EndReason::ExternalStop);
        }
    }

    fn clear_counters(&mut self) {
        self.detecting_silent_frames = 0;
        self.started_voice_frames = 0;
        self.trailing_silent_frames = 0;
        self.session_frames = 0;
    }

    /// 推进一帧。返回本帧触发的事件（若有）。
    pub(crate) fn step(&mut self, is_voice: bool) -> Option<Event> {
        if matches!(self.state, State::Idle | State::End(_)) {
            return None;
        }

        self.session_frames += 1;

        // 全局时长上限：任何非终态下只要撞上就 End。
        let max_frames = ms_to_frames(self.config.max_duration_ms);
        if self.session_frames >= max_frames {
            self.state = State::End(EndReason::MaxDurationReached);
            return Some(Event::MaxDurationReached);
        }

        match self.state {
            State::Detecting => self.step_detecting(is_voice),
            State::Started => self.step_started(is_voice),
            State::Voiced => self.step_voiced(is_voice),
            State::Trailing => self.step_trailing(is_voice),
            State::Idle | State::End(_) => unreachable!(),
        }
    }

    fn step_detecting(&mut self, is_voice: bool) -> Option<Event> {
        if is_voice {
            self.state = State::Started;
            self.started_voice_frames = 1;
            None
        } else {
            self.detecting_silent_frames += 1;
            let head_frames = ms_to_frames(self.config.head_silence_timeout_ms);
            if self.detecting_silent_frames >= head_frames {
                self.state = State::End(EndReason::HeadSilenceTimeout);
                Some(Event::HeadSilenceTimeout)
            } else {
                None
            }
        }
    }

    fn step_started(&mut self, is_voice: bool) -> Option<Event> {
        if is_voice {
            self.started_voice_frames += 1;
            if self.started_voice_frames >= CONFIRM_FRAMES {
                self.state = State::Voiced;
                Some(Event::SentenceStarted)
            } else {
                None
            }
        } else {
            // 假触发：回 Detecting，保留之前积累的 head 静音帧数——
            // 反正"那不是人声"，视作 head 静音阶段的一段小插曲。
            self.state = State::Detecting;
            self.started_voice_frames = 0;
            None
        }
    }

    fn step_voiced(&mut self, is_voice: bool) -> Option<Event> {
        if !is_voice {
            self.state = State::Trailing;
            self.trailing_silent_frames = 1;
        }
        None
    }

    fn step_trailing(&mut self, is_voice: bool) -> Option<Event> {
        if is_voice {
            self.state = State::Voiced;
            self.trailing_silent_frames = 0;
            None
        } else {
            self.trailing_silent_frames += 1;
            let tail_frames = ms_to_frames(self.config.tail_silence_ms);
            if self.trailing_silent_frames >= tail_frames {
                self.state = State::End(EndReason::SpeechCompleted);
                Some(Event::SentenceEnded)
            } else {
                None
            }
        }
    }
}

/// 毫秒 → 帧数，向上取整（至少要覆盖指定时长）。
fn ms_to_frames(ms: u32) -> u32 {
    (ms + FRAME_MS - 1) / FRAME_MS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sm(cfg: ShortModeConfig) -> StateMachine {
        StateMachine::new(cfg)
    }

    fn feed(sm: &mut StateMachine, pattern: &[bool]) -> Vec<Option<Event>> {
        pattern.iter().map(|&v| sm.step(v)).collect()
    }

    #[test]
    fn idle_before_start() {
        let s = sm(Default::default());
        assert_eq!(s.state(), State::Idle);
    }

    #[test]
    fn step_in_idle_is_noop() {
        let mut s = sm(Default::default());
        assert_eq!(s.step(true), None);
        assert_eq!(s.step(false), None);
        assert_eq!(s.state(), State::Idle);
    }

    #[test]
    fn start_goes_to_detecting() {
        let mut s = sm(Default::default());
        s.start();
        assert_eq!(s.state(), State::Detecting);
    }

    #[test]
    fn head_silence_timeout() {
        let cfg = ShortModeConfig {
            head_silence_timeout_ms: 100, // 7 帧
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::HeadSilenceTimeout));
        assert_eq!(s.state(), State::End(EndReason::HeadSilenceTimeout));
    }

    #[test]
    fn confirmation_frames_then_sentence_started() {
        let mut s = sm(Default::default());
        s.start();
        assert_eq!(s.step(true), None); // Detecting -> Started
        assert_eq!(s.state(), State::Started);
        assert_eq!(s.step(true), None); // Started (2/3)
        assert_eq!(s.step(true), Some(Event::SentenceStarted)); // -> Voiced
        assert_eq!(s.state(), State::Voiced);
    }

    #[test]
    fn false_trigger_reverts_without_event() {
        let mut s = sm(Default::default());
        s.start();
        s.step(true); // Started
        s.step(false); // 回 Detecting
        assert_eq!(s.state(), State::Detecting);
        // 再正常说话仍能触发
        let events = feed(&mut s, &[true, true, true]);
        assert_eq!(events[2], Some(Event::SentenceStarted));
        assert_eq!(s.state(), State::Voiced);
    }

    #[test]
    fn voiced_to_trailing_and_back() {
        let mut s = sm(Default::default());
        s.start();
        feed(&mut s, &[true, true, true]); // -> Voiced
        s.step(false); // -> Trailing
        assert_eq!(s.state(), State::Trailing);
        s.step(true); // -> Voiced
        assert_eq!(s.state(), State::Voiced);
    }

    #[test]
    fn tail_silence_ends_sentence() {
        let cfg = ShortModeConfig {
            tail_silence_ms: 100, // 7 帧
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        feed(&mut s, &[true, true, true]); // -> Voiced
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::SentenceEnded));
        assert_eq!(s.state(), State::End(EndReason::SpeechCompleted));
    }

    #[test]
    fn max_duration_ends_session() {
        let cfg = ShortModeConfig {
            max_duration_ms: 100, // 7 帧
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        let events: Vec<_> = (0..7).map(|_| s.step(true)).collect();
        assert_eq!(events[6], Some(Event::MaxDurationReached));
        assert_eq!(s.state(), State::End(EndReason::MaxDurationReached));
    }

    #[test]
    fn external_stop_marks_end() {
        let mut s = sm(Default::default());
        s.start();
        feed(&mut s, &[true, true, true]);
        s.stop();
        assert_eq!(s.state(), State::End(EndReason::ExternalStop));
    }

    #[test]
    fn stop_from_idle_is_noop() {
        let mut s = sm(Default::default());
        s.stop();
        assert_eq!(s.state(), State::Idle);
    }

    #[test]
    fn ms_to_frames_ceils() {
        assert_eq!(ms_to_frames(0), 0);
        assert_eq!(ms_to_frames(1), 1);
        assert_eq!(ms_to_frames(16), 1);
        assert_eq!(ms_to_frames(17), 2);
        assert_eq!(ms_to_frames(100), 7); // 6.25 -> 7
        assert_eq!(ms_to_frames(700), 44); // 43.75 -> 44
    }
}
