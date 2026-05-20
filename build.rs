fn main() {
    let target = std::env::var("TARGET").expect("TARGET 必须由 cargo 设置");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    match target_os.as_str() {
        "macos" => link_macos(),
        "ios" => link_ios(&target),
        _ => {
            println!(
                "cargo:warning=fgvad 当前平台 {target} 未配置 ten-vad 链接\
                ，仅支持 macOS / iOS。"
            );
        }
    }

    generate_c_header();
}

/// 跑 cbindgen 生成 `include/fgvad.h`。
fn generate_c_header() {
    let crate_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR");
    let out_dir = std::path::Path::new(&crate_dir).join("include");
    std::fs::create_dir_all(&out_dir).expect("创建 include 目录");
    let out_file = out_dir.join("fgvad.h");

    match cbindgen::generate(&crate_dir) {
        Ok(bindings) => {
            bindings.write_to_file(&out_file);
        }
        Err(e) => {
            println!("cargo:warning=cbindgen 生成头文件失败: {e}");
        }
    }
    println!("cargo:rerun-if-changed=src/ffi.rs");
    println!("cargo:rerun-if-changed=cbindgen.toml");
}

fn link_macos() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR unset");
    let framework_dir = format!("{manifest_dir}/vendor/ten-vad/macOS");

    println!("cargo:rustc-link-search=framework={framework_dir}");
    println!("cargo:rustc-link-lib=framework=ten_vad");
    println!("cargo:rustc-link-arg=-Wl,-rpath,{framework_dir}");

    // 让 libfgvad.dylib 的 install_name 使用 @rpath，方便分发时重定位。
    println!("cargo:rustc-cdylib-link-arg=-Wl,-install_name,@rpath/libfgvad.dylib");

    println!("cargo:rerun-if-changed=build.rs");
    println!(
        "cargo:rerun-if-changed=vendor/ten-vad/macOS/ten_vad.framework/Versions/A/ten_vad"
    );
}

/// iOS 链接：device（`aarch64-apple-ios`）和 simulator（`aarch64-apple-ios-sim`）
/// 共享同一份头文件，但 framework 二进制不同：
///
/// - `vendor/ten-vad/iOS/device/ten_vad.framework`     —— 上游原版 device 二进制
/// - `vendor/ten-vad/iOS/simulator/ten_vad.framework`  —— 用 `vtool -set-build-version`
///   把 device 二进制重新打 simulator 平台标记得到（上游不提供 simulator slice）
fn link_ios(target: &str) {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR unset");

    // simulator target 的 triple 形如 `aarch64-apple-ios-sim`，device 是 `aarch64-apple-ios`
    let is_simulator = target.ends_with("-sim");
    let subdir = if is_simulator { "simulator" } else { "device" };
    let framework_dir = format!("{manifest_dir}/vendor/ten-vad/iOS/{subdir}");

    println!("cargo:rustc-link-search=framework={framework_dir}");
    println!("cargo:rustc-link-lib=framework=ten_vad");

    // iOS app 内嵌 framework 时通常通过 @executable_path/Frameworks 加载，
    // 这里给一个 rpath 只是开发期方便（最终 app bundle 会把 framework 拷进去）。
    println!("cargo:rustc-link-arg=-Wl,-rpath,@executable_path/Frameworks");

    // libfgvad.dylib 的 install_name（仅当作 cdylib 产出时生效；做 staticlib
    // 集成不影响）。
    println!("cargo:rustc-cdylib-link-arg=-Wl,-install_name,@rpath/libfgvad.dylib");

    println!("cargo:rerun-if-changed=build.rs");
    println!(
        "cargo:rerun-if-changed=vendor/ten-vad/iOS/{subdir}/ten_vad.framework/ten_vad"
    );
}
