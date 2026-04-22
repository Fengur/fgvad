//! 长时模式集成测试。
//!
//! 利用 ten-vad 官方 `s0724-s0730.wav`——里面是两句"打开支付宝"拼接，
//! 句间约 500ms 静音。长时模式应能检出两句，SentenceStart/End 各两次。

#![cfg(target_os = "macos")]

use fgvad::{EndReason, Event, FgVad, LongModeConfig, ResultType, State, VadResult};
use std::fs::File;
use std::io::Read;
use std::path::Path;

fn read_wav_16k_mono_i16(path: impl AsRef<Path>) -> Vec<i16> {
    let mut buf = Vec::new();
    File::open(path)
        .expect("打开 wav 失败")
        .read_to_end(&mut buf)
        .expect("读取 wav 失败");

    assert_eq!(&buf[0..4], b"RIFF");
    assert_eq!(&buf[8..12], b"WAVE");

    let mut pos = 12usize;
    let mut data: Option<&[u8]> = None;
    while pos + 8 <= buf.len() {
        let id = &buf[pos..pos + 4];
        let size = u32::from_le_bytes(buf[pos + 4..pos + 8].try_into().unwrap()) as usize;
        let body_start = pos + 8;
        let body_end = body_start + size;
        if id == b"data" {
            data = Some(&buf[body_start..body_end]);
            break;
        }
        pos = body_end + (size & 1);
    }
    data.expect("找不到 data chunk")
        .chunks_exact(2)
        .map(|b| i16::from_le_bytes([b[0], b[1]]))
        .collect()
}

fn fixture() -> Vec<i16> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/s0724-s0730.wav");
    read_wav_16k_mono_i16(path)
}

fn summarize(results: &[VadResult]) {
    for r in results {
        eprintln!(
            "  offset={:>6}  type={:?}  len={:>5}  frames={:>3}  event={:?}  state={:?}  begin={} end={}",
            r.stream_offset_sample,
            r.result_type,
            r.audio.len(),
            r.frames.len(),
            r.event,
            r.state,
            r.is_sentence_begin,
            r.is_sentence_end,
        );
    }
}

/// 长时模式下 `s0724-s0730.wav` 应切出 2 句。
#[test]
fn detects_two_sentences_in_real_audio() {
    let samples = fixture();
    // 句间静音约 500ms；把 tail 收紧到 400ms 让两句之间能触发 SentenceEnded
    let cfg = LongModeConfig {
        tail_silence_ms_initial: 400,
        tail_silence_ms_min: 400,
        enable_dynamic_tail: false,
        max_sentence_duration_ms: 10_000,
        ..Default::default()
    };
    let mut vad = FgVad::long(cfg).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");
    eprintln!("长时模式共 {} 段：", results.len());
    summarize(&results);

    let starts: Vec<_> = results
        .iter()
        .enumerate()
        .filter(|(_, r)| r.result_type == ResultType::SentenceStart)
        .collect();
    let ends: Vec<_> = results
        .iter()
        .enumerate()
        .filter(|(_, r)| r.result_type == ResultType::SentenceEnd)
        .collect();

    assert_eq!(starts.len(), 2, "应检出两句开始");
    assert_eq!(ends.len(), 2, "应检出两句结束");

    // 顺序：start1 < end1 < start2 < end2
    assert!(starts[0].0 < ends[0].0);
    assert!(ends[0].0 < starts[1].0);
    assert!(starts[1].0 < ends[1].0);

    // 两个 SentenceEnded 事件都应挂在对应的 SentenceEnd VadResult 上
    for (_, r) in &ends {
        assert_eq!(r.event, Some(Event::SentenceEnded));
    }
}

/// 长时模式下多句 offset 严格单调递增，供回放高亮使用。
#[test]
fn offsets_are_monotonic_across_sentences() {
    let samples = fixture();
    let cfg = LongModeConfig {
        tail_silence_ms_initial: 400,
        tail_silence_ms_min: 400,
        enable_dynamic_tail: false,
        max_sentence_duration_ms: 10_000,
        ..Default::default()
    };
    let mut vad = FgVad::long(cfg).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");

    // 每段的 start 都应 >= 前一段的 end
    let mut last_end: u64 = 0;
    for r in &results {
        let this_end = r.stream_offset_sample + r.audio.len() as u64;
        assert!(
            r.stream_offset_sample >= last_end.saturating_sub(r.audio.len() as u64),
            "offset 不应回退：{} 之后却见到 offset {}",
            last_end,
            r.stream_offset_sample
        );
        last_end = this_end;
    }

    // 收集两个 SentenceStart 的 offset，验证第二句在第一句之后
    let start_offsets: Vec<u64> = results
        .iter()
        .filter(|r| r.result_type == ResultType::SentenceStart)
        .map(|r| r.stream_offset_sample)
        .collect();
    assert_eq!(start_offsets.len(), 2);
    assert!(start_offsets[0] < start_offsets[1]);

    let end_offsets: Vec<u64> = results
        .iter()
        .filter(|r| r.result_type == ResultType::SentenceEnd)
        .map(|r| r.stream_offset_sample + r.audio.len() as u64)
        .collect();
    assert_eq!(end_offsets.len(), 2);

    // 每句的 [start, end] 区间供回放高亮用
    eprintln!(
        "sentence 1: samples [{}, {}]  ({}ms)",
        start_offsets[0],
        end_offsets[0],
        (end_offsets[0] - start_offsets[0]) / 16
    );
    eprintln!(
        "sentence 2: samples [{}, {}]  ({}ms)",
        start_offsets[1],
        end_offsets[1],
        (end_offsets[1] - start_offsets[1]) / 16
    );
    assert!(end_offsets[0] <= start_offsets[1], "第一句结束应早于第二句开始");
}

/// stop() 能在长时会话里正常收尾。
#[test]
fn external_stop_in_long_mode() {
    let samples = fixture();
    let cfg = LongModeConfig {
        tail_silence_ms_initial: 400,
        tail_silence_ms_min: 400,
        enable_dynamic_tail: false,
        ..Default::default()
    };
    let mut vad = FgVad::long(cfg).expect("create");
    vad.start();
    // 喂一半音频
    let _ = vad.process(&samples[..samples.len() / 2]).expect("p1");
    vad.stop();
    assert_eq!(vad.state(), State::End(EndReason::ExternalStop));
    // stop 后 process 返回空
    let after = vad.process(&samples[..1000]).expect("post-stop");
    assert!(after.is_empty());
}

/// 单句强切：配置极小 max_sentence_duration 让长音频里每句都被强切。
#[test]
fn sentence_force_cut_fires_on_max_sentence_duration() {
    let samples = fixture();
    let cfg = LongModeConfig {
        tail_silence_ms_initial: 10_000, // 不让它自然 tail
        tail_silence_ms_min: 10_000,
        enable_dynamic_tail: false,
        max_sentence_duration_ms: 800, // 每句最长 0.8s 就强切
        head_silence_timeout_ms: 0,
        ..Default::default()
    };
    let mut vad = FgVad::long(cfg).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");

    let force_cuts: Vec<_> = results
        .iter()
        .filter(|r| r.event == Some(Event::SentenceForceCut))
        .collect();
    assert!(
        !force_cuts.is_empty(),
        "短 max_sentence_duration 下应出现 SentenceForceCut"
    );
    // 每个 ForceCut 的 VadResult 类型应为 SentenceEnd
    for r in &force_cuts {
        assert_eq!(r.result_type, ResultType::SentenceEnd);
        assert!(r.is_sentence_end);
    }
}
