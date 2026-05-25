// swift-tools-version: 5.9
import PackageDescription
import Foundation

// 开发期 export FGVAD_LOCAL_BINARIES=1 让 Package.swift 用 dist/ 本地 xcframework,
// 改 wrapper 后无需重新打 release zip;
// 集成方默认走 GitHub Release URL + checksum,不需要本地构建。
let useLocalBinaries = ProcessInfo.processInfo.environment["FGVAD_LOCAL_BINARIES"] != nil

let releaseTag = "v0.1.0"
let releaseBase = "https://github.com/Fengur/fgvad/releases/download/\(releaseTag)"

let fgvadCoreTarget: Target = useLocalBinaries
    ? .binaryTarget(name: "FgvadCore", path: "dist/FgvadCore.xcframework")
    : .binaryTarget(
        name: "FgvadCore",
        url: "\(releaseBase)/FgvadCore.xcframework.zip",
        checksum: "66cc3faa07ec6a66f8e24178c709566b4e8dedccf9263959b5e3f3d20f1b35c5"
      )

let tenVadTarget: Target = useLocalBinaries
    ? .binaryTarget(name: "TenVad", path: "dist/ten_vad.xcframework")
    : .binaryTarget(
        name: "TenVad",
        url: "\(releaseBase)/ten_vad.xcframework.zip",
        checksum: "d928971e9e361d2da4f5b6e24e5cc95d00696906ea616158406eb9e5330f1c04"
      )

let package = Package(
    name: "Fgvad",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "Fgvad", targets: ["Fgvad"]),
    ],
    targets: [
        fgvadCoreTarget,
        tenVadTarget,
        .target(
            name: "Fgvad",
            dependencies: ["FgvadCore", "TenVad"],
            path: "Sources/Fgvad"
        ),
    ]
)
