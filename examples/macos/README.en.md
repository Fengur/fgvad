# FgVadDemo — macOS Testing Tool for fgvad
> English | [中文](README.md)

AppKit + SnapKit. Serves both as an external usage example and as the primary tool for debugging and parameter tuning.

## Build

```bash
# Generate the Xcode project (re-run after modifying project.yml)
cd examples/macos
xcodegen generate

# Open in Xcode, or build from the command line
open FgVadDemo.xcodeproj
# or
xcodebuild -project FgVadDemo.xcodeproj -scheme FgVadDemo -configuration Debug build
```

**Building the Demo automatically invokes `scripts/build-macos-universal.sh`** — which runs `cargo build` twice (aarch64-apple-darwin + x86_64-apple-darwin), merges them into a universal `libfgvad.dylib` at `target/universal-apple-darwin/debug/`, and then the post-build script copies it into `.app/Contents/Frameworks`. **The Demo therefore runs on both Apple Silicon and Intel Macs.**

On the first build, if the x86_64 rustup target is missing, the script will automatically run `rustup target add`.

Each run leaves a recording file named `rec-YYYY-MM-DD-HH-MM-SS.wav` under `~/Documents/FgVadDemo/`.

## Toolchain

```
Rust fgvad (target/debug/libfgvad.dylib) ─┐
                                          ├─ link + embed into Frameworks/
ten_vad.framework (vendor/ten-vad/macOS/)─┘
                  ↓
       Xcode compiles FgVadDemo.app

Swift imports fgvad.h (include/) via FgVadDemo-Bridging-Header.h
Loaded at runtime via @rpath/@executable_path/../Frameworks
```

## Dependencies

- Xcode 15+ / macOS 13+
- Rust toolchain (`rustup`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- SnapKit (pulled automatically via SPM)

## Current Features

- **Short / Long Mode toggle** (top segmented control)
- **Parameter panel**: head_silence_timeout / tail_silence / max_duration, plus long-mode-only tail_silence_initial / tail_silence_min / enable dynamic tail endpoint curve toggle
- **Streaming recording**: continuously feeds VAD while recording; auto-stops on SentenceEnd in Short Mode
- **Load WAV for replay**: batch feed an existing WAV using the current mode + parameters (spinner + locked controls during processing)
- **Sentence list**: one row per sentence `Sentence N  mm:ss.mmm – mm:ss.mmm  event label ▶` — ForceCut in orange, SentenceEnded in green; ▶ slices the audio in the background, writes a temporary WAV, and plays it via AVAudioPlayer
- **Live tick during recording**: elapsed time + state + cumulative sentence count
- **End reason display**: "Speech completed (tail silence threshold met)", "No speech detected (head silence timeout)", "Maximum duration reached", "Stopped manually"
- **Debug log**: `~/Library/Logs/FgVadDemo/run.log` (truncated on each launch)

## How the Demo Integrates fgvad (Dev Workflow)

The Demo consumes fgvad via **Swift Package Manager `path:` mode** — it does **not** use the public GitHub Release URL:

```yaml
# project.yml
packages:
  SnapKit: { url: ..., from: "5.7.0" }
  Fgvad:
    path: ../..  # repo root, where Package.swift lives

targets:
  FgVadDemo:
    dependencies:
      - package: SnapKit
      - package: Fgvad
        product: Fgvad
```

During development, changes to the Swift wrapper (`Sources/Fgvad/FgVadAnalyzer.swift`) are immediately visible on the next demo build. Changes to Rust code (`src/`) require re-running `./scripts/build-xcframework.sh` to regenerate `dist/*.xcframework` before the demo picks them up.

`Package.swift` supports two modes: by default it fetches from the GitHub Release URL (with SHA256 checksum); for faster local iteration, `export FGVAD_LOCAL_BINARIES=1` switches to the local `dist/`.

## Todo

- Visualization of probability curve + dynamic tail curve + role color bands (roadmap, optional polish)
