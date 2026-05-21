package io.fengur.fgvaddemo

import io.fengur.fgvad.Event

data class Sentence(
    val index: Int,
    val startMs: Double,
    val endMs: Double,
    val endEvent: Event,
    val audio: ShortArray?,
)
