//! 状态机：短时 / 长时两种模式，各自独立。
//!
//! 纯逻辑，不依赖底层 VAD；输入是二值化后的 `is_voice` 帧序列，
//! 输出每帧之后的状态和（若有）触发的事件。
//!
//! 模块对 `vad.rs` 暴露一个统一的 `StateMachine` 枚举，内部分派到
//! [`ShortStateMachine`] 或 [`LongStateMachine`]。

const SAMPLE_RATE: u32 = 16_000;
const HOP_SAMPLES: u32 = 256;
/// 每帧时长（毫秒）：`256 * 1000 / 16_000 = 16`。
pub(crate) const FRAME_MS: u32 = HOP_SAMPLES * 1000 / SAMPLE_RATE;

/// `Started → Voiced` 所需的连续语音帧数（含触发帧）。3 帧 ≈ 48 ms。
const CONFIRM_FRAMES: u32 = 3;

// ———————— 公开配置 ————————

/// 短时模式配置。
///
/// 短时 = 一次 `start()` 对应一句话；触达 `tail_silence_ms` 或 `max_duration_ms`
/// 或头部超时即结束整个会话。
#[derive(Debug, Clone, Copy)]
pub struct ShortModeConfig {
    /// 开始后连续多久没检测到人声就判头部超时结束（ms）。
    pub head_silence_timeout_ms: u32,
    /// 后端点：进入说话后，尾部静音达此时长即判本句结束（ms）。
    /// 短时模式下 = 会话结束。
    pub tail_silence_ms: u32,
    /// 单次会话最大总时长（ms），超过强制截断。
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

/// 长时模式配置。
///
/// 长时 = 一次 `start()` 对应一整段会话（典型：听写/口述/会议），
/// 会话内自动切分多句；只在外部 `stop()` 或撞 `max_session_duration_ms` 时才结束。
///
/// **动态后端点曲线**：一句话内部，随说话累积时长增加，尾部判停阈值按线性
/// 方式从 `tail_silence_ms_initial` 收紧到 `tail_silence_ms_min`，越久越严。
/// 这能在长句子里降低"说话人停顿过久不知道断句"的延迟，同时保护短句
/// 不被过早切断。
#[derive(Debug, Clone, Copy)]
pub struct LongModeConfig {
    /// 头部静音超时（ms）。**仅在首次开口前生效**；一旦说过一句，此后
    /// 句间无限静音都不会触发。0 表示禁用。
    pub head_silence_timeout_ms: u32,

    /// **单句最大时长**（ms）。兼做两件事：
    /// 1. 动态 tail 曲线的分母：`progress = 本句已说时长 / max_sentence_duration_ms`。
    ///    progress 越大，tail 越接近 `min`。
    /// 2. 强切阈值：单句撑到这个时长仍没自然 EOS，触发 `SentenceForceCut`，
    ///    立即切本句并进入下一句（会话继续）。
    pub max_sentence_duration_ms: u32,

    /// **整会话最大时长**（ms）。超过即 `End(MaxDurationReached)` 终结会话。
    /// 0 表示不限（需要 caller 自己 `stop()`）。
    pub max_session_duration_ms: u32,

    /// 动态 tail 曲线的 **起始值**：一句话刚开始时的 tail 阈值（ms），此时最宽容。
    /// 典型 1000ms，允许说话人自然停顿／思考。
    pub tail_silence_ms_initial: u32,

    /// 动态 tail 曲线的 **最小值**：收紧的下限（ms）。默认 500ms，避免
    /// 长句后期对换气（~300ms）误切。
    pub tail_silence_ms_min: u32,

