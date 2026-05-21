# Android Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 fgvad 库跨编到 Android arm64-v8a，写 JNI 桥，做 1:1 复刻 iOS demo 交互的 Android demo（含按句试听、加载测试 WAV）。

**Architecture:** 三层切干净——(1) fgvad rlib 扩展 cfg 到 android，build.rs 链 ten-vad 的 `libten_vad.so`；(2) 独立 `fgvad-jni` cdylib crate 依赖 fgvad rlib，用 `jni` crate 暴露 JNI 函数给 Kotlin；(3) Android Studio 项目用 Views（XML+Kotlin）一比一翻 iOS UIKit demo。

**Tech Stack:** Rust（fgvad core，jni 0.21）/ NDK 28.2 toolchain / Kotlin / Android Views / AudioRecord+AudioTrack（裸 PCM）/ RecyclerView。设计稿见 [`../specs/2026-05-21-android-demo-design.md`](../specs/2026-05-21-android-demo-design.md)。

---

## File Structure

**新建：**

| 路径 | 责任 |
|---|---|
| `vendor/ten-vad/Android/arm64-v8a/libten_vad.so` | 上游预编 .so |
| `examples/android/fgvad-jni/Cargo.toml` | bridge crate manifest |
| `examples/android/fgvad-jni/src/lib.rs` | JNI exports |
| `examples/android/FgVadDemo/` | Android Studio 项目（gradle wrapper、settings、app/...） |
| `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/*.kt` | Kotlin lib wrapper |
| `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/*.kt` | App 代码 |
| `examples/android/FgVadDemo/app/src/main/res/layout/*.xml` | UI 布局 |
| `examples/android/FgVadDemo/app/src/main/AndroidManifest.xml` | manifest |
| `examples/android/FgVadDemo/app/src/main/jniLibs/arm64-v8a/{libfgvad_android,libten_vad}.so` | 运行时加载（由脚本拷入） |
| `examples/android/FgVadDemo/app/src/main/assets/short/*.wav` | 短测试 WAV |
| `examples/android/README.md` | Android 端构建说明 |
| `scripts/build-android.sh` | 一键编 Rust + 拷 .so |

**修改：**

| 路径 | 改什么 |
|---|---|
| `src/lib.rs` | cfg 扩 `target_os = "android"` |
| `build.rs` | 加 `link_android()` 分支 |
| `vendor/ten-vad/README.md` | 添加 Android 子目录说明 + 升级流程同步 |
| `README.md` | 路线图把 Android 那行打勾、补 Android demo 复现命令 |

---

## Phase 1 — fgvad library Android cross-compile

### Task 1: 扩展 fgvad crate 的 cfg gate 到 android

**Files:**
- Modify: `src/lib.rs`

- [ ] **Step 1: 把所有 `#[cfg(any(target_os = "macos", target_os = "ios"))]` 改成包含 android**

```rust
// src/lib.rs 顶部 4 处 cfg 全部改为：
#[cfg(any(target_os = "macos", target_os = "ios", target_os = "android"))]
```

涉及 `mod sys;` / `mod vad;` / `pub mod ffi;` / `pub use vad::{...}` / `pub fn ten_vad_version()` / `tests` 内的那个 `#[cfg]`。一共 6 处。

- [ ] **Step 2: 验证 macOS 上还编译**

Run: `cargo build`
Expected: 干净编出，无 warning（除了原本就有的）

- [ ] **Step 3: 验证 macOS 上 cargo test 还过**

Run: `cargo test --lib --quiet 2>&1 | tail -5`
Expected: 全过（不跑 tests/ 里的长跑集成）

- [ ] **Step 4: Commit**

```bash
git add src/lib.rs
git commit -m "fgvad: extend cfg gates to allow android target_os"
```

---

### Task 2: Vendor ten-vad Android .so

**Files:**
- Create: `vendor/ten-vad/Android/arm64-v8a/libten_vad.so`
- Modify: `vendor/ten-vad/README.md`

- [ ] **Step 1: 拉上游对应 commit**

Run:
```bash
TEN_VAD_COMMIT="22a3bcd4509d0faaa8eef4881e8af5f39c178950"
cd /tmp && rm -rf ten-vad
git clone https://github.com/TEN-framework/ten-vad
cd ten-vad && git checkout "$TEN_VAD_COMMIT"
ls lib/Android/  # 找到 arm64-v8a 路径
```

Expected: 看到形如 `arm64-v8a/libten_vad.so` 的结构。如果上游布局变了，拿实际路径写下一步。

- [ ] **Step 2: 拷到 vendor**

Run:
```bash
cd /Users/fengurwang/Desktop/OldJob/fgvad
mkdir -p vendor/ten-vad/Android/arm64-v8a
cp /tmp/ten-vad/lib/Android/arm64-v8a/libten_vad.so vendor/ten-vad/Android/arm64-v8a/
ls -la vendor/ten-vad/Android/arm64-v8a/libten_vad.so
file vendor/ten-vad/Android/arm64-v8a/libten_vad.so
```

Expected: `file` 输出 `ELF 64-bit LSB shared object, ARM aarch64`。

- [ ] **Step 3: 更新 vendor README**

Modify `vendor/ten-vad/README.md` 的目录树部分，在 iOS 之后加：

```markdown
├── Android/
│   └── arm64-v8a/
│       └── libten_vad.so      arm64-v8a，上游原版（无 simulator 概念）
```

并在"升级 ten-vad 上游版本"小节追加：

```bash
# Android arm64-v8a
rm -rf vendor/ten-vad/Android/arm64-v8a
mkdir -p vendor/ten-vad/Android/arm64-v8a
cp /tmp/ten-vad/lib/Android/arm64-v8a/libten_vad.so vendor/ten-vad/Android/arm64-v8a/
```

- [ ] **Step 4: Commit**

```bash
git add vendor/ten-vad/Android vendor/ten-vad/README.md
git commit -m "vendor ten-vad Android arm64-v8a libten_vad.so"
```

---

### Task 3: 给 build.rs 加 Android 链接分支

**Files:**
- Modify: `build.rs`

- [ ] **Step 1: 加 dispatch 分支**

修改 `build.rs` 顶部 match：

```rust
match target_os.as_str() {
    "macos" => link_macos(),
    "ios" => link_ios(&target),
    "android" => link_android(),
    _ => {
        println!(
            "cargo:warning=fgvad 当前平台 {target} 未配置 ten-vad 链接\
            ，仅支持 macOS / iOS / Android。"
        );
    }
}
```

- [ ] **Step 2: 实现 `link_android` 函数**

在 `build.rs` 末尾追加：

```rust
fn link_android() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR unset");
    let abi = "arm64-v8a"; // 单 ABI；将来支持 v7a 时这里按 target arch 切换
    let lib_dir = format!("{manifest_dir}/vendor/ten-vad/Android/{abi}");

    println!("cargo:rustc-link-search=native={lib_dir}");
    println!("cargo:rustc-link-lib=dylib=ten_vad");

    // .so 链接信息：DT_NEEDED 写 libten_vad.so，运行时由 Android linker 在
    // jniLibs/<abi>/ 目录下找到（由 APK 解压保证）。不需要 rpath。

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=vendor/ten-vad/Android/{abi}/libten_vad.so");
}
```

- [ ] **Step 3: 装 Rust Android target**

Run:
```bash
rustup target add aarch64-linux-android
```

Expected: 成功，或已装提示。

- [ ] **Step 4: 试编（不通也没关系，看是不是只差 linker 配置）**

Run:
```bash
NDK="$HOME/Library/Android/sdk/ndk/28.2.13676358"
TOOLCHAIN_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
CC_aarch64_linux_android="$TOOLCHAIN_BIN/aarch64-linux-android26-clang" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOLCHAIN_BIN/aarch64-linux-android26-clang" \
cargo build --target=aarch64-linux-android --lib 2>&1 | tail -20
```

Expected: `libfgvad.dylib` 是 macOS 概念，Android 上是 `libfgvad.so`。要么编出 `target/aarch64-linux-android/debug/libfgvad.so`，要么报链接错误（缺 ten_vad）。后者也可——下一步统一在 build script 里包裹。

如果报 "library not found for -lten_vad"：先看 `ls vendor/ten-vad/Android/arm64-v8a/` 文件名。Rust 链接 `dylib=ten_vad` 找的是 `libten_vad.so`，文件名必须是这个。如有出入，调整 vendor 命名或 link_android 中的 link-lib 名。

- [ ] **Step 5: macOS 回归再跑一次**

Run: `cargo build && cargo test --lib --quiet 2>&1 | tail -3`
Expected: 全过。

- [ ] **Step 6: Commit**

```bash
git add build.rs
git commit -m "build.rs: link ten-vad libten_vad.so for android"
```

---

### Task 4: 创建 build-android.sh 一键脚本

**Files:**
- Create: `scripts/build-android.sh`

- [ ] **Step 1: 写脚本**

