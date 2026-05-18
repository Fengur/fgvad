//! 短时模式 6 个 case 的契约级断言。素材见 `test-data/short/`。
//!
//! 默认配置（与 Demo UI 默认一致）：
//! - `head_silence_timeout_ms = 3000`
//! - `tail_silence_ms = 2000`
//! - `max_duration_ms = 30000`
//!
//! 每个 case 的预期行为同 [`test-data/short/README.md`](../../test-data/short/README.md)。

#![cfg(target_os = "macos")]

mod common;

use fgvad::{EndReason, Event, FgVad, ShortModeConfig, State, VadResult};

fn default_short_cfg() -> ShortModeConfig {
    ShortModeConfig {
        head_silence_timeout_ms: 3000,
        tail_silence_ms: 2000,
        max_duration_ms: 30000,
    }
}

fn run_short(name: &str) -> (State, Vec<VadResult>) {
    let samples = common::read_test_wav(&format!("test-data/short/{name}"));
    let mut vad = FgVad::short(default_short_cfg()).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");
    (vad.state(), results)
}

fn count_event(results: &[VadResult], target: Event) -> usize {
    results.iter().filter(|r| r.event == Some(target)).count()
}

#[test]
fn case_01_pure_silence_triggers_head_timeout() {
    let (state, results) = run_short("01-pure-silence-5s.wav");
    assert_eq!(state, State::End(EndReason::HeadSilenceTimeout));
    assert_eq!(count_event(&results, Event::SentenceStarted), 0);
    assert_eq!(count_event(&results, Event::HeadSilenceTimeout), 1);
}

#[test]
fn case_02_normal_utterance_speech_completed() {
    let (state, results) = run_short("02-normal-utterance.wav");
    assert_eq!(state, State::End(EndReason::SpeechCompleted));
    assert_eq!(count_event(&results, Event::SentenceStarted), 1);
    assert_eq!(count_event(&results, Event::SentenceEnded), 1);
}

#[test]
fn case_03_immediate_speech_speech_completed() {
    let (state, results) = run_short("03-immediate-speech.wav");
    assert_eq!(state, State::End(EndReason::SpeechCompleted));
    assert_eq!(count_event(&results, Event::SentenceStarted), 1);
    assert_eq!(count_event(&results, Event::SentenceEnded), 1);
}

#[test]
fn case_04_max_duration_reached() {
    let (state, results) = run_short("04-max-duration-reached.wav");
    assert_eq!(state, State::End(EndReason::MaxDurationReached));
    assert_eq!(count_event(&results, Event::SentenceStarted), 1);
    assert_eq!(count_event(&results, Event::MaxDurationReached), 1);
}

#[test]
fn case_05_short_pauses_merged_into_one() {
    // 1.5s 短停顿 < 2s tail_silence，整段应合并为单句
    let (state, results) = run_short("05-short-pauses-merged.wav");
    assert_eq!(state, State::End(EndReason::SpeechCompleted));
    assert_eq!(
        count_event(&results, Event::SentenceStarted),
        1,
        "1.5s 短停顿不应触发新句"
    );
    assert_eq!(count_event(&results, Event::SentenceEnded), 1);
}

#[test]
fn case_06_very_brief_speech_above_confirm_threshold() {
    // 0.3s (300ms) 语音 > CONFIRM_FRAMES (16 帧 = 256ms)，应能触发 SentenceStarted
    let (state, results) = run_short("06-very-brief-speech.wav");
    assert_eq!(state, State::End(EndReason::SpeechCompleted));
    assert_eq!(count_event(&results, Event::SentenceStarted), 1);
    assert_eq!(count_event(&results, Event::SentenceEnded), 1);
}
