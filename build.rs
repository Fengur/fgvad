fn main() {
    #[cfg(target_os = "macos")]
    link_macos();

    #[cfg(not(target_os = "macos"))]
    {
        println!(
            "cargo:warning=fgvad 目前仅支持 macOS；其他平台构建会成功但无法使用 ten-vad。"
        );
    }
}

#[cfg(target_os = "macos")]
fn link_macos() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR unset");
    let framework_dir = format!("{manifest_dir}/vendor/ten-vad/macOS");

    println!("cargo:rustc-link-search=framework={framework_dir}");
    println!("cargo:rustc-link-lib=framework=ten_vad");
    println!("cargo:rustc-link-arg=-Wl,-rpath,{framework_dir}");

    println!("cargo:rerun-if-changed=build.rs");
    println!(
        "cargo:rerun-if-changed=vendor/ten-vad/macOS/ten_vad.framework/Versions/A/ten_vad"
    );
}