```bash
#!/usr/bin/env bash
# 编 fgvad-jni（含 fgvad 静态链） → 拷到 demo jniLibs。
# 用法：
#   scripts/build-android.sh                    # debug
#   scripts/build-android.sh --release          # release
set -euo pipefail

PROFILE="debug"
for arg in "$@"; do
  if [[ "$arg" == "--release" ]]; then
    PROFILE="release"
    break
  fi
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NDK="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
if [[ ! -d "$NDK" ]]; then
  echo "✗ 找不到 NDK：$NDK"
  echo "  请装 NDK 28.2.13676358 或设 ANDROID_NDK_HOME"
  exit 1
fi

# 注意：Apple Silicon Mac 的 NDK 仍然叫 darwin-x86_64（Google 沿用旧名，
# 实际是 arm64 原生二进制）。不要改成 darwin-arm64。
TOOLCHAIN_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
if [[ ! -x "$TOOLCHAIN_BIN/aarch64-linux-android26-clang" ]]; then
  echo "✗ 找不到 NDK toolchain: $TOOLCHAIN_BIN"
  exit 1
fi

# 自动装 rustup target
if ! rustup target list --installed | grep -q '^aarch64-linux-android$'; then
  echo "==> 安装 rustup target aarch64-linux-android"
  rustup target add aarch64-linux-android
fi

export CC_aarch64_linux_android="$TOOLCHAIN_BIN/aarch64-linux-android26-clang"
export CXX_aarch64_linux_android="$TOOLCHAIN_BIN/aarch64-linux-android26-clang++"
export AR_aarch64_linux_android="$TOOLCHAIN_BIN/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC_aarch64_linux_android"

cd "$ROOT/examples/android/fgvad-jni"
echo "==> 编译 fgvad-jni ($PROFILE) for aarch64-linux-android"
if [[ "$PROFILE" == "release" ]]; then
  cargo build --target=aarch64-linux-android --release
else
  cargo build --target=aarch64-linux-android
fi

# 拷 .so 到 demo jniLibs
DEMO_LIBS="$ROOT/examples/android/FgVadDemo/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$DEMO_LIBS"
cp "$ROOT/target/aarch64-linux-android/$PROFILE/libfgvad_android.so" "$DEMO_LIBS/"
cp "$ROOT/vendor/ten-vad/Android/arm64-v8a/libten_vad.so" "$DEMO_LIBS/"

echo
echo "✓ Android .so 已就绪: $DEMO_LIBS"
ls -la "$DEMO_LIBS"
echo
echo "==> 链接信息（DT_NEEDED 应该看到 libten_vad.so）："
"$TOOLCHAIN_BIN/llvm-readelf" -d "$DEMO_LIBS/libfgvad_android.so" | grep NEEDED || true
```

- [ ] **Step 2: 加可执行权限**

Run: `chmod +x scripts/build-android.sh`

- [ ] **Step 3: 暂不跑——等 Task 5 把 fgvad-jni crate 创出来再试**

- [ ] **Step 4: Commit**

```bash
git add scripts/build-android.sh
git commit -m "scripts: add build-android.sh"
```

---

## Phase 2 — fgvad-jni crate 骨架 + 生命周期 JNI

### Task 5: 创建 fgvad-jni crate

**Files:**
- Create: `examples/android/fgvad-jni/Cargo.toml`
- Create: `examples/android/fgvad-jni/src/lib.rs`

- [ ] **Step 1: 创建目录结构**

Run:
```bash
mkdir -p examples/android/fgvad-jni/src
```

- [ ] **Step 2: 写 Cargo.toml**

Create `examples/android/fgvad-jni/Cargo.toml`:

```toml
[package]
name = "fgvad-jni"
version = "0.1.0"
edition = "2021"
license = "MIT"
description = "JNI bridge for fgvad on Android"
publish = false

[lib]
name = "fgvad_android"
crate-type = ["cdylib"]

[dependencies]
fgvad = { path = "../../.." }
jni = "0.21"
```

- [ ] **Step 3: 写最小 lib.rs（先验证 cargo build 通）**

Create `examples/android/fgvad-jni/src/lib.rs`:

```rust
//! fgvad Android JNI bridge.
//!
//! Kotlin 端通过 `System.loadLibrary("fgvad_android")` 加载，所有 JNI
//! 函数符号形如 `Java_io_fengur_fgvad_FgVad_*`。

#![cfg(target_os = "android")]

use jni::JNIEnv;
use jni::objects::JClass;
use jni::sys::jstring;

/// 烟测函数：返回 fgvad 库版本字符串。Kotlin 测试用。
#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeVersion<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jstring {
    let v = fgvad::version();
    env.new_string(v).expect("new_string").into_raw()
}
```

- [ ] **Step 4: 跑 build-android.sh**

Run: `./scripts/build-android.sh`
Expected: 编出 `target/aarch64-linux-android/debug/libfgvad_android.so`，拷到 `examples/android/FgVadDemo/app/src/main/jniLibs/arm64-v8a/`（即便 demo 项目此时还没有，目录会自动创建）。`llvm-readelf -d` 应显示 `NEEDED libten_vad.so`。

如果失败：
- "could not find native static library `ten_vad`"：检查 `vendor/ten-vad/Android/arm64-v8a/libten_vad.so` 文件名是否完全匹配
- ld 报 unresolved symbols：八成是 ten-vad 头文件 ABI 与 .so 不一致——重新 vendor

- [ ] **Step 5: Commit**

```bash
git add examples/android/fgvad-jni
git commit -m "fgvad-jni: skeleton crate with version() smoke export"
```

---

### Task 6: JNI 实现：构造 + 释放

**Files:**
- Modify: `examples/android/fgvad-jni/src/lib.rs`

- [ ] **Step 1: 加 panic 兜底辅助**

在 `lib.rs` 顶部 imports 后追加：

```rust
use std::panic::{catch_unwind, AssertUnwindSafe};
use jni::sys::{jboolean, jint, jlong};

/// 把 Rust panic 转成 Java IllegalStateException。所有 native 函数包一层。
fn catch_panic<F: FnOnce() -> R, R: Default>(env: &mut JNIEnv, body: F) -> R {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(r) => r,
        Err(_) => {
            let _ = env.throw_new("java/lang/IllegalStateException", "fgvad-jni panicked");
            R::default()
        }
    }
}
```

- [ ] **Step 2: 加 newShort/newLong/free**

```rust
use fgvad::{FgVad, LongModeConfig, Mode, ShortModeConfig};

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeNewShort<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    head_silence_ms: jint,
    tail_silence_ms: jint,
    max_duration_ms: jint,
) -> jlong {
    catch_panic(&mut env, || {
        let cfg = ShortModeConfig {
            head_silence_timeout_ms: head_silence_ms.max(0) as u32,
            tail_silence_ms: tail_silence_ms.max(0) as u32,
            max_duration_ms: max_duration_ms.max(0) as u32,
        };
        match FgVad::short(cfg) {
            Ok(vad) => Box::into_raw(Box::new(vad)) as jlong,
            Err(_) => 0,
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeNewLong<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    head_silence_ms: jint,
    max_sentence_ms: jint,
    max_session_ms: jint,
    tail_init_ms: jint,
    tail_min_ms: jint,
    enable_dynamic: jboolean,
) -> jlong {
    catch_panic(&mut env, || {
        let cfg = LongModeConfig {
            head_silence_timeout_ms: head_silence_ms.max(0) as u32,
            max_sentence_duration_ms: max_sentence_ms.max(0) as u32,
            max_session_duration_ms: max_session_ms.max(0) as u32,
            tail_silence_ms_initial: tail_init_ms.max(0) as u32,
            tail_silence_ms_min: tail_min_ms.max(0) as u32,
            enable_dynamic_tail: enable_dynamic != 0,
        };
        match FgVad::long(cfg) {
            Ok(vad) => Box::into_raw(Box::new(vad)) as jlong,
            Err(_) => 0,
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeFree<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    handle: jlong,
) {
    catch_panic(&mut env, || {
        if handle != 0 {
            unsafe { drop(Box::from_raw(handle as *mut FgVad)); }
        }
    });
}

/// 拿 handle 解引用为 &mut FgVad。NULL handle 返回 None。
unsafe fn handle_mut<'a>(handle: jlong) -> Option<&'a mut FgVad> {
    if handle == 0 {
        None
    } else {
        Some(&mut *(handle as *mut FgVad))
    }
}

unsafe fn handle_ref<'a>(handle: jlong) -> Option<&'a FgVad> {
    if handle == 0 {
        None
    } else {
        Some(&*(handle as *const FgVad))
    }
}
```

- [ ] **Step 3: 编译**

Run: `./scripts/build-android.sh`
Expected: 编过。

- [ ] **Step 4: Commit**

```bash
git add examples/android/fgvad-jni/src/lib.rs
git commit -m "fgvad-jni: lifecycle (newShort/newLong/free) with panic guard"
```

---

### Task 7: JNI 实现：start/stop/reset/state/endReason

**Files:**
- Modify: `examples/android/fgvad-jni/src/lib.rs`

- [ ] **Step 1: 加 5 个简单调度函数**