    /// 是否启用动态 tail 曲线。false 时 tail 固定为 `tail_silence_ms_initial`。
    pub enable_dynamic_tail: bool,
}

impl Default for LongModeConfig {
    fn default() -> Self {
        Self {
            head_silence_timeout_ms: 3000,
            max_sentence_duration_ms: 60_000,
            max_session_duration_ms: 0, // 默认不限
            tail_silence_ms_initial: 1000,
            tail_silence_ms_min: 500,
            enable_dynamic_tail: true,
        }
    }
}

/// 顶层模式选择。
#[derive(Debug, Clone, Copy)]
pub enum Mode {
    Short(ShortModeConfig),
    Long(LongModeConfig),
}

impl Default for Mode {
    fn default() -> Self {
        Mode::Short(ShortModeConfig::default())
    }
}

// ———————— 公开状态/事件/终结原因 ————————

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// 未 `start()`，或已 `reset()`。
    Idle,
    /// 已开始，等待人声出现；计头部静音。
    Detecting,
    /// 第一帧语音已到，正在确认是否稳定开口（过渡态 ~48ms）。
    Started,
    /// 确认开口，主体说话中。
    Voiced,
    /// 说话暂停，尾部静音计时中；随时可能回 `Voiced`。
    Trailing,
    /// 会话终结，附带原因。
    End(EndReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndReason {
    /// 短时：尾部静音达阈值，一句自然结束即会话结束。长时不会进入此终态。
    SpeechCompleted,
    /// 首次开口前超时（长时模式仅在未见任何句子时触发）。
    HeadSilenceTimeout,
    /// 短时：单次会话超长；长时：整会话超长。
    MaxDurationReached,
    /// 调用方主动 `stop()`。
    ExternalStop,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    /// `Started → Voiced` 触发——一句话开始。
    SentenceStarted,
    /// 一句话自然结束（tail 达阈值）。短时：伴随会话终结；长时：下一句继续。
    SentenceEnded,
    /// **长时独有**：单句撞 `max_sentence_duration_ms` 被强制切断。
    /// 会话继续，状态机回到 `Detecting` 等下一句。
    SentenceForceCut,
    /// 头部超时。
    HeadSilenceTimeout,
    /// 整会话超长。
    MaxDurationReached,
}

// ———————— 对外 StateMachine 包装（枚举分派） ————————

pub(crate) enum StateMachine {
    Short(ShortStateMachine),
    Long(LongStateMachine),
}

impl StateMachine {
    pub(crate) fn new(mode: Mode) -> Self {
        match mode {
            Mode::Short(cfg) => Self::Short(ShortStateMachine::new(cfg)),
            Mode::Long(cfg) => Self::Long(LongStateMachine::new(cfg)),
        }
    }

    pub(crate) fn state(&self) -> State {
        match self {
            Self::Short(s) => s.state,
            Self::Long(l) => l.state,
        }
    }

    pub(crate) fn start(&mut self) {
        match self {
            Self::Short(s) => s.start(),
            Self::Long(l) => l.start(),
        }
    }

    pub(crate) fn reset(&mut self) {
        match self {
            Self::Short(s) => s.reset(),
            Self::Long(l) => l.reset(),
        }
    }

    pub(crate) fn stop(&mut self) {
        match self {
            Self::Short(s) => s.stop(),
            Self::Long(l) => l.stop(),
        }
    }

    pub(crate) fn step(&mut self, is_voice: bool) -> Option<Event> {
        match self {
            Self::Short(s) => s.step(is_voice),
            Self::Long(l) => l.step(is_voice),
        }
    }
}

// ———————— 短时状态机 ————————

pub(crate) struct ShortStateMachine {
    config: ShortModeConfig,
    state: State,
    detecting_silent_frames: u32,
    started_voice_frames: u32,
    trailing_silent_frames: u32,
    session_frames: u32,
}

impl ShortStateMachine {
    fn new(config: ShortModeConfig) -> Self {
        Self {
            config,
            state: State::Idle,
            detecting_silent_frames: 0,
            started_voice_frames: 0,
            trailing_silent_frames: 0,
            session_frames: 0,
        }
    }

    fn start(&mut self) {
        self.state = State::Detecting;
        self.clear_counters();
    }

    fn reset(&mut self) {
        self.state = State::Idle;
        self.clear_counters();
    }

    fn stop(&mut self) {
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

    fn step(&mut self, is_voice: bool) -> Option<Event> {
        if matches!(self.state, State::Idle | State::End(_)) {
            return None;
        }
        self.session_frames += 1;

        let max_frames = ms_to_frames(self.config.max_duration_ms);
        if self.session_frames >= max_frames {
            self.state = State::End(EndReason::MaxDurationReached);
            return Some(Event::MaxDurationReached);
        }

        match self.state {
            State::Detecting => {
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
            State::Started => {
                if is_voice {
                    self.started_voice_frames += 1;
                    if self.started_voice_frames >= CONFIRM_FRAMES {
                        self.state = State::Voiced;
                        Some(Event::SentenceStarted)
                    } else {
                        None
                    }
                } else {
                    // 假触发回 Detecting（保留 head 计时）
                    self.state = State::Detecting;
                    self.started_voice_frames = 0;
                    None
                }
            }
            State::Voiced => {
                if !is_voice {
                    self.state = State::Trailing;
                    self.trailing_silent_frames = 1;
                }
                None
            }
            State::Trailing => {
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
            State::Idle | State::End(_) => unreachable!(),
        }
    }
}

// ———————— 长时状态机 ————————

pub(crate) struct LongStateMachine {
    config: LongModeConfig,
    state: State,
    detecting_silent_frames: u32,
    started_voice_frames: u32,
    trailing_silent_frames: u32,
    session_frames: u32,
    /// 自本句 SentenceStarted 起累计的帧数（Voiced + Trailing 全算）。
    /// 动态 tail 曲线和 SentenceForceCut 都靠它。每次 SentenceEnded /
    /// SentenceForceCut 后清零。
    current_sentence_frames: u32,
    /// 是否见过任何一句话。true 后 head_silence_timeout 不再生效。
    has_seen_any_sentence: bool,
}

impl LongStateMachine {
    fn new(config: LongModeConfig) -> Self {
        Self {
            config,
            state: State::Idle,
            detecting_silent_frames: 0,
            started_voice_frames: 0,
            trailing_silent_frames: 0,
            session_frames: 0,
            current_sentence_frames: 0,
            has_seen_any_sentence: false,
        }
    }

    fn start(&mut self) {
        self.state = State::Detecting;
        self.clear_counters();
        self.has_seen_any_sentence = false;
    }

    fn reset(&mut self) {
        self.state = State::Idle;
        self.clear_counters();
        self.has_seen_any_sentence = false;
    }

    fn stop(&mut self) {
        if !matches!(self.state, State::Idle | State::End(_)) {
            self.state = State::End(EndReason::ExternalStop);
        }
    }

    fn clear_counters(&mut self) {
        self.detecting_silent_frames = 0;
        self.started_voice_frames = 0;
        self.trailing_silent_frames = 0;
        self.session_frames = 0;
        self.current_sentence_frames = 0;
    }

    fn clear_per_sentence(&mut self) {
        self.started_voice_frames = 0;
        self.trailing_silent_frames = 0;
        self.current_sentence_frames = 0;
        self.detecting_silent_frames = 0;
    }

    /// 依据当前句累计长度计算此刻的 tail 阈值（帧数）。
    fn current_tail_frames(&self) -> u32 {
        if !self.config.enable_dynamic_tail || self.config.max_sentence_duration_ms == 0 {
            return ms_to_frames(self.config.tail_silence_ms_initial);
        }
        let max_frames = ms_to_frames(self.config.max_sentence_duration_ms) as f32;
        let progress = (self.current_sentence_frames as f32 / max_frames).min(1.0);
        let dynamic_ms = self.config.tail_silence_ms_initial as f32 * (1.0 - progress);
        let clamped = dynamic_ms.max(self.config.tail_silence_ms_min as f32) as u32;
        ms_to_frames(clamped)
    }

    fn step(&mut self, is_voice: bool) -> Option<Event> {
        if matches!(self.state, State::Idle | State::End(_)) {
            return None;
        }
        self.session_frames += 1;

        // 整会话超时（仅在设置了 max_session_duration_ms 时生效）
        if self.config.max_session_duration_ms > 0 {
            let session_max = ms_to_frames(self.config.max_session_duration_ms);
            if self.session_frames >= session_max {
                self.state = State::End(EndReason::MaxDurationReached);
                return Some(Event::MaxDurationReached);
            }
        }

        match self.state {
            State::Detecting => {
                if is_voice {
                    self.state = State::Started;
                    self.started_voice_frames = 1;
                    None
                } else {
                    self.detecting_silent_frames += 1;
                    // 头部超时仅首次开口前有效
                    if !self.has_seen_any_sentence && self.config.head_silence_timeout_ms > 0 {
                        let head_frames = ms_to_frames(self.config.head_silence_timeout_ms);
                        if self.detecting_silent_frames >= head_frames {
                            self.state = State::End(EndReason::HeadSilenceTimeout);
                            return Some(Event::HeadSilenceTimeout);
                        }
                    }
                    None
                }
            }
            State::Started => {
                if is_voice {
                    self.started_voice_frames += 1;
                    if self.started_voice_frames >= CONFIRM_FRAMES {
                        self.state = State::Voiced;
                        self.current_sentence_frames = self.started_voice_frames;
                        self.has_seen_any_sentence = true;
                        Some(Event::SentenceStarted)
                    } else {
                        None
                    }
                } else {
                    self.state = State::Detecting;
                    self.started_voice_frames = 0;
                    None
                }
            }
            State::Voiced => {
                self.current_sentence_frames += 1;
                // 单句强切
                let max_sentence_frames = ms_to_frames(self.config.max_sentence_duration_ms);
                if max_sentence_frames > 0 && self.current_sentence_frames >= max_sentence_frames {
                    self.state = State::Detecting;
                    self.clear_per_sentence();
                    return Some(Event::SentenceForceCut);
                }
                if !is_voice {
                    self.state = State::Trailing;
                    self.trailing_silent_frames = 1;
                }
                None
            }
            State::Trailing => {
                self.current_sentence_frames += 1;
                // 单句强切
                let max_sentence_frames = ms_to_frames(self.config.max_sentence_duration_ms);
                if max_sentence_frames > 0 && self.current_sentence_frames >= max_sentence_frames {
                    self.state = State::Detecting;
                    self.clear_per_sentence();
                    return Some(Event::SentenceForceCut);
                }
                if is_voice {
                    self.state = State::Voiced;
                    self.trailing_silent_frames = 0;
                    return None;
                }
                self.trailing_silent_frames += 1;
                let tail_frames = self.current_tail_frames();
                if self.trailing_silent_frames >= tail_frames {
                    // 长时：一句结束，回 Detecting 听下一句
                    self.state = State::Detecting;
                    self.clear_per_sentence();
                    Some(Event::SentenceEnded)
                } else {
                    None
                }
            }
            State::Idle | State::End(_) => unreachable!(),
        }
    }
}

/// 毫秒 → 帧数，向上取整。
fn ms_to_frames(ms: u32) -> u32 {
    (ms + FRAME_MS - 1) / FRAME_MS
}

// ———————— 测试 ————————

#[cfg(test)]
mod short_tests {
    use super::*;

    fn sm(cfg: ShortModeConfig) -> ShortStateMachine {
        ShortStateMachine::new(cfg)
    }

    fn feed(sm: &mut ShortStateMachine, pattern: &[bool]) -> Vec<Option<Event>> {
        pattern.iter().map(|&v| sm.step(v)).collect()
    }

    #[test]
    fn idle_before_start() {
        let s = sm(Default::default());
        assert_eq!(s.state, State::Idle);
    }

    #[test]
    fn step_in_idle_is_noop() {
        let mut s = sm(Default::default());
        assert_eq!(s.step(true), None);
        assert_eq!(s.step(false), None);
        assert_eq!(s.state, State::Idle);
    }

    #[test]
    fn start_goes_to_detecting() {
        let mut s = sm(Default::default());
        s.start();
        assert_eq!(s.state, State::Detecting);
    }

    #[test]
    fn head_silence_timeout() {
        let cfg = ShortModeConfig {
            head_silence_timeout_ms: 100,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::HeadSilenceTimeout));
        assert_eq!(s.state, State::End(EndReason::HeadSilenceTimeout));
    }

    #[test]
    fn confirmation_frames_then_sentence_started() {
        let mut s = sm(Default::default());
        s.start();
        assert_eq!(s.step(true), None);
        assert_eq!(s.state, State::Started);
        assert_eq!(s.step(true), None);
        assert_eq!(s.step(true), Some(Event::SentenceStarted));
        assert_eq!(s.state, State::Voiced);
    }

    #[test]
    fn false_trigger_reverts_without_event() {
        let mut s = sm(Default::default());
        s.start();
        s.step(true);
        s.step(false);
        assert_eq!(s.state, State::Detecting);
        let events = feed(&mut s, &[true, true, true]);
        assert_eq!(events[2], Some(Event::SentenceStarted));
    }

    #[test]
    fn voiced_to_trailing_and_back() {
        let mut s = sm(Default::default());
        s.start();
        feed(&mut s, &[true, true, true]);
        s.step(false);
        assert_eq!(s.state, State::Trailing);
        s.step(true);
        assert_eq!(s.state, State::Voiced);
    }

    #[test]
    fn tail_silence_ends_sentence() {
        let cfg = ShortModeConfig {
            tail_silence_ms: 100,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        feed(&mut s, &[true, true, true]);
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::SentenceEnded));
        assert_eq!(s.state, State::End(EndReason::SpeechCompleted));
    }

    #[test]
    fn max_duration_ends_session() {
        let cfg = ShortModeConfig {
            max_duration_ms: 100,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        let events: Vec<_> = (0..7).map(|_| s.step(true)).collect();
        assert_eq!(events[6], Some(Event::MaxDurationReached));
        assert_eq!(s.state, State::End(EndReason::MaxDurationReached));
    }

    #[test]
    fn external_stop_marks_end() {
        let mut s = sm(Default::default());
        s.start();
        feed(&mut s, &[true, true, true]);
        s.stop();
        assert_eq!(s.state, State::End(EndReason::ExternalStop));
    }

    #[test]
    fn ms_to_frames_ceils() {
        assert_eq!(ms_to_frames(0), 0);
        assert_eq!(ms_to_frames(1), 1);
        assert_eq!(ms_to_frames(16), 1);
        assert_eq!(ms_to_frames(17), 2);
        assert_eq!(ms_to_frames(100), 7);
        assert_eq!(ms_to_frames(700), 44);
    }
}

#[cfg(test)]
mod long_tests {
    use super::*;

    fn sm(cfg: LongModeConfig) -> LongStateMachine {
        LongStateMachine::new(cfg)
    }

    /// 长时模式：一句自然结束后 state 回 Detecting，session 未终结。
    #[test]
    fn sentence_ended_returns_to_detecting() {
        let cfg = LongModeConfig {
            tail_silence_ms_initial: 100, // 7 帧
            tail_silence_ms_min: 100,
            enable_dynamic_tail: false,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        // 3 帧确认开口 -> Voiced
        for _ in 0..3 {
            s.step(true);
        }
        assert_eq!(s.state, State::Voiced);
        // 7 帧静音 -> SentenceEnded，回 Detecting
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::SentenceEnded));
        assert_eq!(s.state, State::Detecting);
        // session 仍可继续
        s.step(true); // 又开口
        assert_eq!(s.state, State::Started);
    }

    /// 长时模式：两句话连续，SentenceStarted 应发两次，SentenceEnded 也两次。
    #[test]
    fn multi_sentence_flow() {
        let cfg = LongModeConfig {
            tail_silence_ms_initial: 100, // 7 帧
            tail_silence_ms_min: 100,
            enable_dynamic_tail: false,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();

        let mut starts = 0;
        let mut ends = 0;
        let mut feed = |s: &mut LongStateMachine, v: bool| {
            if let Some(ev) = s.step(v) {
                match ev {
                    Event::SentenceStarted => starts += 1,
                    Event::SentenceEnded => ends += 1,
                    _ => {}
                }
            }
        };
        // 第 1 句：3 帧语音 + 7 帧静音
        for _ in 0..3 {
            feed(&mut s, true);
        }
        for _ in 0..7 {
            feed(&mut s, false);
        }
        // 第 2 句：3 帧语音 + 7 帧静音
        for _ in 0..3 {
            feed(&mut s, true);
        }
        for _ in 0..7 {
            feed(&mut s, false);
        }

        assert_eq!(starts, 2);
        assert_eq!(ends, 2);
        assert_eq!(s.state, State::Detecting);
    }

    /// 长时：句间静音再长也不会触发 HeadSilenceTimeout（首句过后豁免）。
    #[test]
    fn head_timeout_only_before_first_sentence() {
        let cfg = LongModeConfig {
            head_silence_timeout_ms: 100, // 7 帧
            tail_silence_ms_initial: 100,
            tail_silence_ms_min: 100,
            enable_dynamic_tail: false,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        // 首句：3 voice + 7 silent -> SentenceEnded
        for _ in 0..3 {
            s.step(true);
        }
        for _ in 0..7 {
            s.step(false);
        }
        assert!(s.has_seen_any_sentence);
        // 之后喂大量静音，不应再超时
        for _ in 0..100 {
            let ev = s.step(false);
            assert_ne!(ev, Some(Event::HeadSilenceTimeout));
        }
        assert_eq!(s.state, State::Detecting);
    }

    /// 长时：首次开口前超时确实会触发。
    #[test]
    fn head_timeout_before_first_sentence_fires() {
        let cfg = LongModeConfig {
            head_silence_timeout_ms: 100,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::HeadSilenceTimeout));
        assert_eq!(s.state, State::End(EndReason::HeadSilenceTimeout));
    }

    /// 动态 tail 曲线：句子越久，所需 tail 帧数越小。
    #[test]
    fn dynamic_tail_shrinks_over_sentence_duration() {
        let cfg = LongModeConfig {
            max_sentence_duration_ms: 1000, // 62 帧 (向上取整)
            tail_silence_ms_initial: 500,   // 32 帧
            tail_silence_ms_min: 100,       // 7 帧
            enable_dynamic_tail: true,
            ..Default::default()
        };
        let mut s = sm(cfg);

        // 模拟"说了 0 帧"——current_tail 应接近 initial
        s.current_sentence_frames = 0;
        let tail_at_0 = s.current_tail_frames();
        // 模拟"说了半程"——tail 应大约在中间
        s.current_sentence_frames = 31; // half of 62
        let tail_at_half = s.current_tail_frames();
        // 模拟"说到上限"——tail 应落到 min
        s.current_sentence_frames = 62;
        let tail_at_full = s.current_tail_frames();

        assert_eq!(tail_at_0, ms_to_frames(500));
        assert!(tail_at_half < tail_at_0);
        assert!(tail_at_half >= ms_to_frames(100));
        assert_eq!(tail_at_full, ms_to_frames(100));
    }

    /// 单句强切：超过 max_sentence_duration 时发 SentenceForceCut，state 回 Detecting。
    #[test]
    fn sentence_force_cut_fires() {
        let cfg = LongModeConfig {
            max_sentence_duration_ms: 100, // 7 帧
            tail_silence_ms_initial: 10_000,
            tail_silence_ms_min: 10_000,
            enable_dynamic_tail: false,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        // 持续说话直到撞 max_sentence
        for _ in 0..3 {
            s.step(true); // -> Started/Voiced（第 3 帧 SentenceStarted）
        }
        // 这里 current_sentence_frames = 3
        // 再 4 帧 voice，到 7 帧触发强切
        let mut force_cut_seen = false;
        for _ in 0..10 {
            if let Some(Event::SentenceForceCut) = s.step(true) {
                force_cut_seen = true;
                break;
            }
        }
        assert!(force_cut_seen, "应触发 SentenceForceCut");
        assert_eq!(s.state, State::Detecting);
    }

    /// 整会话超时：session_frames 撞 max_session_duration_ms → End(MaxDurationReached)。
    #[test]
    fn session_max_duration_ends_session() {
        let cfg = LongModeConfig {
            max_session_duration_ms: 100, // 7 帧
            head_silence_timeout_ms: 0,
            ..Default::default()
        };
        let mut s = sm(cfg);
        s.start();
        let events: Vec<_> = (0..7).map(|_| s.step(false)).collect();
        assert_eq!(events[6], Some(Event::MaxDurationReached));
        assert_eq!(s.state, State::End(EndReason::MaxDurationReached));
    }

    /// stop() 终结会话（不管当前在哪个非终态）。
    #[test]
    fn stop_terminates() {
        let mut s = sm(LongModeConfig::default());
        s.start();
        for _ in 0..3 {
            s.step(true);
        }
        s.stop();
        assert_eq!(s.state, State::End(EndReason::ExternalStop));
    }
}
