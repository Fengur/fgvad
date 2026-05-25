Pod::Spec.new do |s|
  s.name             = 'Fgvad'
  s.version          = '0.1.0'
  s.summary          = '智能 VAD 库 —— Rust 封装 ten-vad,带状态机和动态端点策略。'
  s.description      = <<-DESC
    fgvad 是一个 Rust 写的智能语音活动检测(VAD)库,基于 ten-vad 神经网络模型,
    提供状态机封装和动态尾端点曲线策略。本 podspec 提供 iOS 16+ 的 Swift wrapper 接入。
    macOS 接入请使用 Swift Package Manager。
  DESC

  s.homepage         = 'https://github.com/Fengur/fgvad'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Fengur' => 'noreply@fengur.cn' }

  s.source           = {
    :git => 'https://github.com/Fengur/fgvad.git',
    :tag => "v#{s.version}"
  }

  s.ios.deployment_target = '16.0'
  s.swift_versions = ['5.9']

  # Swift wrapper 源码
  s.source_files = 'Sources/Fgvad/**/*.swift'

  # 远程 XCFramework(从 GitHub Release 下载)
  # 注意:xcframework 的 iOS Simulator 切片仅包含 arm64(vendor ten-vad 库同限制)。
  # x86_64 Simulator 不支持,通过 EXCLUDED_ARCHS 排除。
  s.vendored_frameworks = 'dist/FgvadCore.xcframework', 'dist/TenVad.xcframework'

  # 排除 x86_64 simulator — ten-vad vendor 库不提供该架构
  # Xcode 26 beta simulator SDK 中:
  # - UIUtilities 位于 SubFrameworks/ 而非 Frameworks/,需要额外搜索路径
  # - SwiftUICore 在 Simulator target 下有 allowable_clients 限制,弱链接让 ld 不报 error
  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]' => '$(inherited) $(SDKROOT)/System/Library/SubFrameworks',
    'OTHER_LDFLAGS' => '$(inherited) -weak_framework SwiftUICore'
  }

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
