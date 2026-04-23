/*
 * fgvad C API
 * 自动生成 by cbindgen —— 请勿手工修改。
 */

#ifndef FGVAD_H
#define FGVAD_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/**
 * 仅当 `state == FgVadState::End` 时有意义；否则为 `None_`。
 */
enum FgVadEndReason
#ifdef __cplusplus
  : uint32_t
#endif // __cplusplus
 {
  FgVadEndReason_None_ = 0,
  FgVadEndReason_SpeechCompleted = 1,
  FgVadEndReason_HeadSilenceTimeout = 2,
  FgVadEndReason_MaxDurationReached = 3,
  FgVadEndReason_ExternalStop = 4,
};
#ifndef __cplusplus
typedef uint32_t FgVadEndReason;
#endif // __cplusplus

enum FgVadEvent
#ifdef __cplusplus
  : uint32_t
#endif // __cplusplus
 {
  FgVadEvent_None_ = 0,
  FgVadEvent_SentenceStarted = 1,
  FgVadEvent_SentenceEnded = 2,
  FgVadEvent_SentenceForceCut = 3,
  FgVadEvent_HeadSilenceTimeout = 4,
  FgVadEvent_MaxDurationReached = 5,
};
#ifndef __cplusplus
typedef uint32_t FgVadEvent;
#endif // __cplusplus

enum FgVadResultType
#ifdef __cplusplus
  : uint32_t
#endif // __cplusplus
 {
  FgVadResultType_Silence = 0,
  FgVadResultType_SentenceStart = 1,
  FgVadResultType_Active = 2,
  FgVadResultType_SentenceEnd = 3,
};
#ifndef __cplusplus
typedef uint32_t FgVadResultType;
#endif // __cplusplus

enum FgVadState
#ifdef __cplusplus
  : uint32_t
#endif // __cplusplus
 {
  FgVadState_Idle = 0,
  FgVadState_Detecting = 1,
  FgVadState_Started = 2,
  FgVadState_Voiced = 3,
  FgVadState_Trailing = 4,
  FgVadState_End = 5,
};
#ifndef __cplusplus
typedef uint32_t FgVadState;
#endif // __cplusplus

typedef struct FgVad FgVad;

/**
 * opaque 句柄（C 里只以 `struct FgVad *` 形式出现）。
 */
typedef struct FgVad FgVad;

/**
 * opaque 结果集，内部持有 `Vec<VadResult>` 与逐帧概率 / is_voice 的 SoA 缓存
 * （方便 C 侧直接拿连续指针画波形）。
 */
typedef struct FgVadResults FgVadResults;

/**
 * 一条结果的只读视图。指针生命周期绑定 `FgVadResults`。
 */
typedef struct FgVadResultView {
  FgVadResultType result_type;
  /**
   * 本段音频起始指针（Silence 段可能为空——此时 ptr 为空、len=0）。
   */
  const int16_t *audio_ptr;
  uintptr_t audio_len;
  /**
   * 本段覆盖的每 16ms 帧的 probability（连续数组）。
   */
  const float *probabilities_ptr;
  /**
   * 本段覆盖的每 16ms 帧的 is_voice（0 或 1）。
   */
  const uint8_t *is_voice_ptr;
  uintptr_t frames_count;
  FgVadEvent event;
  FgVadState state;
  FgVadEndReason end_reason;
  bool is_sentence_begin;
  bool is_sentence_end;
  uint64_t stream_offset_sample;
} FgVadResultView;

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * 创建短时模式实例。失败返回 NULL。
 * 参数单位：毫秒。
 */
struct FgVad *fgvad_new_short(uint32_t head_silence_timeout_ms,
                              uint32_t tail_silence_ms,
                              uint32_t max_duration_ms);

/**
 * 创建长时模式实例。失败返回 NULL。
 * `max_session_duration_ms = 0` 表示会话时长不限。
 */
struct FgVad *fgvad_new_long(uint32_t head_silence_timeout_ms,
                             uint32_t max_sentence_duration_ms,
                             uint32_t max_session_duration_ms,
                             uint32_t tail_silence_ms_initial,
                             uint32_t tail_silence_ms_min,
                             bool enable_dynamic_tail);

/**
 * 释放 VAD 实例。接收 NULL 为 no-op。
 */
void fgvad_free(struct FgVad *vad);

void fgvad_start(struct FgVad *vad);

void fgvad_stop(struct FgVad *vad);

void fgvad_reset(struct FgVad *vad);

/**
 * 查询当前状态机状态。NULL 返回 `Idle`。
 */
FgVadState fgvad_state(const struct FgVad *vad);

/**
 * 查询终态原因（仅 `state == End` 时有意义）。
 */
FgVadEndReason fgvad_end_reason(const struct FgVad *vad);

/**
 * 喂入 16 kHz mono i16 PCM。返回一个 opaque 结果集；
 * 失败（传 NULL、ten-vad 处理失败等）返回 NULL。
 *
 * `sample_count` 为 0 时依然返回有效（空）结果集。
 */
struct FgVadResults *fgvad_process(struct FgVad *vad,
                                   const int16_t *samples,
                                   uintptr_t sample_count);

void fgvad_results_free(struct FgVadResults *results);

uintptr_t fgvad_results_count(const struct FgVadResults *results);

/**
 * 按索引取一条结果的只读视图。越界或 NULL 返回全零视图。
 * 视图内所有指针的生命周期绑定到 `FgVadResults`；调用 `fgvad_results_free` 之后失效。
 */
struct FgVadResultView fgvad_result_view(const struct FgVadResults *results,
                                         uintptr_t index);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* FGVAD_H */
