# FgVadDemo —— fgvad 的 iOS 测试 / 接入样本

UIKit + 纯 frame 布局,**复用 OC RemoteIO AudioUnit 录音器**(`FGAudioController` / `FGIOSRecorder`,跑在 RemoteIO AU 专用 NSThread + run loop 上,串行化 AU 操作)。Swift 业务层通过 `import Fgvad` 调用 wrapper。

既是对外的使用示例,也是真机端到端验证 fgvad 的工具。

## 构建方式

```bash
cd examples/ios/FgVadDemo
xcodegen generate                                        # 改了 project.yml 后跑

# 命令行 build(给 CI / Simulator 用)
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# 真机:Xcode 打开 ⌘R(首次必须 Xcode UI 触发签名 + iOS platform 安装)
open FgVadDemo.xcodeproj
```

## 真机签名

`project.yml` 默认不指定 `DEVELOPMENT_TEAM` —— 第一次 ⌘R 时 Xcode 会自动加你的 personal team ID 到 `.pbxproj`(本地变更,不入库)。Demo 不依赖任何付费 Apple Developer 账号。

如果本机没装当前 Xcode SDK 对应的 iOS platform package,Xcode UI 会弹下载提示(8GB+,一次性)。装完真机 ⌘R 即可。

## Demo 接入 fgvad 的方式(dev 工作流)

Demo 通过 **Swift Package Manager `path:` 模式**消费 fgvad,**不走公开 GitHub Release URL**:

```yaml
# project.yml
packages:
  Fgvad:
    path: ../../..   # 仓库根,Package.swift 在那里

targets:
  FgVadDemo:
    dependencies:
      - package: Fgvad
        product: Fgvad
```

dev 期改 Swift wrapper(`Sources/Fgvad/FgVadAnalyzer.swift`)立即在 demo build 看到。改 Rust 代码(`src/`)需要重跑 `./scripts/build-xcframework.sh` 重生成 `dist/*.xcframework`,demo 才能看到。

`Package.swift` 用 `FGVAD_LOCAL_BINARIES` 环境变量切换 path / url 模式。dev 默认 url 模式从 GitHub Release 下载 zip(首次 build 慢,会 cache)。如果需要走本地 dist/ 加速调试:

```bash
export FGVAD_LOCAL_BINARIES=1
./scripts/build-xcframework.sh    # 先打 dist/ XCFramework
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo build
```

## 当前功能

- **短/长时模式切换** + 参数面板
- **流式录音** + 实时事件流
- **加载测试 WAV 重跑**(test-data/short 6 个 case + test-data/long yixi 单击进 app bundle)
- **句子列表 + 按句试听**(AVAudioPlayer 切片临时 WAV)
- **导出日志按钮**(Documents/run.log,通过 UIFileSharingEnabled 暴露给 Files app)
- 已知小瑕疵:OC 录音器 `FGAudioController` 的 4 个 `atomic` 属性 .h/.m 不一致警告(老代码,不影响功能)

## 依赖

- Xcode 16+ / iOS 16+
- Rust toolchain(`rustup`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen):`brew install xcodegen`

## 已验证

- iPhone 17 Pro Simulator BUILD SUCCEEDED + 进程稳定存活
- iPhone XS Max(iOS 26.5)真机 24 分钟连续长时模式录音 + VAD 稳定切句 + `import Fgvad` 全栈链路工作
