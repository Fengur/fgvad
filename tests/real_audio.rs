//! 端到端集成测试：把一段真实 16 kHz mono i16 WAV 喂给 `FgVad`，
//! 验证角色切分、pre-roll、尾静音 padding 等真实行为。

#![cfg(target_os = "macos")]

use fgvad::{EndReason, Event, FgVad, FrameDiag, ResultType, ShortModeConfig, State, VadResult};
use std::fs::File;
use std::io::Read;
use std::path::Path;

/// 极简 WAV 解析器：只接受 16 kHz 单声道 int16 PCM。
fn read_wav_16k_mono_i16(path: impl AsRef<Path>) -> Vec<i16> {
    let mut buf = Vec::new();
    File::open(path)
        .expect("打开 wav 失败")
        .read_to_end(&mut buf)
        .expect("读取 wav 失败");

    assert_eq!(&buf[0..4], b"RIFF", "不是 RIFF 文件");
    assert_eq!(&buf[8..12], b"WAVE", "不是 WAVE 文件");

    let mut pos = 12usize;
    let mut sample_rate = 0u32;
    let mut channels = 0u16;
    let mut bits = 0u16;
    let mut data: Option<&[u8]> = None;

    while pos + 8 <= buf.len() {
        let id = &buf[pos..pos + 4];
        let size = u32::from_le_bytes(buf[pos + 4..pos + 8].try_into().unwrap()) as usize;
        let body_start = pos + 8;
        let body_end = body_start + size;

        match id {
            b"fmt " => {
                let body = &buf[body_start..body_end];
                channels = u16::from_le_bytes(body[2..4].try_into().unwrap());
                sample_rate = u32::from_le_bytes(body[4..8].try_into().unwrap());
                bits = u16::from_le_bytes(body[14..16].try_into().unwrap());
            }
            b"data" => {
                data = Some(&buf[body_start..body_end]);
                break;
            }
            _ => {}
        }
        pos = body_end + (size & 1);
    }

    assert_eq!(sample_rate, 16000);
    assert_eq!(channels, 1);
    assert_eq!(bits, 16);

    let data = data.expect("找不到 data chunk");
    data.chunks_exact(2)
        .map(|b| i16::from_le_bytes([b[0], b[1]]))
        .collect()
}

fn fixture() -> Vec<i16> {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/s0724-s0730.wav");
    read_wav_16k_mono_i16(path)
}

/// 打印 result 类型序列与位置，用于 debug。
fn dump(results: &[VadResult]) {
    for r in results {
        eprintln!(
            "  offset={:>6}  type={:?}  len={:>5}  frames={:>3}  event={:?}  state={:?}",
            r.stream_offset_sample,
            r.result_type,
            r.audio.len(),
            r.frames.len(),
            r.event,
            r.state,
        );
    }
}

#[test]
fn full_session_on_real_speech() {
    let samples = fixture();
    // 默认 tail=700ms 在这段 wav 的两句中间的 500ms 不足以判停；收紧到 400ms 让会话
    // 在第一句后正常收尾。
    let cfg = ShortModeConfig {
        tail_silence_ms: 400,
        ..Default::default()
    };
    let mut vad = FgVad::short(cfg).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");

    eprintln!("共 {} 段 VadResult：", results.len());
    dump(&results);

    // 必须至少有：Silence（头部）→ SentenceStart → ... → SentenceEnd
    let types: Vec<_> = results.iter().map(|r| r.result_type).collect();
    assert!(types.contains(&ResultType::Silence));
    assert!(types.contains(&ResultType::SentenceStart));
    assert!(types.contains(&ResultType::SentenceEnd));

    // 顺序：SentenceStart 必须在 SentenceEnd 之前
    let start_idx = types.iter().position(|t| *t == ResultType::SentenceStart).unwrap();
    let end_idx = types.iter().rposition(|t| *t == ResultType::SentenceEnd).unwrap();
    assert!(start_idx < end_idx);

    // SentenceStart 标记正确
    let start = &results[start_idx];
    assert!(start.is_sentence_begin);
    assert!(!start.is_sentence_end);

    // SentenceEnd 标记正确，终态是 SpeechCompleted，事件是 SentenceEnded
    let end = &results[end_idx];
    assert!(end.is_sentence_end);
    assert_eq!(end.state, State::End(EndReason::SpeechCompleted));
    assert_eq!(end.event, Some(Event::SentenceEnded));

    // 会话结束后 process 应返回空
    assert!(vad.process(&samples[..1000]).expect("post-end").is_empty());
}

