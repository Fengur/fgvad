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
 * 把采样数(16kHz)格式化成 mm:ss.mmm 写入 buf(>=12 字节)。
 */
void fgvad_format_timestamp(uint64_t sample_offset, char *buf, size_t buf_size);

#endif
