# fgvad

基于 [ten-vad](https://github.com/TEN-framework/ten-vad) 的智能 VAD 库，在底层神经网络
VAD 之上封装状态机和动态端点策略（思路来源于作者过去的工作经验）。

> 当前阶段：空骨架。真正的封装与 Demo 会在后续 commit 中逐步加入。

## 目标

- 底层引擎：ten-vad（Apache 2.0，神经网络 VAD，16 kHz / 10 ms 帧）
- 封装层：Rust（与 [micvol](https://github.com/Fengur/micvol) 保持一致的风格）
- 第一版平台：macOS arm64
- 产物：`libfgvad.dylib` + `fgvad.h`，随附 `ten_vad.framework`
- 后续分发：XCFramework、CocoaPods、Swift Package Manager

## 构建

```bash
cargo build
cargo test
```

## License

MIT — 详见 [LICENSE](./LICENSE)。底层 ten-vad 遵循 Apache 2.0。
