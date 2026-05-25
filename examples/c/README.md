# fgvad C Demo

纯 C99 + CMake 的命令行工具,演示 fgvad 在不依赖任何 GUI/平台 SDK 的环境下
怎么集成。云端服务、Linux 后台任务、嵌入式集成方可参考本目录的链接方式。

## 构建

只需要 macOS + CMake 3.18+ + Rust toolchain。

```bash
cmake -B build
cmake --build build
```

CMake 会自动触发顶层 `cargo build --release`,产物 `libfgvad.dylib` 落在
`<repo>/target/release/`。可执行文件落在 `examples/c/build/fgvad_cli`。

## 运行

```bash
# 短时模式——命令/查询场景
./build/fgvad_cli short ../../test-data/short/02-normal-utterance.wav

# 长时模式——连续多句听写
./build/fgvad_cli long ../../test-data/long/yixi-zhuzhiwei-typography.wav

# 把每句切成独立 WAV
mkdir -p /tmp/fgvad-out
./build/fgvad_cli long input.wav -o /tmp/fgvad-out
```

## 输出格式

事件流(stdout):

```
[mm:ss.mmm] EventName             state=...
[mm:ss.mmm] SentenceEnded         duration=Nms  end_reason=...
```

末尾一行 Summary 给出句数 / ForceCut 数 / 终态 / 结束原因。

诊断信息("已读入 N 个采样点"等)走 stderr,可单独 `2>/dev/null` 静默。

## 把 fgvad 集成到自己工程

最少需要:

1. `<repo>/include/fgvad.h` 加到 include path
2. `libfgvad.dylib` 或 `libfgvad.a` 加到 link path

### 用 dylib(推荐,零配置)

> 这里有两层 rpath:`my_app` 通过 `-Wl,-rpath` 找到 `libfgvad.dylib`;
> `libfgvad.dylib` 内部已经有 rpath 指向 ten\_vad framework 目录(由 build.rs 编入)。
> 所以集成方**不需要**额外给 my\_app 加 ten-vad 相关路径。

```bash
clang -o my_app my_app.c \
    -I<repo>/include \
    -L<repo>/target/release \
    -lfgvad \
    -Wl,-rpath,<repo>/target/release
```

### 用 staticlib(自己处理 ten-vad)

`libfgvad.a` 不带链接信息,必须自己加 `-framework ten_vad`:

> macOS clang 在 `-L` 路径下同时找到 `.dylib` 和 `.a` 时优先用 dylib。
> 链 staticlib 必须显式给 `.a` 文件的绝对路径(或用 `-Wl,-search_paths_first` 等技巧)。

```bash
clang -o my_app my_app.c \
    -I<repo>/include \
    <repo>/target/release/libfgvad.a \
    -F<repo>/vendor/ten-vad/macOS -framework ten_vad \
    -Wl,-rpath,<repo>/vendor/ten-vad/macOS
```

## 测试

```bash
ctest --test-dir build -V
```

跑 wav_io 模块的单元测试。

## IDE 支持

`examples/c/.clangd` 指向 `build/compile_commands.json`,clangd 集成的 IDE
(VS Code、Neovim、CLion)能自动解析 include path。第一次构建后红波浪自动消失。

## 边界

- 第一版仅 macOS。Linux 支持需要 vendor ten-vad Linux 预编译 +
  `build.rs` 加 `link_linux()` 分支(在主项目 roadmap 里)。
- WAV 解析仅接受 mono / 16kHz / i16,其他格式直接报错。
- 流式 vs 批式:本 demo 一次性把整段 PCM 喂给 `fgvad_process` (简单直观)。
  真实服务端流式接入时,每个网络帧到达后 chunk-by-chunk 调 `fgvad_process` 即可,
  返回的 results 处理逻辑相同。
