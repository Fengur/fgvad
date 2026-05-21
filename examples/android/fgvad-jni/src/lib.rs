//! fgvad Android JNI bridge.
//!
//! Kotlin 端通过 `System.loadLibrary("fgvad_android")` 加载，所有 JNI
//! 函数符号形如 `Java_io_fengur_fgvad_FgVad_*`。

#![cfg(target_os = "android")]

use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::JNIEnv;
use jni::objects::JClass;
use jni::sys::{jboolean, jint, jlong, jstring};

use fgvad::{FgVad, LongModeConfig, ShortModeConfig};

/// 把 Rust panic 转成 Java IllegalStateException。所有 native 函数包一层。
fn catch_panic<F: FnOnce() -> R, R: Default>(env: &mut JNIEnv, body: F) -> R {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(r) => r,
        Err(_) => {
            let _ = env.throw_new("java/lang/IllegalStateException", "fgvad-jni panicked");
            R::default()
        }
    }
}

/// 烟测函数：返回 fgvad 库版本字符串。Kotlin 测试用。
#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeVersion<'local>(
    env: JNIEnv<'local>,
    _class: JClass<'local>,
) -> jstring {
    let v = fgvad::version();
    env.new_string(v).expect("new_string").into_raw()
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeNewShort<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    head_silence_ms: jint,
    tail_silence_ms: jint,
    max_duration_ms: jint,
) -> jlong {
    catch_panic(&mut env, || {
        let cfg = ShortModeConfig {
            head_silence_timeout_ms: head_silence_ms.max(0) as u32,
            tail_silence_ms: tail_silence_ms.max(0) as u32,
            max_duration_ms: max_duration_ms.max(0) as u32,
        };
        match FgVad::short(cfg) {
            Ok(vad) => Box::into_raw(Box::new(vad)) as jlong,
            Err(_) => 0,
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeNewLong<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    head_silence_ms: jint,
    max_sentence_ms: jint,
    max_session_ms: jint,
    tail_init_ms: jint,
    tail_min_ms: jint,
    enable_dynamic: jboolean,
) -> jlong {
    catch_panic(&mut env, || {
        let cfg = LongModeConfig {
            head_silence_timeout_ms: head_silence_ms.max(0) as u32,
            max_sentence_duration_ms: max_sentence_ms.max(0) as u32,
            max_session_duration_ms: max_session_ms.max(0) as u32,
            tail_silence_ms_initial: tail_init_ms.max(0) as u32,
            tail_silence_ms_min: tail_min_ms.max(0) as u32,
            enable_dynamic_tail: enable_dynamic != 0,
        };
        match FgVad::long(cfg) {
            Ok(vad) => Box::into_raw(Box::new(vad)) as jlong,
            Err(_) => 0,
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_io_fengur_fgvad_FgVad_nativeFree<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    handle: jlong,
) {
    catch_panic(&mut env, || {
        if handle != 0 {
            unsafe { drop(Box::from_raw(handle as *mut FgVad)); }
        }
    });
}

/// 拿 handle 解引用为 &mut FgVad。NULL handle 返回 None。
#[allow(dead_code)]
unsafe fn handle_mut<'a>(handle: jlong) -> Option<&'a mut FgVad> {
    if handle == 0 {
        None
    } else {
        Some(&mut *(handle as *mut FgVad))
    }
}

#[allow(dead_code)]
unsafe fn handle_ref<'a>(handle: jlong) -> Option<&'a FgVad> {
    if handle == 0 {
        None
    } else {
        Some(&*(handle as *const FgVad))
    }
}
