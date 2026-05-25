Pod::Spec.new do |s|
  s.name             = 'Fgvad'
  s.version          = '0.1.0'
  s.summary          = '智能 VAD 库 —— Rust 封装 ten-vad,带状态机和动态端点策略。'
  s.description      = <<-DESC
    fgvad 是一个 Rust 写的智能语音活动检测(VAD)库,基于 ten-vad 神经网络模型,
    提供状态机封装和动态尾端点曲线策略。本 podspec 提供 iOS 16+ / macOS 13+ 的
    Swift wrapper 接入。
  DESC

  s.homepage         = 'https://github.com/Fengur/fgvad'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Fengur' => 'noreply@fengur.cn' }

  s.source           = {
    :git => 'https://github.com/Fengur/fgvad.git',
    :tag => "v#{s.version}"
  }

  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '13.0'
  s.swift_versions = ['5.9']

  # Swift wrapper 源码
  s.source_files = 'Sources/Fgvad/**/*.swift'

  # 远程 XCFramework(从 GitHub Release 下载)
  s.ios.vendored_frameworks = 'dist/FgvadCore.xcframework', 'dist/TenVad.xcframework'
  s.osx.vendored_frameworks = 'dist/FgvadCore.xcframework', 'dist/TenVad.xcframework'

  # CocoaPods 不直接支持远程 XCFramework URL,用 prepare_command 在 pod install
  # 时下载 + 解压两个 xcframework 到 dist/。
  s.prepare_command = <<-CMD
    set -euo pipefail
    RELEASE_BASE="https://github.com/Fengur/fgvad/releases/download/v#{s.version}"
    mkdir -p dist

    if [ ! -d dist/FgvadCore.xcframework ]; then
      echo "==> 下载 FgvadCore.xcframework.zip"
      curl -L -o /tmp/FgvadCore.xcframework.zip \
        "$RELEASE_BASE/FgvadCore.xcframework.zip"
      unzip -q -o /tmp/FgvadCore.xcframework.zip -d dist
      rm /tmp/FgvadCore.xcframework.zip
    fi

    if [ ! -d dist/TenVad.xcframework ]; then
      echo "==> 下载 TenVad.xcframework.zip"
      curl -L -o /tmp/TenVad.xcframework.zip \
        "$RELEASE_BASE/TenVad.xcframework.zip"
      unzip -q -o /tmp/TenVad.xcframework.zip -d dist
      rm /tmp/TenVad.xcframework.zip
    fi
  CMD
end
