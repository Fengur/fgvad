// swift-tools-version: 5.9
import PackageDescription

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
        // C ABI(staticlib)+ headers + module.modulemap，从 dist/ 引用本地 XCFramework。
        // Plan 2 切到 GitHub Release URL + checksum。
        .binaryTarget(
            name: "FgvadCore",
            path: "dist/FgvadCore.xcframework"
        ),
        .binaryTarget(
            name: "TenVad",
            path: "dist/TenVad.xcframework"
        ),
        // Swift wrapper，依赖 FgvadCore(C)+ TenVad(链接需要)。
        .target(
            name: "Fgvad",
            dependencies: ["FgvadCore", "TenVad"],
            path: "Sources/Fgvad"
        ),
    ]
)