```rust
use fgvad::State;

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeStart<'local>(
    mut env: JNIEnv<'local>, _class: JClass<'local>, handle: jlong,
) {
    catch_panic(&mut env, || {
        if let Some(v) = unsafe { handle_mut(handle) } { v.start(); }
    });
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeStop<'local>(
    mut env: JNIEnv<'local>, _class: JClass<'local>, handle: jlong,
) {
    catch_panic(&mut env, || {
        if let Some(v) = unsafe { handle_mut(handle) } { v.stop(); }
    });
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeReset<'local>(
    mut env: JNIEnv<'local>, _class: JClass<'local>, handle: jlong,
) {
    catch_panic(&mut env, || {
        if let Some(v) = unsafe { handle_mut(handle) } { v.reset(); }
    });
}

/// 返回 State 的 ordinal（与 Kotlin enum State 顺序匹配：
/// Idle=0, Detecting=1, Started=2, Voiced=3, Trailing=4, End=5）。
#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeState<'local>(
    mut env: JNIEnv<'local>, _class: JClass<'local>, handle: jlong,
) -> jint {
    catch_panic(&mut env, || {
        let Some(v) = (unsafe { handle_ref(handle) }) else { return 0; };
        state_ordinal(v.state())
    })
}

/// 返回 EndReason 的 ordinal（None=0, SpeechCompleted=1, HeadSilenceTimeout=2,
/// MaxDurationReached=3, ExternalStop=4）。仅 state==End 时有意义。
#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeEndReason<'local>(
    mut env: JNIEnv<'local>, _class: JClass<'local>, handle: jlong,
) -> jint {
    catch_panic(&mut env, || {
        let Some(v) = (unsafe { handle_ref(handle) }) else { return 0; };
        end_reason_ordinal(v.state())
    })
}

fn state_ordinal(s: State) -> jint {
    use fgvad::State::*;
    match s {
        Idle => 0, Detecting => 1, Started => 2, Voiced => 3,
        Trailing => 4, End(_) => 5,
    }
}

fn end_reason_ordinal(s: State) -> jint {
    use fgvad::{EndReason::*, State::*};
    match s {
        End(SpeechCompleted) => 1,
        End(HeadSilenceTimeout) => 2,
        End(MaxDurationReached) => 3,
        End(ExternalStop) => 4,
        _ => 0,
    }
}
```

**重要**：上面假设 `fgvad::State::End` 携带 `EndReason`。如果实际 State 定义不同（比如 `End` 单独存在、`end_reason` 是 FgVad 上的方法），调整 `state_ordinal` 和 `end_reason_ordinal`。检查方式：`grep -n "pub enum State" src/state_machine.rs`。

- [ ] **Step 2: 编译**

Run: `./scripts/build-android.sh`
Expected: 编过。

- [ ] **Step 3: Commit**

```bash
git add examples/android/fgvad-jni/src/lib.rs
git commit -m "fgvad-jni: start/stop/reset/state/endReason"
```

---

### Task 8: JNI 实现：process（核心）

**Files:**
- Modify: `examples/android/fgvad-jni/src/lib.rs`

- [ ] **Step 1: 实现 nativeProcess**

```rust
use jni::objects::{JObject, JShortArray};
use jni::sys::{jobjectArray, jsize};

/// 入参：handle, samples (jshort[]), count (jint)。
/// 返回：Object[]，每个元素是 io/fengur/fgvad/Result 实例。NULL 表示失败。
///
/// 内存策略：samples 用 GetShortArrayCritical 零拷贝读；audioSamples 仅
/// SentenceEnded/SentenceForceCut 时分配 Java short[] 拷贝。
#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeProcess<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    handle: jlong,
    samples: JShortArray<'local>,
    count: jint,
) -> jobjectArray {
    catch_panic(&mut env, || {
        let Some(vad) = (unsafe { handle_mut(handle) }) else {
            return std::ptr::null_mut();
        };
        let count = count.max(0) as usize;

        // 读 samples 切片（最多 count 个）
        let pcm: Vec<i16> = if count == 0 {
            Vec::new()
        } else {
            // GetShortArrayElements 提交一份拷贝。jni crate 0.21 暴露的安全接口。
            // GetShortArrayCritical 在 jni crate 里没有 safe 包装；直接 elements 也够用——
            // 一次 process 才 1024 i16 (2KB)，拷贝可忽略。
            let arr = match env.get_array_elements(&samples, jni::objects::ReleaseMode::NoCopyBack) {
                Ok(a) => a,
                Err(_) => return std::ptr::null_mut(),
            };
            let len = arr.len().min(count);
            arr[..len].to_vec()
        };

        let results = match vad.process(&pcm) {
            Ok(r) => r,
            Err(_) => return std::ptr::null_mut(),
        };

        // 找 io/fengur/fgvad/Result 类
        let result_class = match env.find_class("io/fengur/fgvad/Result") {
            Ok(c) => c,
            Err(_) => return std::ptr::null_mut(),
        };

        let arr = match env.new_object_array(results.len() as jsize, &result_class, JObject::null()) {
            Ok(a) => a,
            Err(_) => return std::ptr::null_mut(),
        };

        for (i, r) in results.iter().enumerate() {
            let obj = build_result_object(&mut env, &result_class, r);
            if let Ok(obj) = obj {
                let _ = env.set_object_array_element(&arr, i as jsize, obj);
            }
        }

        arr.into_raw()
    })
}

fn build_result_object<'local>(
    env: &mut JNIEnv<'local>,
    cls: &JClass<'local>,
    r: &fgvad::VadResult,
) -> jni::errors::Result<JObject<'local>> {
    use fgvad::ResultType;

    let result_type = match r.result_type {
        ResultType::Silence => 0,
        ResultType::SentenceStart => 1,
        ResultType::Active => 2,
        ResultType::SentenceEnd => 3,
    } as jint;

    let event = match r.event {
        None => 0,
        Some(fgvad::Event::SentenceStarted) => 1,
        Some(fgvad::Event::SentenceEnded) => 2,
        Some(fgvad::Event::SentenceForceCut) => 3,
        Some(fgvad::Event::HeadSilenceTimeout) => 4,
        Some(fgvad::Event::MaxDurationReached) => 5,
    } as jint;

    let state_ord = state_ordinal(r.state);
    let end_reason_ord = end_reason_ordinal(r.state);

    // audioSamples：仅 SentenceEnded / SentenceForceCut 时拷贝
    let need_audio = matches!(
        r.event,
        Some(fgvad::Event::SentenceEnded) | Some(fgvad::Event::SentenceForceCut)
    );
    let audio_obj: JObject = if need_audio && !r.audio.is_empty() {
        let arr = env.new_short_array(r.audio.len() as jsize)?;
        env.set_short_array_region(&arr, 0, &r.audio)?;
        arr.into()
    } else {
        JObject::null()
    };

    // 构造 Result(type, event, state, endReason, isSentenceBegin, isSentenceEnd,
    //             streamOffsetSample, audioSamples)
    // 签名：(IIIIZZJ[S)V
    let obj = env.new_object(
        cls,
        "(IIIIZZJ[S)V",
        &[
            jni::objects::JValue::Int(result_type),
            jni::objects::JValue::Int(event),
            jni::objects::JValue::Int(state_ord),
            jni::objects::JValue::Int(end_reason_ord),
            jni::objects::JValue::Bool(if r.is_sentence_begin { 1 } else { 0 }),
            jni::objects::JValue::Bool(if r.is_sentence_end { 1 } else { 0 }),
            jni::objects::JValue::Long(r.stream_offset_sample as jlong),
            jni::objects::JValue::Object(&audio_obj),
        ],
    )?;
    Ok(obj)
}
```

- [ ] **Step 2: 编译**

Run: `./scripts/build-android.sh`
Expected: 编过。

- [ ] **Step 3: Commit**

```bash
git add examples/android/fgvad-jni/src/lib.rs
git commit -m "fgvad-jni: process (sample input + Result[] output, audio for sentence-end events)"
```

---

## Phase 3 — Kotlin library wrapper

### Task 9: 写 Kotlin 库 wrapper（FgVad、Result、enum 们）

**Files:**
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/State.kt`
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/EndReason.kt`
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/Event.kt`
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/ResultType.kt`
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/Result.kt`
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad/FgVad.kt`

> 注意：Kotlin 文件先建着，等 Task 12 起 Android Studio 项目生成后才能编译。这一步只验证文本正确。

- [ ] **Step 1: 创建目录**

Run:
```bash
mkdir -p examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad
```

- [ ] **Step 2: 写枚举**

`State.kt`:
```kotlin
package io.fengur.fgvad

/** 与 fgvad-jni 的 nativeState 返回 ordinal 严格对齐。 */
enum class State { Idle, Detecting, Started, Voiced, Trailing, End }
```

`EndReason.kt`:
```kotlin
package io.fengur.fgvad

enum class EndReason { None, SpeechCompleted, HeadSilenceTimeout, MaxDurationReached, ExternalStop }
```

`Event.kt`:
```kotlin
package io.fengur.fgvad

enum class Event { None, SentenceStarted, SentenceEnded, SentenceForceCut, HeadSilenceTimeout, MaxDurationReached }
```

`ResultType.kt`:
```kotlin
package io.fengur.fgvad

enum class ResultType { Silence, SentenceStart, Active, SentenceEnd }
```