#[test]
fn sentence_start_contains_pre_roll() {
    let samples = fixture();
    let cfg = ShortModeConfig {
        tail_silence_ms: 400,
        ..Default::default()
    };
    let mut vad = FgVad::short(cfg).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");

    let start = results
        .iter()
        .find(|r| r.result_type == ResultType::SentenceStart)
        .expect("应存在 SentenceStart");

    // 本 fixture 里 SentenceStart 出现在 frame 32 附近（ten-vad 首次触发+3 帧确认）。
    // pre-roll=250ms=16 帧应把 SentenceStart 的起始前移到 frame 16 之前左右。
    // 这里用 frames.len() 做粗略验证：SentenceStart 的 frames 至少有 pre-roll 的帧数。
    assert!(
        start.frames.len() >= 16,
        "SentenceStart 应至少包含 pre-roll 的 16 帧，实得 {}",
        start.frames.len()
    );
    assert_eq!(
        start.audio.len(),
        start.frames.len() * 256,
        "音频长度应与 frames 数严格对齐（256 样本/帧）"
    );
}

/// 小 chunk 模拟流式输入：应随时间逐段吐 VadResult，总音频覆盖不丢帧。
#[test]
fn streaming_input_in_small_chunks() {
    let samples = fixture();
    let chunk_len = 256 * 2; // 32 ms per chunk
    let cfg = ShortModeConfig {
        tail_silence_ms: 400,
        ..Default::default()
    };
    let mut vad = FgVad::short(cfg).expect("create");
    vad.start();

    let mut all_results: Vec<VadResult> = Vec::new();
    for chunk in samples.chunks(chunk_len) {
        let r = vad.process(chunk).expect("process");
        all_results.extend(r);
        if matches!(all_results.last().map(|r| r.state), Some(State::End(_))) {
            break;
        }
    }

    eprintln!("流式输入共得 {} 段：", all_results.len());
    // 打前 5 后 5
    let n = all_results.len();
    for r in &all_results[..5.min(n)] {
        eprintln!(
            "  {:?} offset={} len={}",
            r.result_type,
            r.stream_offset_sample,
            r.audio.len()
        );
    }
    if n > 5 {
        eprintln!("  ...");
        for r in &all_results[n.saturating_sub(3)..] {
            eprintln!(
                "  {:?} offset={} len={}",
                r.result_type,
                r.stream_offset_sample,
                r.audio.len()
            );
        }
    }

    // 流式下应仍有 SentenceStart 和 SentenceEnd
    assert!(all_results
        .iter()
        .any(|r| r.result_type == ResultType::SentenceStart));
    assert!(all_results
        .iter()
        .any(|r| r.result_type == ResultType::SentenceEnd));

    // is_sentence_begin 只出现 1 次（短时单段），is_sentence_end 也只 1 次
    let n_begin = all_results.iter().filter(|r| r.is_sentence_begin).count();
    let n_end = all_results.iter().filter(|r| r.is_sentence_end).count();
    assert_eq!(n_begin, 1);
    assert_eq!(n_end, 1);
}

/// 把 Active 段的 frames 串起来画个概率条，肉眼复核 ten-vad 曲线（保留此便于调试）。
#[test]
fn print_probability_timeline() {
    let samples = fixture();
    let cfg = ShortModeConfig {
        tail_silence_ms: 400,
        ..Default::default()
    };
    let mut vad = FgVad::short(cfg).expect("create");
    vad.start();
    let results = vad.process(&samples).expect("process");

    let all_frames: Vec<&FrameDiag> = results.iter().flat_map(|r| r.frames.iter()).collect();
    eprintln!("\n总帧数 {}", all_frames.len());
    for (i, f) in all_frames.iter().enumerate() {
        if i % 10 != 0 {
            continue;
        }
        let bar_len = (f.probability * 20.0) as usize;
        let bar: String = std::iter::repeat('█').take(bar_len).collect();
        eprintln!(
            "  {:>4} {:>5.2} {} {}",
            i,
            f.probability,
            if f.is_voice { '✓' } else { ' ' },
            bar
        );
    }
}
