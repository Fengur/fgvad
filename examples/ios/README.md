# FgVadDemo — iOS Testing / Integration Sample for fgvad
> English | [中文](README_CN.md)

UIKit + pure frame layout, **reusing an OC RemoteIO AudioUnit recorder** (`FGAudioController` / `FGIOSRecorder`, running on a dedicated NSThread + run loop for the RemoteIO AU, serializing AU operations). The Swift business layer calls the wrapper via `import Fgvad`.

Serves both as an external usage example and as a tool for end-to-end on-device validation of fgvad.

## Build

```bash
cd examples/ios/FgVadDemo
xcodegen generate                                        # re-run after modifying project.yml

# Command-line build (for CI / Simulator)
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# Real device: open in Xcode and press ⌘R (first run must go through Xcode UI to trigger signing + iOS platform install)
open FgVadDemo.xcodeproj
```

## Device Signing

`project.yml` does not specify `DEVELOPMENT_TEAM` by default — the first ⌘R in Xcode will automatically add your personal team ID to `.pbxproj` (local change, not committed). The Demo does not require a paid Apple Developer account.

If the iOS platform package for the current Xcode SDK is not installed, Xcode UI will prompt you to download it (8GB+, one-time). After it installs, ⌘R on a real device works.

## How the Demo Integrates fgvad (Dev Workflow)

The Demo consumes fgvad via **Swift Package Manager `path:` mode** — it does **not** use the public GitHub Release URL:

```yaml
# project.yml
packages:
  Fgvad:
    path: ../../..   # repo root, where Package.swift lives

targets:
  FgVadDemo:
    dependencies:
      - package: Fgvad
        product: Fgvad
```

During development, changes to the Swift wrapper (`Sources/Fgvad/FgVadAnalyzer.swift`) are immediately visible on the next demo build. Changes to Rust code (`src/`) require re-running `./scripts/build-xcframework.sh` to regenerate `dist/*.xcframework` before the demo picks them up.

`Package.swift` uses the `FGVAD_LOCAL_BINARIES` environment variable to switch between path / url modes. By default in dev the url mode downloads the zip from GitHub Release (slow on first build, cached afterwards). To switch to local `dist/` for faster iteration:

```bash
export FGVAD_LOCAL_BINARIES=1
./scripts/build-xcframework.sh    # build dist/ XCFramework first
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo build
```

## Current Features

- **Short / Long Mode toggle** + parameter panel
- **Streaming recording** + real-time event stream
- **Load test WAV for replay** (test-data/short 6 cases + test-data/long yixi, single-tap loads into app bundle)
- **Sentence list + per-sentence playback** (AVAudioPlayer slices a temporary WAV)
- **Export log button** (Documents/run.log, exposed to the Files app via UIFileSharingEnabled)
- Known minor issue: 4 `atomic` properties in the OC recorder `FGAudioController` have mismatched `.h`/`.m` declarations causing warnings (legacy code, does not affect functionality)

## Dependencies

- Xcode 16+ / iOS 16+
- Rust toolchain (`rustup`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Verified

- iPhone 17 Pro Simulator: BUILD SUCCEEDED + process stable
- iPhone XS Max (iOS 26.5), real device: 24-minute continuous Long Mode recording + stable VAD sentence segmentation + full `import Fgvad` stack verified