- [ ] **Step 3: 写 Result 数据类**

`Result.kt`:
```kotlin
package io.fengur.fgvad

/**
 * VAD 处理结果。一次 [FgVad.process] 返回 0..N 条。
 *
 * @property audioSamples 仅 SentenceEnded / SentenceForceCut 时 non-null，
 *                       含整句 16 kHz mono i16 PCM。其他事件为 null。
 */
class Result(
    type: Int,
    event: Int,
    state: Int,
    endReason: Int,
    val isSentenceBegin: Boolean,
    val isSentenceEnd: Boolean,
    val streamOffsetSample: Long,
    val audioSamples: ShortArray?,
) {
    val type: ResultType = ResultType.values()[type]
    val event: Event = Event.values()[event]
    val state: State = State.values()[state]
    val endReason: EndReason = EndReason.values()[endReason]

    /** 起始时间（毫秒，自 start 起）。基于 16 kHz 采样率换算。 */
    val startMs: Double get() = streamOffsetSample.toDouble() / 16.0

    val durationMs: Double get() = (audioSamples?.size?.toDouble() ?: 0.0) / 16.0

    val endMs: Double get() = startMs + durationMs
}
```

构造器签名是 `(IIIIZZJ[S)V`——和 Task 8 里 `new_object` 调用对齐：4 个 int（type/event/state/endReason）+ 2 个 boolean + long + short[]。这是 native 端能直接 JNI 构造的形状。

- [ ] **Step 4: 写 FgVad 类**

`FgVad.kt`:
```kotlin
package io.fengur.fgvad

class FgVad private constructor(private var handle: Long) : AutoCloseable {

    init {
        require(handle != 0L) { "fgvad handle is null" }
    }

    companion object {
        init {
            System.loadLibrary("fgvad_android")  // 触发依赖 libten_vad.so 也加载
        }

        fun newShort(headSilenceMs: Int, tailSilenceMs: Int, maxDurationMs: Int): FgVad {
            val h = nativeNewShort(headSilenceMs, tailSilenceMs, maxDurationMs)
            require(h != 0L) { "FgVad.newShort failed" }
            return FgVad(h)
        }

        fun newLong(
            headSilenceMs: Int,
            maxSentenceMs: Int,
            maxSessionMs: Int,
            tailInitMs: Int,
            tailMinMs: Int,
            enableDynamicTail: Boolean,
        ): FgVad {
            val h = nativeNewLong(
                headSilenceMs, maxSentenceMs, maxSessionMs,
                tailInitMs, tailMinMs, enableDynamicTail
            )
            require(h != 0L) { "FgVad.newLong failed" }
            return FgVad(h)
        }

        @JvmStatic external fun nativeVersion(): String

        @JvmStatic external fun nativeNewShort(
            headSilenceMs: Int, tailSilenceMs: Int, maxDurationMs: Int,
        ): Long

        @JvmStatic external fun nativeNewLong(
            headSilenceMs: Int, maxSentenceMs: Int, maxSessionMs: Int,
            tailInitMs: Int, tailMinMs: Int, enableDynamicTail: Boolean,
        ): Long

        @JvmStatic external fun nativeFree(handle: Long)
        @JvmStatic external fun nativeStart(handle: Long)
        @JvmStatic external fun nativeStop(handle: Long)
        @JvmStatic external fun nativeReset(handle: Long)
        @JvmStatic external fun nativeState(handle: Long): Int
        @JvmStatic external fun nativeEndReason(handle: Long): Int
        @JvmStatic external fun nativeProcess(handle: Long, samples: ShortArray, count: Int): Array<Result>?

        fun version(): String = nativeVersion()
    }

    fun start() = nativeStart(handle)
    fun stop() = nativeStop(handle)
    fun reset() = nativeReset(handle)
    fun state(): State = State.values()[nativeState(handle)]
    fun endReason(): EndReason = EndReason.values()[nativeEndReason(handle)]

    fun process(samples: ShortArray, count: Int = samples.size): List<Result> {
        val arr = nativeProcess(handle, samples, count)
            ?: throw IllegalStateException("fgvad process failed")
        return arr.toList()
    }

    override fun close() {
        if (handle != 0L) {
            nativeFree(handle)
            handle = 0L
        }
    }
}
```

- [ ] **Step 5: Commit（文件先入库，等项目生成后会跟着 build）**

```bash
git add examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvad
git commit -m "kotlin: FgVad library wrapper (enums, Result, FgVad)"
```

---

## Phase 4 — Android Studio project scaffold

### Task 10: 用 Android Studio Gradle wrapper 起项目骨架

**Files:**
- Create: `examples/android/FgVadDemo/settings.gradle.kts`
- Create: `examples/android/FgVadDemo/build.gradle.kts` (root)
- Create: `examples/android/FgVadDemo/app/build.gradle.kts`
- Create: `examples/android/FgVadDemo/app/src/main/AndroidManifest.xml`
- Create: `examples/android/FgVadDemo/gradle/wrapper/gradle-wrapper.properties`
- Create: `examples/android/FgVadDemo/gradle.properties`
- Create: `examples/android/FgVadDemo/gradlew` + `gradlew.bat`

- [ ] **Step 1: 用本机的 gradle 自带 wrapper（如果系统里没 gradle，用 `brew install gradle` 或下个 distribution）**

最快：从既有 Android 项目拷一个 `gradle/wrapper/`、`gradlew`、`gradlew.bat`，或者：

```bash
mkdir -p examples/android/FgVadDemo
cd examples/android/FgVadDemo
# 用 SDK 自带的 gradle 跑一次 wrapper init 命令也行
# 或者从 https://services.gradle.org/distributions/ 下载 gradle-8.7-bin.zip 解压临时用一次
gradle wrapper --gradle-version 8.7 || \
  echo "如果系统没 gradle，从 distribution 临时拉一次：" \
       "curl -O https://services.gradle.org/distributions/gradle-8.7-bin.zip"
```

最终目录里要有：`gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`。

- [ ] **Step 2: 写 settings.gradle.kts**

```kotlin
// examples/android/FgVadDemo/settings.gradle.kts
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "FgVadDemo"
include(":app")
```

- [ ] **Step 3: 写 root build.gradle.kts**

```kotlin
// examples/android/FgVadDemo/build.gradle.kts
plugins {
    id("com.android.application") version "8.5.0" apply false
    id("org.jetbrains.kotlin.android") version "2.0.0" apply false
}
```

- [ ] **Step 4: 写 app/build.gradle.kts**

```kotlin
// examples/android/FgVadDemo/app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.fengur.fgvaddemo"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.fengur.fgvaddemo"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        ndk { abiFilters += "arm64-v8a" }
    }

    buildFeatures {
        viewBinding = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 5: 写 gradle.properties**

```properties
# examples/android/FgVadDemo/gradle.properties
android.useAndroidX=true
kotlin.code.style=official
org.gradle.jvmargs=-Xmx2048m
```

- [ ] **Step 6: 写 AndroidManifest.xml（含权限和 Activity 占位）**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.RECORD_AUDIO" />

    <application
        android:label="FgVad Demo"
        android:theme="@style/Theme.MaterialComponents.DayNight.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

- [ ] **Step 7: 创建占位 MainActivity（编译能通过即可，后续填内容）**

```bash
mkdir -p examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo
mkdir -p examples/android/FgVadDemo/app/src/main/res/layout
mkdir -p examples/android/FgVadDemo/app/src/main/res/values
```

`app/src/main/java/io/fengur/fgvaddemo/MainActivity.kt`:
```kotlin
package io.fengur.fgvaddemo

import android.app.Activity
import android.os.Bundle
import io.fengur.fgvad.FgVad

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 烟测：触发 System.loadLibrary，记录版本号
        android.util.Log.i("FgVadDemo", "fgvad version=${FgVad.version()}")
    }
}
```

`app/src/main/res/values/strings.xml`:
```xml
<resources>
    <string name="app_name">FgVad Demo</string>
