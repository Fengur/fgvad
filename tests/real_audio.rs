//! 端到端集成测试：把一段真实 16 kHz mono i16 WAV 喂给 `FgVad`，
//! 打印每帧概率曲线，并断言语音/静音段落被正确区分。

#![cfg(target_os = "macos")]

use fgvad::{FgVad, FrameResult};
use std::fs::File;
use std::io::Read;
use std::path::Path;

/// 极简 WAV 解析器：只接受 16 kHz 单声道 int16 PCM。
/// 扫描 chunk 找到 `data`，忽略 fmt 之外的其他 chunk（如 LIST）。
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
        pos = body_end + (size & 1); // chunk 按偶数字节对齐
    }

    assert_eq!(sample_rate, 16000, "必须是 16 kHz");
    assert_eq!(channels, 1, "必须是单声道");
    assert_eq!(bits, 16, "必须是 16-bit");

    let data = data.expect("找不到 data chunk");
    assert_eq!(data.len() % 2, 0, "data 字节数必须是偶数");

    data.chunks_exact(2)
        .map(|b| i16::from_le_bytes([b[0], b[1]]))
        .collect()
}

#[test]
fn run_vad_on_real_speech() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/s0724-s0730.wav");
    let samples = read_wav_16k_mono_i16(path);
    eprintln!(
        "加载 {} 个样本（{} ms）",
        samples.len(),
        samples.len() * 1000 / 16_000
    );

    let mut vad = FgVad::new().expect("create");
    let frames: Vec<FrameResult> = vad.process(&samples).expect("process");

    print_timeline(&frames);

    // 基本分布断言。ten-vad 的"静音"帧概率并不接近 0（环境基线在 ~0.2-0.4），
    // 因此以 is_voice（即 ten-vad 自己的二值化结果）为准。
    let n_voice = frames.iter().filter(|f| f.is_voice).count();
    let n_silence = frames.len() - n_voice;
    let max_prob = frames
        .iter()
        .map(|f| f.probability)
        .fold(0.0f32, f32::max);
    let min_prob = frames
        .iter()
        .map(|f| f.probability)
        .fold(1.0f32, f32::min);

    eprintln!(
        "总帧数 {}，voice={}，silence={}，prob 范围 [{:.3}, {:.3}]",
        frames.len(),
        n_voice,
        n_silence,
        min_prob,
        max_prob,
    );

    assert!(!frames.is_empty(), "至少应有若干帧");
    assert!(n_voice > 50, "期望至少 50 个语音帧，实得 {n_voice}");
    assert!(n_silence > 20, "期望至少 20 个静音帧，实得 {n_silence}");
    assert!(max_prob > 0.85, "语音段最高概率应 > 0.85，实得 {max_prob:.3}");
}

/// 打印每 10 帧一行的概率时间线，每行带概率条形图示。
fn print_timeline(frames: &[FrameResult]) {
    eprintln!("\n帧号  时间(ms)  prob   voice  bar");
    eprintln!("────  ────────  ─────  ─────  ────────────────────");
    for (i, f) in frames.iter().enumerate() {
        if i % 5 != 0 {
            continue; // 每 5 帧（80 ms）打一行，降低噪音
        }
        let ms = i * 256 * 1000 / 16_000;
        let bar_len = (f.probability * 20.0) as usize;
        let bar: String = std::iter::repeat('█').take(bar_len).collect();
        eprintln!(
            "{:>4}  {:>8}  {:>5.3}  {:>5}  {}",
            i,
            ms,
            f.probability,
            if f.is_voice { "yes" } else { "-" },
            bar
        );
    }
    eprintln!();
}
