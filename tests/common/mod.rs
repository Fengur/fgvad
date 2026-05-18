//! 集成测试共享工具：WAV 读取 + 测试音频路径助手。
//!
//! `tests/common/mod.rs` 是 cargo 的标准约定——以 `mod.rs` 命名时不会被
//! 当成独立 test 二进制单独编译，可被同目录下任何 test 文件 `mod common;`
//! 引入复用。

use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

/// 极简 WAV 解析器：只接受 16 kHz 单声道 int16 PCM。
pub fn read_wav_16k_mono_i16(path: impl AsRef<Path>) -> Vec<i16> {
    let p = path.as_ref();
    let mut buf = Vec::new();
    File::open(p)
        .unwrap_or_else(|e| panic!("打开 wav 失败: {e} ({p:?})"))
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

    assert_eq!(sample_rate, 16000, "wav 必须 16kHz");
    assert_eq!(channels, 1, "wav 必须单声道");
    assert_eq!(bits, 16, "wav 必须 16-bit");

    let data = data.expect("找不到 data chunk");
    data.chunks_exact(2)
        .map(|b| i16::from_le_bytes([b[0], b[1]]))
        .collect()
}

/// 取项目根的相对路径，绝对化（基于 `CARGO_MANIFEST_DIR`）。
pub fn project_path(rel: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(rel)
}

/// 读取 `test-data/...` 下的 fixture。
pub fn read_test_wav(rel_under_repo: &str) -> Vec<i16> {
    read_wav_16k_mono_i16(project_path(rel_under_repo))
}