</resources>
```

- [ ] **Step 8: 跑一次 build 看编译**

Run:
```bash
cd examples/android/FgVadDemo
./gradlew :app:assembleDebug 2>&1 | tail -20
```

Expected: BUILD SUCCESSFUL，`app/build/outputs/apk/debug/app-debug.apk` 出现。

如果 `System.loadLibrary("fgvad_android")` 报 `UnsatisfiedLinkError`：先确认 `app/src/main/jniLibs/arm64-v8a/libfgvad_android.so` + `libten_vad.so` 存在（应该是 Task 5 build-android.sh 拷进去的）。

- [ ] **Step 9: Commit**

```bash
cd /Users/fengurwang/Desktop/OldJob/fgvad
git add examples/android/FgVadDemo
git commit -m "android: gradle scaffold + minimal MainActivity"
```

---

### Task 11: 装到真机做生命周期烟测

**Files:** none

- [ ] **Step 1: 装 APK**

Run:
```bash
cd examples/android/FgVadDemo
./gradlew :app:installDebug
```

Expected: 在 `adb devices -l` 列出的真机上装上 `io.fengur.fgvaddemo`。

- [ ] **Step 2: 启动 + 看 logcat**

Run:
```bash
adb logcat -c
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
adb logcat -d FgVadDemo:I '*:E' | head -20
```

Expected:
- 看到 `FgVadDemo: fgvad version=0.1.0`
- 没有 `UnsatisfiedLinkError`
- 没有 native crash

如果 fail：
- 库找不到：`adb shell run-as io.fengur.fgvaddemo ls /data/app/...lib/arm64/`，查 .so 是否在
- 符号缺失：`adb logcat -d *:E | grep dlopen`，再回头查 build-android.sh 链接信息

- [ ] **Step 3: 跑一遍 lifecycle 烟测——加一段临时代码**

临时改 `MainActivity.kt::onCreate`：

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    android.util.Log.i("FgVadDemo", "fgvad version=${FgVad.version()}")

    val vad = FgVad.newLong(
        headSilenceMs = 3000,
        maxSentenceMs = 30_000,
        maxSessionMs = 0,
        tailInitMs = 2000,
        tailMinMs = 600,
        enableDynamicTail = true,
    )
    android.util.Log.i("FgVadDemo", "state before start: ${vad.state()}")
    vad.start()
    android.util.Log.i("FgVadDemo", "state after start: ${vad.state()}")
    val results = vad.process(ShortArray(1600))  // 100ms 静音
    android.util.Log.i("FgVadDemo", "process returned ${results.size} results")
    vad.close()
    android.util.Log.i("FgVadDemo", "fgvad closed")
}
```

Run: `./gradlew :app:installDebug` + 启动 + `adb logcat -d FgVadDemo:I`

Expected:
- `state before start: Idle`
- `state after start: Detecting`
- `process returned <N> results`（N 通常 0-1）
- `fgvad closed`
- 整个过程无 crash

- [ ] **Step 4: 把临时代码删回去（保留 version 那一行）**

- [ ] **Step 5: Commit**

```bash
git add -A examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/MainActivity.kt
git commit -m "android: lifecycle smoke test passed on device"
```

---

## Phase 5 — 录音通链路 + 日志写文件

### Task 12: DemoLogger（写文件）

**Files:**
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/DemoLogger.kt`

- [ ] **Step 1: 写 DemoLogger.kt**

```kotlin
package io.fengur.fgvaddemo

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 把调试日志写到固定文件路径：
 *   /sdcard/Android/data/io.fengur.fgvaddemo/files/run.log
 *
 * App 启动 truncate。Claude 端 `adb pull` 出来 Read。
 * 不依赖 logcat（要可持久化、可跨 iOS/Android 比对）。
 */
class DemoLogger private constructor(private val file: File) {

    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    fun i(tag: String, msg: String) = write("I", tag, msg)
    fun w(tag: String, msg: String) = write("W", tag, msg)
    fun e(tag: String, msg: String) = write("E", tag, msg)

    @Synchronized
    private fun write(level: String, tag: String, msg: String) {
        val line = "${fmt.format(Date())} $level/$tag: $msg\n"
        file.appendText(line)
        when (level) {
            "I" -> android.util.Log.i(tag, msg)
            "W" -> android.util.Log.w(tag, msg)
            "E" -> android.util.Log.e(tag, msg)
        }
    }

    companion object {
        @Volatile private var instance: DemoLogger? = null

        fun init(ctx: Context): DemoLogger {
            val existing = instance
            if (existing != null) return existing
            synchronized(this) {
                val again = instance
                if (again != null) return again
                val f = File(ctx.getExternalFilesDir(null), "run.log")
                f.parentFile?.mkdirs()
                f.writeText("")  // truncate on app start
                val l = DemoLogger(f)
                instance = l
                return l
            }
        }

        fun get(): DemoLogger = instance!!
    }
}
```

- [ ] **Step 2: MainActivity 里初始化**

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    DemoLogger.init(this)
    DemoLogger.get().i("App", "fgvad version=${FgVad.version()}")
}
```

- [ ] **Step 3: 装机验证**

Run:
```bash
cd examples/android/FgVadDemo
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
sleep 2
adb pull /sdcard/Android/data/io.fengur.fgvaddemo/files/run.log /tmp/run.log
cat /tmp/run.log
```

Expected: 看到 `HH:MM:SS.MMM I/App: fgvad version=0.1.0`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "android: DemoLogger writes to run.log on external files dir"
```

---

### Task 13: AudioRecorder + 接 fgvad 输出事件流

**Files:**
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/AudioRecorder.kt`
- Modify: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/MainActivity.kt`

- [ ] **Step 1: 写 AudioRecorder.kt**

```kotlin
package io.fengur.fgvaddemo

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat

class AudioRecorder(private val onPcm: (samples: ShortArray, count: Int) -> Unit) {

    private var thread: Thread? = null
    @Volatile private var running = false
    private var rec: AudioRecord? = null

    fun isPermissionGranted(ctx: android.content.Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    @Suppress("MissingPermission")
    fun start() {
        if (running) return
        val sampleRate = 16_000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufBytes = (minBuf * 2).coerceAtLeast(4096)

        rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION, // 比 MIC 走更轻处理
            sampleRate, channelConfig, audioFormat, bufBytes,
        )
        rec?.startRecording()
        running = true

        thread = Thread {
            val chunk = ShortArray(1024)  // 64ms @ 16kHz
            while (running) {
                val n = rec?.read(chunk, 0, chunk.size) ?: 0
                if (n > 0) onPcm(chunk, n)
            }
        }.apply {
            name = "AudioRecorder"
            start()
        }
    }

    fun stop() {
        if (!running) return
        running = false
        thread?.join(500)
        thread = null
        rec?.stop()
        rec?.release()
        rec = null
    }
}
```

- [ ] **Step 2: 改 MainActivity，权限 + start/stop 临时按键**

```kotlin
package io.fengur.fgvaddemo

import android.Manifest
import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import androidx.core.app.ActivityCompat
import io.fengur.fgvad.FgVad

class MainActivity : Activity() {

    private lateinit var logger: DemoLogger
    private var vad: FgVad? = null
    private val recorder = AudioRecorder { samples, count ->
        val v = vad ?: return@AudioRecorder
        val results = v.process(samples, count)
        for (r in results) {
            if (r.event != io.fengur.fgvad.Event.None) {
                logger.i("VAD", "event=${r.event} state=${r.state} startMs=${r.startMs.toInt()} dur=${r.durationMs.toInt()}ms")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logger = DemoLogger.init(this)
        logger.i("App", "fgvad version=${FgVad.version()}")

        if (!recorder.isPermissionGranted(this)) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.RECORD_AUDIO), 1,
            )
        }

        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val startBtn = Button(this).apply { text = "Start (long mode)" }
        val stopBtn = Button(this).apply { text = "Stop" }
        root.addView(startBtn)
        root.addView(stopBtn)
        setContentView(root)

        startBtn.setOnClickListener {
            vad = FgVad.newLong(3000, 30_000, 0, 2000, 600, true)
            vad!!.start()
            recorder.start()
            logger.i("App", "started")
        }
        stopBtn.setOnClickListener {
            recorder.stop()
            vad?.stop()
            logger.i("App", "stopped, endReason=${vad?.endReason()}")
            vad?.close()
            vad = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        recorder.stop()
        vad?.close()
        vad = null
    }
}
```

- [ ] **Step 3: 装机 + 真口测**

Run:
```bash
cd examples/android/FgVadDemo
../../../scripts/build-android.sh  # 确保 .so 在
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
# 同意权限弹窗
# 点 Start，说"喂喂喂今天天气真好"，停 1 秒，说"再试一句"，再停，点 Stop
sleep 15
adb pull /sdcard/Android/data/io.fengur.fgvaddemo/files/run.log /tmp/run.log
cat /tmp/run.log
```

Expected `run.log` 里：
- `App: started`
- 至少一对 `VAD: event=SentenceStarted`...`event=SentenceEnded`
- `App: stopped, endReason=ExternalStop`

如果 SentenceStarted 一直不出：检查权限是否给了；检查 mic 不是 mute 的；用 `adb shell dumpsys media.audio_flinger` 看不看得到 input 流。

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "android: mic → AudioRecord → fgvad pipeline producing event stream"
```

---

## Phase 6 — UI 1:1 翻 iOS

### Task 14: 主屏 XML 布局（params + buttons + status）

**Files:**
- Create: `examples/android/FgVadDemo/app/src/main/res/layout/activity_main.xml`
- Create: `examples/android/FgVadDemo/app/src/main/res/layout/row_param.xml`

