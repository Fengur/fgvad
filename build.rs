fn main() {
    #[cfg(target_os = "macos")]
    link_macos();

    #[cfg(not(target_os = "macos"))]
    {
        println!(
            "cargo:warning=fgvad 目前仅支持 macOS；其他平台构建会成功但无法使用 ten-vad。"
        );
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

#[cfg(target_os = "macos")]
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
