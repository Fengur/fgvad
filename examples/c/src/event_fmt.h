#ifndef FGVAD_DEMO_EVENT_FMT_H
#define FGVAD_DEMO_EVENT_FMT_H

#include <stddef.h>
#include <stdint.h>
#include "fgvad.h"

const char *fgvad_event_label(enum FgVadEvent e);
const char *fgvad_state_label(enum FgVadState s);
const char *fgvad_end_reason_label(enum FgVadEndReason r);
const char *fgvad_result_type_label(enum FgVadResultType t);

/**
 * 推荐的 buf 大小:`mm:ss.mmm` 最长 11 字节(含 NUL)。
 * 留 16 字节余量足够任何边界情况。
 */
#define FGVAD_TIMESTAMP_BUF_SIZE 16

/**
 * 把采样数(16kHz)格式化成 mm:ss.mmm 写入 buf。
 * 调用方建议传 `FGVAD_TIMESTAMP_BUF_SIZE` 大小的 buf。
 */
void fgvad_format_timestamp(uint64_t sample_offset, char *buf, size_t buf_size);

#endif /* FGVAD_DEMO_EVENT_FMT_H */
