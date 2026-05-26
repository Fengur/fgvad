package io.fengur.fgvad

/** 与 fgvad-jni 的 nativeState 返回 ordinal 严格对齐。 */
enum class State { Idle, Detecting, Started, Voiced, Trailing, End }