- [ ] **Step 1: 写 activity_main.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">

    <com.google.android.material.button.MaterialButtonToggleGroup
        android:id="@+id/modeGroup"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        app:singleSelection="true"
        app:selectionRequired="true">
        <com.google.android.material.button.MaterialButton
            android:id="@+id/modeShort"
            style="?attr/materialButtonOutlinedStyle"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="短时 Short" />
        <com.google.android.material.button.MaterialButton
            android:id="@+id/modeLong"
            style="?attr/materialButtonOutlinedStyle"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="长时 Long" />
    </com.google.android.material.button.MaterialButtonToggleGroup>

    <TextView
        android:id="@+id/modeHint"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="12sp"
        android:layout_marginTop="4dp"
        android:gravity="center"
        android:textColor="?android:attr/textColorSecondary" />

    <LinearLayout
        android:id="@+id/paramsContainer"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:layout_marginTop="12dp" />

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:layout_marginTop="12dp">
        <Button
            android:id="@+id/recordBtn"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="开始录音" />
        <Button
            android:id="@+id/loadAudioBtn"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:layout_marginStart="8dp"
            android:text="加载测试音频" />
    </LinearLayout>

    <TextView
        android:id="@+id/statusLabel"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textSize="14sp"
        android:layout_marginTop="12dp" />

    <androidx.recyclerview.widget.RecyclerView
        android:id="@+id/sentenceList"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginTop="12dp" />

</LinearLayout>
```

- [ ] **Step 2: 写参数行 row_param.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:padding="4dp">
    <TextView
        android:id="@+id/paramName"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="2"
        android:textSize="13sp" />
    <EditText
        android:id="@+id/paramValue"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:inputType="number"
        android:textSize="14sp" />
    <TextView
        android:id="@+id/paramUnit"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:paddingStart="8dp"
        android:textSize="13sp" />
</LinearLayout>
```

- [ ] **Step 3: 编译**

Run: `./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL。

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "android: activity_main + row_param layouts"
```

---

### Task 15: MainActivity 接 UI（mode/params/start/stop/status）

**Files:**
- Modify: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/MainActivity.kt`

> 这一节较长（~250 行），把 iOS `ViewController.swift` 模式切换 / 参数读取 / 状态展示那块翻成 Kotlin。代码全量给出，executor 直接整体替换。

- [ ] **Step 1: 整体替换 MainActivity**

```kotlin
package io.fengur.fgvaddemo

import android.Manifest
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.widget.*
import androidx.core.app.ActivityCompat
import com.google.android.material.button.MaterialButtonToggleGroup
import io.fengur.fgvad.EndReason
import io.fengur.fgvad.Event
import io.fengur.fgvad.FgVad

class MainActivity : Activity() {

    private enum class Mode { SHORT, LONG }
    private var currentMode = Mode.SHORT

    private lateinit var logger: DemoLogger
    private val ui = Handler(Looper.getMainLooper())

    private var vad: FgVad? = null
    private var sentenceCount = 0
    private var startMs = 0L

    // 短时参数
    private val shortHead = NumField("head_silence_timeout", "3000")
    private val shortTail = NumField("tail_silence", "2000")
    private val shortMax  = NumField("max_duration", "30000")

    // 长时参数
    private val longHead     = NumField("head_silence_timeout", "3000")
    private val longMaxSent  = NumField("max_sentence_duration", "30000")
    private val longTailInit = NumField("tail_silence_initial", "2000")
    private val longTailMin  = NumField("tail_silence_min", "600")
    private var longDynamic  = true

    private lateinit var paramsContainer: LinearLayout
    private lateinit var modeHint: TextView
    private lateinit var statusLabel: TextView
    private lateinit var recordBtn: Button
    private lateinit var loadAudioBtn: Button
    private lateinit var sentenceList: androidx.recyclerview.widget.RecyclerView

    private val sentenceAdapter = SentenceAdapter()
    private val recorder = AudioRecorder { samples, count -> onPcm(samples, count) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logger = DemoLogger.init(this)
        logger.i("App", "fgvad version=${FgVad.version()}")
        setContentView(R.layout.activity_main)

        modeHint = findViewById(R.id.modeHint)
        paramsContainer = findViewById(R.id.paramsContainer)
        statusLabel = findViewById(R.id.statusLabel)
        recordBtn = findViewById(R.id.recordBtn)
        loadAudioBtn = findViewById(R.id.loadAudioBtn)
        sentenceList = findViewById(R.id.sentenceList)
        sentenceList.layoutManager = androidx.recyclerview.widget.LinearLayoutManager(this)
        sentenceList.adapter = sentenceAdapter

        val modeGroup: MaterialButtonToggleGroup = findViewById(R.id.modeGroup)
        modeGroup.check(R.id.modeShort)
        modeGroup.addOnButtonCheckedListener { _, id, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            currentMode = if (id == R.id.modeShort) Mode.SHORT else Mode.LONG
            applyMode()
        }
        applyMode()

        recordBtn.setOnClickListener { toggleRecord() }
        loadAudioBtn.setOnClickListener { showLoadAudioDialog() }

        if (!recorder.isPermissionGranted(this)) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.RECORD_AUDIO), 1,
            )
        }

        statusLabel.text = "状态：就绪"
    }

    private fun applyMode() {
        paramsContainer.removeAllViews()
        when (currentMode) {
            Mode.SHORT -> {
                modeHint.text = "短时：尾静音达标即结束整个会话；适合命令/查询"
                addRow(shortHead)
                addRow(shortTail)
                addRow(shortMax)
            }
            Mode.LONG -> {
                modeHint.text = "长时：自动切句，外部 stop 才结束；适合听写/连续口述"
                addRow(longHead)
                addRow(longMaxSent)
                addRow(longTailInit)
                addRow(longTailMin)
                addDynamicSwitch()
            }
        }
    }

    private fun addRow(field: NumField) {
        val row = layoutInflater.inflate(R.layout.row_param, paramsContainer, false)
        row.findViewById<TextView>(R.id.paramName).text = field.name
        val edit = row.findViewById<EditText>(R.id.paramValue)
        edit.setText(field.value)
        edit.inputType = InputType.TYPE_CLASS_NUMBER
        edit.addTextChangedListener(object : android.text.TextWatcher {
            override fun afterTextChanged(s: android.text.Editable?) {
                field.value = s?.toString() ?: ""
            }
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
        })
        row.findViewById<TextView>(R.id.paramUnit).text = "ms"
        paramsContainer.addView(row)
    }

    private fun addDynamicSwitch() {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(4, 4, 4, 4)
        }
        val label = TextView(this).apply { text = "启用动态尾端点曲线"; textSize = 13f }
        val sw = androidx.appcompat.widget.SwitchCompat(this).apply {
            isChecked = longDynamic
            setOnCheckedChangeListener { _, checked -> longDynamic = checked }
        }
        row.addView(label, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(sw)
        paramsContainer.addView(row)
    }

    private fun toggleRecord() {
        if (vad == null) {
            startSession()
        } else {
            stopSession(reason = "ExternalStop")
        }
    }

    private fun startSession() {
        sentenceCount = 0
        startMs = System.currentTimeMillis()
        sentenceAdapter.clear()

        vad = when (currentMode) {
            Mode.SHORT -> FgVad.newShort(
                shortHead.intValue(3000),
                shortTail.intValue(2000),
                shortMax.intValue(30_000),
            )
            Mode.LONG -> FgVad.newLong(
                longHead.intValue(3000),
                longMaxSent.intValue(30_000),
                0,
                longTailInit.intValue(2000),
                longTailMin.intValue(600),
                longDynamic,
            )
        }
        vad!!.start()
        recorder.start()
        recordBtn.text = "停止录音"
        statusLabel.text = "状态：录音中 · 0 句"
        logger.i("App", "session start mode=$currentMode")
    }

    private fun stopSession(reason: String) {
        recorder.stop()
        vad?.stop()
        val end = vad?.endReason() ?: EndReason.None
        logger.i("App", "session stop endReason=$end ($reason)")
        vad?.close()
        vad = null
        recordBtn.text = "开始录音"
        ui.post { statusLabel.text = "状态：${reasonText(end)} · $sentenceCount 句" }
    }

    private fun reasonText(r: EndReason): String = when (r) {
        EndReason.None -> "已停止"
        EndReason.SpeechCompleted -> "完成"
        EndReason.HeadSilenceTimeout -> "头部超时"
        EndReason.MaxDurationReached -> "时长上限"
        EndReason.ExternalStop -> "用户停止"
    }

    private fun onPcm(samples: ShortArray, count: Int) {
        val v = vad ?: return
        val results = v.process(samples, count)
        if (results.isEmpty()) return
        ui.post { handleResults(results) }
    }

    private fun handleResults(results: List<io.fengur.fgvad.Result>) {
        for (r in results) {
            if (r.event != Event.None) {
                logger.i("VAD", "event=${r.event} state=${r.state} startMs=${r.startMs.toInt()}")
            }
            if (r.event == Event.SentenceEnded || r.event == Event.SentenceForceCut) {
                sentenceCount += 1
                sentenceAdapter.add(
                    Sentence(
                        index = sentenceCount,
                        startMs = r.startMs,
                        endMs = r.endMs,
                        endEvent = r.event,
                        audio = r.audioSamples,
                    )
                )
                statusLabel.text = "状态：录音中 · $sentenceCount 句"
            }
            // 长时模式 HeadSilenceTimeout 是通知事件，session 不结束
            if (r.state == io.fengur.fgvad.State.End) {
                stopSession(reason = "natural-end")
            }
        }
    }

    private fun showLoadAudioDialog() {
        // Task 18 实现
        Toast.makeText(this, "TODO: load audio dialog", Toast.LENGTH_SHORT).show()
    }

    override fun onDestroy() {
        super.onDestroy()
        recorder.stop()
        vad?.close()
        vad = null
    }
}

