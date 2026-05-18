//! 长时模式核心契约：动态尾端点曲线对照实验。
//!
//! 基于 25:33 一席演讲（`test-data/long/yixi-zhuzhiwei-typography.wav`）的实测数据：
//! - ON  (默认): 85 句, 5 ForceCut, 5.9% 强切率
//! - OFF (恒等 2000ms tail): 53 句, 46 ForceCut, 87% 强切率
//!
//! 这套断言固化了 fgvad 在长时连续语音上的设计意图——动态曲线必须显著降低
//! 强切占比。任何让这条曲线退化的改动都会被 cargo test 拦下。
//!
//! 性能注意：每个测试把 24M sample 一次喂给 ten-vad，约 45s/次。三个测试
//! 总计 ~2-3 分钟。CI 跑完整 cargo test 可接受。

#![cfg(target_os = "macos")]

mod common;

use fgvad::{Event, FgVad, LongModeConfig, VadResult};

const YIXI: &str = "test-data/long/yixi-zhuzhiwei-typography.wav";

fn default_long_cfg(enable_dynamic_tail: bool) -> LongModeConfig {
    LongModeConfig {
        head_silence_timeout_ms: 3000,
        max_sentence_duration_ms: 30000,
        max_session_duration_ms: 0,
        tail_silence_ms_initial: 2000,
        tail_silence_ms_min: 600,
        enable_dynamic_tail,
    }
}

fn run_yixi(enable_dynamic_tail: bool) -> (usize, usize) {
    let samples = common::read_test_wav(YIXI);
    let mut vad = FgVad::long(default_long_cfg(enable_dynamic_tail)).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");
    summary(&results)
}

fn summary(results: &[VadResult]) -> (usize, usize) {
    let sentences = results
        .iter()
        .filter(|r| r.event == Some(Event::SentenceStarted))
        .count();
    let force_cuts = results
        .iter()
        .filter(|r| r.event == Some(Event::SentenceForceCut))
        .count();
    (sentences, force_cuts)
}

#[test]
fn dynamic_curve_on_yields_baseline_85_sentences_5_force_cuts() {
    let (sentences, force_cuts) = run_yixi(true);
    eprintln!("ON: {sentences} 句, {force_cuts} ForceCut");
    assert!(
        (83..=87).contains(&sentences),
        "动态 ON 期望 85±2 句，实得 {sentences}"
    );
    assert_eq!(force_cuts, 5, "动态 ON 期望 5 个 ForceCut，实得 {force_cuts}");
}

#[test]
fn dynamic_curve_off_degrades_to_force_cut_dominated() {
    let (sentences, force_cuts) = run_yixi(false);
    eprintln!("OFF: {sentences} 句, {force_cuts} ForceCut");
    assert!(
        (51..=55).contains(&sentences),
        "动态 OFF 期望 53±2 句，实得 {sentences}"
    );
    assert!(
        force_cuts >= 40,
        "动态 OFF 应有大量 ForceCut（典型 46），实得 {force_cuts}"
    );
}

/// 设计契约：动态曲线必须显著降低 ForceCut 占比。
///
/// 此断言保护 fgvad 的核心存在论证——若这条 fail 了，意味着动态曲线
/// 失效或退化，README 里 85/5 vs 53/46 那张表的论证基础没了。
#[test]
fn dynamic_curve_substantially_reduces_force_cut_ratio() {
    let (s_on, fc_on) = run_yixi(true);
    let (s_off, fc_off) = run_yixi(false);

    let ratio_on = fc_on as f64 / s_on as f64;
    let ratio_off = fc_off as f64 / s_off as f64;
    eprintln!("ON  ForceCut 占比: {:.1}%", ratio_on * 100.0);
    eprintln!("OFF ForceCut 占比: {:.1}%", ratio_off * 100.0);

    assert!(
        ratio_on < 0.10,
        "ON 模式 ForceCut 占比应 <10% (设计目标)，实得 {:.1}%",
        ratio_on * 100.0
    );
    assert!(
        ratio_off > 0.50,
        "OFF 模式 ForceCut 占比应 >50% (用以验证 ON 模式的相对价值)，实得 {:.1}%",
        ratio_off * 100.0
    );
    assert!(
        ratio_on < ratio_off * 0.20,
        "动态曲线应让 ForceCut 占比降到 OFF 的 20% 以下；实得 ON {:.1}% / OFF {:.1}%",
        ratio_on * 100.0,
        ratio_off * 100.0
    );
}
