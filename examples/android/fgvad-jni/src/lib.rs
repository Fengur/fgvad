//! fgvad Android JNI bridge.
//!
//! Kotlin 端通过 `System.loadLibrary("fgvad_android")` 加载，所有 JNI
//! 函数符号形如 `Java_io_fengur_fgvad_FgVad_*`。

#![cfg(target_os = "android")]

use jni::JNIEnv;
use jni::objects::JClass;
use jni::sys::jstring;

/// 烟测函数：返回 fgvad 库版本字符串。Kotlin 测试用。
#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeVersion<'local>(
    env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jstring {
    let v = fgvad::version();
    env.new_string(v).expect("new_string").into_raw()
}