private class NumField(val name: String, var value: String) {
    fun intValue(default: Int): Int = value.toIntOrNull() ?: default
}
```

- [ ] **Step 2: 暂时占位 SentenceAdapter / Sentence**

下一个 task 真写。这里先放占位让 MainActivity 能编。新建 `Sentence.kt` + `SentenceAdapter.kt`：

`Sentence.kt`:
```kotlin
package io.fengur.fgvaddemo

import io.fengur.fgvad.Event

data class Sentence(
    val index: Int,
    val startMs: Double,
    val endMs: Double,
    val endEvent: Event,
    val audio: ShortArray?,
)
```

`SentenceAdapter.kt`:
```kotlin
package io.fengur.fgvaddemo

import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class SentenceAdapter : RecyclerView.Adapter<SentenceAdapter.VH>() {

    private val items = mutableListOf<Sentence>()

    fun clear() { val n = items.size; items.clear(); notifyItemRangeRemoved(0, n) }
    fun add(s: Sentence) { items.add(s); notifyItemInserted(items.size - 1) }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val tv = TextView(parent.context).apply {
            textSize = 13f
            setPadding(8, 12, 8, 12)
        }
        return VH(tv)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val s = items[position]
        holder.tv.text = "Sentence ${s.index} | ${s.endEvent} | ${formatMs(s.startMs)} - ${formatMs(s.endMs)}"
    }

    override fun getItemCount(): Int = items.size

    class VH(val tv: TextView) : RecyclerView.ViewHolder(tv)

    companion object {
        fun formatMs(ms: Double): String {
            val total = ms.toInt()
            val m = total / 60_000
            val s = (total % 60_000) / 1_000
            val mil = total % 1_000
            return "%02d:%02d.%03d".format(m, s, mil)
        }
    }
}
```

- [ ] **Step 3: 编译 + 装机 + 真口测**

Run:
```bash
cd /Users/fengurwang/Desktop/OldJob/fgvad
./scripts/build-android.sh
cd examples/android/FgVadDemo
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
```

UI 操作：
- 切到长时模式
- 点开始录音
- 说 3 句话，每句之间停顿 ~3 秒
- 点停止录音

Expected:
- 列表里出现 3 行 sentence
- 状态行最后显示 `状态：用户停止 · 3 句`
- run.log 里能看到 SentenceStarted/SentenceEnded 配对

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "android: full UI – mode/params/record/sentence list (no playback yet)"
```

---

### Task 16: 按句试听（AudioTrack）

**Files:**
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/SentencePlayer.kt`
- Create: `examples/android/FgVadDemo/app/src/main/res/layout/row_sentence.xml`
- Modify: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/SentenceAdapter.kt`

- [ ] **Step 1: 写 SentencePlayer.kt**

```kotlin
package io.fengur.fgvaddemo

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack

object SentencePlayer {
    @Volatile private var current: AudioTrack? = null

    fun play(samples: ShortArray) {
        stop()
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(16_000)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(samples.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        track.write(samples, 0, samples.size)
        track.play()
        current = track
    }

    fun stop() {
        current?.let {
            try { it.stop() } catch (_: Throwable) {}
            it.release()
        }
        current = null
    }
}
```

- [ ] **Step 2: 写 row_sentence.xml**

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="horizontal"
    android:gravity="center_vertical"
    android:paddingHorizontal="8dp"
    android:paddingVertical="10dp"
    android:background="?android:attr/selectableItemBackground">
    <TextView
        android:id="@+id/sentenceTitle"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:textSize="13sp" />
    <Button
        android:id="@+id/playBtn"
        style="?attr/buttonBarButtonStyle"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="▶" />
</LinearLayout>
```

- [ ] **Step 3: 改 SentenceAdapter 用真布局**

```kotlin
package io.fengur.fgvaddemo

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class SentenceAdapter : RecyclerView.Adapter<SentenceAdapter.VH>() {

    private val items = mutableListOf<Sentence>()

    fun clear() { val n = items.size; items.clear(); notifyItemRangeRemoved(0, n) }
    fun add(s: Sentence) { items.add(s); notifyItemInserted(items.size - 1) }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.row_sentence, parent, false)
        return VH(v)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val s = items[position]
        holder.title.text = "Sentence ${s.index} | ${s.endEvent} | ${formatMs(s.startMs)} - ${formatMs(s.endMs)}"
        holder.play.isEnabled = s.audio != null
        holder.play.setOnClickListener {
            s.audio?.let { SentencePlayer.play(it) }
        }
    }

    override fun getItemCount(): Int = items.size

    class VH(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.sentenceTitle)
        val play: Button = view.findViewById(R.id.playBtn)
    }

    companion object {
        fun formatMs(ms: Double): String {
            val total = ms.toInt()
            val m = total / 60_000
            val s = (total % 60_000) / 1_000
            val mil = total % 1_000
            return "%02d:%02d.%03d".format(m, s, mil)
        }
    }
}
```

- [ ] **Step 4: 装机 + 试听**

Run: `./scripts/build-android.sh && cd examples/android/FgVadDemo && ./gradlew :app:installDebug`

操作：长时模式录 3 句，停止，逐条点 ▶。

Expected: 听到对应句子的录音回放，听感与 iOS demo 同操作一致。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "android: per-sentence playback via AudioTrack"
```

---

## Phase 7 — 加载测试 WAV 重跑

### Task 17: WavReader

**Files:**
- Create: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/WavReader.kt`

- [ ] **Step 1: 写 WavReader.kt**

```kotlin
package io.fengur.fgvaddemo

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

object WavReader {

