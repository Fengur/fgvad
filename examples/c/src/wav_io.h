#ifndef FGVAD_DEMO_WAV_IO_H
#define FGVAD_DEMO_WAV_IO_H

#include <stddef.h>
#include <stdint.h>

#define WAV_OK              0
#define WAV_ERR_OPEN       -1
#define WAV_ERR_FORMAT     -2
#define WAV_ERR_UNSUPPORTED -3
#define WAV_ERR_IO         -4

/**
 * 读取一个 mono/16kHz/i16 PCM WAV。成功返回 WAV_OK，
 * `*out_samples` 指向 malloc 出来的 i16 数组（由调用者 free），
 * `*out_count` 为采样点数。失败返回错误码，*out_samples 置空。
 */
int wav_read_mono16k(const char *path, int16_t **out_samples, size_t *out_count);

/**
 * 写一个 mono/16kHz/i16 PCM WAV。成功返回 WAV_OK。
 */
int wav_write_mono16k(const char *path, const int16_t *samples, size_t count);

#endif /* FGVAD_DEMO_WAV_IO_H */