    /**
     * 读 WAV 文件成 i16 mono PCM（16 kHz）。不支持转换——文件本身必须是
     * RIFF / 16 kHz / mono / 16-bit PCM，否则抛 [IllegalArgumentException]。
     */
    fun read(input: InputStream): ShortArray {
        val all = input.readBytes()
        require(all.size >= 44) { "wav too short" }
        val bb = ByteBuffer.wrap(all).order(ByteOrder.LITTLE_ENDIAN)
        require(String(all, 0, 4) == "RIFF") { "not RIFF" }
        require(String(all, 8, 4) == "WAVE") { "not WAVE" }

        // 简化：固定格式校验（fmt 块在 12 起，紧跟 data）
        require(String(all, 12, 4) == "fmt ") { "expected fmt at 12" }
        val fmtSize = bb.getInt(16)
        val audioFormat = bb.getShort(20).toInt() and 0xFFFF
        val channels = bb.getShort(22).toInt() and 0xFFFF
        val sampleRate = bb.getInt(24)
        val bitsPerSample = bb.getShort(34).toInt() and 0xFFFF
        require(audioFormat == 1) { "audioFormat=$audioFormat (must be PCM=1)" }
        require(channels == 1) { "channels=$channels (must be 1)" }
        require(sampleRate == 16_000) { "sampleRate=$sampleRate (must be 16000)" }
        require(bitsPerSample == 16) { "bitsPerSample=$bitsPerSample (must be 16)" }

        // 找 data 块
        var pos = 20 + fmtSize
        while (pos + 8 <= all.size) {
            val id = String(all, pos, 4)
            val size = bb.getInt(pos + 4)
            if (id == "data") {
                val nBytes = size.coerceAtMost(all.size - pos - 8)
                val nSamples = nBytes / 2
                val out = ShortArray(nSamples)
                val sb = bb.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                sb.position(pos + 8)
                sb.asShortBuffer().get(out)
                return out
            }
            pos += 8 + size
        }
        throw IllegalArgumentException("no data chunk")
    }
}
```

- [ ] **Step 2: 编译**

Run: `./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "android: WavReader (RIFF / mono / 16k / i16 only)"
```

---

### Task 18: "加载测试音频"对话框 + 重跑流水线

**Files:**
- Modify: `examples/android/FgVadDemo/app/src/main/java/io/fengur/fgvaddemo/MainActivity.kt`

- [ ] **Step 1: bundle 短测试 WAV 到 assets**

Run:
```bash
cd /Users/fengurwang/Desktop/OldJob/fgvad
mkdir -p examples/android/FgVadDemo/app/src/main/assets/short
cp test-data/short/*.wav examples/android/FgVadDemo/app/src/main/assets/short/
```

- [ ] **Step 2: 把长 yixi push 到设备**

```bash
adb shell mkdir -p /sdcard/Android/data/io.fengur.fgvaddemo/files/long
adb push test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
```

- [ ] **Step 3: 实现 showLoadAudioDialog 和 runAnalyze**

替换 MainActivity 里的 `showLoadAudioDialog` 占位 + 添加 `runAnalyze`：

```kotlin
private fun showLoadAudioDialog() {
    val items = mutableListOf<Pair<String, () -> java.io.InputStream>>()

    // 1) bundled assets
    val list = assets.list("short") ?: emptyArray()
    for (name in list.sorted()) {
        items.add("[assets] short/$name" to { assets.open("short/$name") })
    }

    // 2) external long
    val longDir = java.io.File(getExternalFilesDir(null), "long")
    if (longDir.exists()) {
        for (f in longDir.listFiles { _, n -> n.endsWith(".wav") } ?: emptyArray()) {
            items.add("[external] long/${f.name}" to { f.inputStream() })
        }
    }

    if (items.isEmpty()) {
        Toast.makeText(this, "无测试音频。先 adb push 到 long/，或确认 assets/short/ 有 WAV。", Toast.LENGTH_LONG).show()
        return
    }

    val labels = items.map { it.first }.toTypedArray()
    android.app.AlertDialog.Builder(this)
        .setTitle("选择测试音频")
        .setItems(labels) { _, idx ->
            val (label, opener) = items[idx]
            Thread {
                try {
                    val pcm = opener().use { WavReader.read(it) }
                    ui.post { runAnalyze(label, pcm) }
                } catch (e: Throwable) {
                    logger.e("App", "wav read failed: ${e.message}")
                    ui.post { Toast.makeText(this, "读 WAV 失败: ${e.message}", Toast.LENGTH_LONG).show() }
                }
            }.start()
        }
        .show()
}

private fun runAnalyze(label: String, pcm: ShortArray) {
    if (vad != null) {
        Toast.makeText(this, "请先停止录音", Toast.LENGTH_SHORT).show()
        return
    }
    sentenceCount = 0
    sentenceAdapter.clear()
    statusLabel.text = "状态：解析中… ($label)"
    logger.i("App", "runAnalyze start: $label, ${pcm.size} samples")

    // 后台跑：把 pcm 切成 chunk 送 fgvad
    val v = when (currentMode) {
        Mode.SHORT -> FgVad.newShort(
            shortHead.intValue(3000), shortTail.intValue(2000), shortMax.intValue(30_000),
        )
        Mode.LONG -> FgVad.newLong(
            longHead.intValue(3000), longMaxSent.intValue(30_000), 0,
            longTailInit.intValue(2000), longTailMin.intValue(600), longDynamic,
        )
    }
    v.start()
    Thread {
        val chunkSize = 1024
        var offset = 0
        var collected = 0
        while (offset < pcm.size) {
            val n = minOf(chunkSize, pcm.size - offset)
            val chunk = if (offset == 0 && n == pcm.size) pcm else pcm.copyOfRange(offset, offset + n)
            val results = v.process(chunk, n)
            for (r in results) {
                if (r.event != Event.None) {
                    logger.i("VAD", "event=${r.event} startMs=${r.startMs.toInt()}")
                }
                if (r.event == Event.SentenceEnded || r.event == Event.SentenceForceCut) {
                    collected += 1
                    val captured = collected
                    val rr = r
                    ui.post {
                        sentenceCount = captured
                        sentenceAdapter.add(
                            Sentence(captured, rr.startMs, rr.endMs, rr.event, rr.audioSamples)
                        )
                        statusLabel.text = "状态：解析中… · $sentenceCount 句"
                    }
                }
            }
            offset += n
        }
        v.stop()
        val end = v.endReason()
        v.close()
        logger.i("App", "runAnalyze done: $label, $collected sentences, endReason=$end")
        ui.post { statusLabel.text = "状态：重跑完成 · $collected 句 · $end" }
    }.start()
}
```

- [ ] **Step 4: 装机 + 短 WAV 重跑测**

Run: `./scripts/build-android.sh && cd examples/android/FgVadDemo && ./gradlew :app:installDebug`

操作：
- 切到短时模式
- 点 "加载测试音频" → 选 `[assets] short/02-normal-utterance.wav`
- 期望：列表出 1 句，状态行 `重跑完成 · 1 句 · SpeechCompleted`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "android: load test audio dialog + reanalyze pipeline"
```

---

## Phase 8 — 验收：iOS baseline 对照

### Task 19: 长 yixi 重跑硬指标验证

**Files:** none（验收 task）

- [ ] **Step 1: 把 yixi push 到设备（如果 Task 18 没 push 过）**

Run:
```bash
adb push test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
```

- [ ] **Step 2: 跑长时 + 动态曲线 ON**

启动 app → 切长时模式 → 参数保持默认（head 3000, max_sent 30000, tail_init 2000, tail_min 600, 动态 ON）→ 加载 `[external] long/yixi-zhuzhiwei-typography.wav` → 等待解析完成（设备速度，估计 2-5 分钟）。

- [ ] **Step 3: 拉日志，统计**

```bash
adb pull /sdcard/Android/data/io.fengur.fgvaddemo/files/run.log /tmp/run.log
echo "=== sentence count ==="
grep -c "event=SentenceEnded\|event=SentenceForceCut" /tmp/run.log
echo "=== ForceCut count ==="
grep -c "event=SentenceForceCut" /tmp/run.log
echo "=== last status ==="
grep "runAnalyze done" /tmp/run.log
```

Expected：
- 总句数 ≈ 85（README 表里的 baseline）
- ForceCut ≤ 6
- 与 iOS demo 同 wav 跑出来的结果应**显著一致**——若总句数差超 ±5、ForceCut 差超 ±2，停下查 bug 不要交付

- [ ] **Step 4: 跑动态曲线 OFF 对照（可选但推荐）**

切动态开关 → 重跑 → 期望 ForceCut 飙到 ~46，证明动态曲线在 Android 上同样起作用。

- [ ] **Step 5: 更新 README 路线图**

修改根 `README.md`：

```markdown
- [x] iOS 库构建支持（device + simulator）
- [x] iOS Demo（最小录音 + VAD）
- [ ] iOS XCFramework 打包脚本（用于对外分发）
- [x] Android 构建支持（NDK + JNI bridge）
- [x] Android Demo（含按句试听 + 测试 WAV 重跑）
```

并在快速上手"跑 macOS Demo"小节后追加 Android 复现命令：

```markdown
### 跑 Android Demo

```bash
cd examples/android/FgVadDemo
../../../scripts/build-android.sh           # 编 fgvad-jni 并拷 .so
adb push ../../../test-data/long/yixi-zhuzhiwei-typography.wav \
  /sdcard/Android/data/io.fengur.fgvaddemo/files/long/
./gradlew :app:installDebug
adb shell am start -n io.fengur.fgvaddemo/.MainActivity
```

启动后：长时模式 → 加载测试音频 → `[external] long/yixi-...` → 等解析完成。
```

- [ ] **Step 6: 写 examples/android/README.md**

```markdown
# fgvad Android Demo

复刻 iOS demo 的 Android 版本。最小子集：

- 短/长时模式切换 + 参数面板
- 麦克风录音（AudioRecord）+ 实时事件流
- 加载测试 WAV 重跑（assets 自带短 case + adb push 长 yixi）
- Sentence list + 按句试听（AudioTrack 直播 i16 PCM）
- 调试日志写文件：`/sdcard/Android/data/io.fengur.fgvaddemo/files/run.log`

## 复现

见根 README.md "跑 Android Demo" 小节。

## 已验证设备

- 小米 luming（25067PYE3C），Android 16，arm64-v8a

## 限制

- 仅 arm64-v8a（armeabi-v7a 32-bit 在路线图）
- min SDK 26
- 录音用 AudioRecord（不用 Oboe）
- 测试音频长 yixi（49MB）不打进 APK，需 adb push
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs: tick Android roadmap; add demo README; baseline verified on luming"
```

---

## Self-Review Checklist

- [x] 设计稿"仓库布局" → Tasks 1-10 全部覆盖
- [x] 设计稿"构建链路" → Tasks 1-4
- [x] 设计稿"JNI 桥的 API 形状" → Tasks 5-9
- [x] 设计稿"UI 设计" → Tasks 14-16
- [x] 设计稿"录音" → Task 13
- [x] 设计稿"测试音频" → Tasks 17-18
- [x] 设计稿"日志" → Task 12
- [x] 设计稿"验证 5 条" → Task 11 (load+lifecycle), Task 13 (mic), Task 19 (yixi baseline), Task 16 (playback), 参数面板生效在 Task 15 操作中可顺手验
- [x] 风险"darwin-x86_64 toolchain 路径" → Task 4 注释里写死
- [x] 风险"JNI throw 处理" → Task 6 catch_panic
- [x] 风险"loadLibrary 顺序" → Task 5 build-android.sh DT_NEEDED 检查 + Task 9 companion init
- [x] 风险"AudioRecord buffer 欠 read" → Task 13 工作线程紧凑设计 + bufBytes ×2

**潜在 placeholder / 类型不一致：**
- Task 7 假设 `State::End(EndReason)`，提示了 `grep "pub enum State"` 校验。如不符，改 ordinal 函数。
- `FgVad.kt` 的 native 方法签名与 fgvad-jni 的 JNI 函数名一一对应（Java_io_fengur_fgvad_FgVad_*）。
- `Result` 构造器签名 `(IIIIZZJ[S)V` 与 Task 8 的 `new_object` 调用对齐。
- 复读：Task 14 row_sentence.xml + Task 16 改 SentenceAdapter 用真布局——一致。

如有发现实施时出入，回头改 spec + plan。
