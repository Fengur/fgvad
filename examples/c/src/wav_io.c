#include "wav_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#pragma pack(push, 1)
typedef struct {
    char     riff_id[4];   /* "RIFF" */
    uint32_t riff_size;
    char     wave_id[4];   /* "WAVE" */
} RiffHeader;

typedef struct {
    char     id[4];
    uint32_t size;
} ChunkHeader;

typedef struct {
    uint16_t audio_format;    /* 1 = PCM */
    uint16_t num_channels;
    uint32_t sample_rate;
    uint32_t byte_rate;
    uint16_t block_align;
    uint16_t bits_per_sample;
} FmtChunk;
#pragma pack(pop)

int wav_read_mono16k(const char *path, int16_t **out_samples, size_t *out_count) {
    *out_samples = NULL;
    *out_count = 0;

    FILE *fp = fopen(path, "rb");
    if (!fp) return WAV_ERR_OPEN;

    RiffHeader rh;
    if (fread(&rh, sizeof(rh), 1, fp) != 1) { fclose(fp); return WAV_ERR_IO; }
    if (memcmp(rh.riff_id, "RIFF", 4) != 0 ||
        memcmp(rh.wave_id, "WAVE", 4) != 0) {
        fclose(fp); return WAV_ERR_FORMAT;
    }

    int got_fmt = 0;
    FmtChunk fmt;
    memset(&fmt, 0, sizeof(fmt));

    while (1) {
        ChunkHeader ch;
        if (fread(&ch, sizeof(ch), 1, fp) != 1) {
            fclose(fp);
            return got_fmt ? WAV_ERR_IO : WAV_ERR_FORMAT;
        }

        if (memcmp(ch.id, "fmt ", 4) == 0) {
            if (ch.size < sizeof(FmtChunk)) { fclose(fp); return WAV_ERR_FORMAT; }
            if (fread(&fmt, sizeof(FmtChunk), 1, fp) != 1) {
                fclose(fp); return WAV_ERR_IO;
            }
            /* 跳过 fmt 扩展字段 */
            if (ch.size > (uint32_t)sizeof(FmtChunk)) {
                fseek(fp, (long)(ch.size - sizeof(FmtChunk)), SEEK_CUR);
            }
            got_fmt = 1;
            if (fmt.audio_format   != 1     ||
                fmt.num_channels   != 1     ||
                fmt.sample_rate    != 16000 ||
                fmt.bits_per_sample != 16) {
                fclose(fp); return WAV_ERR_UNSUPPORTED;
            }
        } else if (memcmp(ch.id, "data", 4) == 0) {
            if (!got_fmt) { fclose(fp); return WAV_ERR_FORMAT; }
            size_t n = ch.size / 2;
            int16_t *buf = (int16_t *)malloc(n * sizeof(int16_t));
            if (!buf) { fclose(fp); return WAV_ERR_IO; }
            if (fread(buf, sizeof(int16_t), n, fp) != n) {
                free(buf); fclose(fp); return WAV_ERR_IO;
            }
            *out_samples = buf;
            *out_count = n;
            fclose(fp);
            return WAV_OK;
        } else {
            /* 跳过未知 chunk（LIST/INFO 等） */
            fseek(fp, (long)ch.size, SEEK_CUR);
        }
    }
}

int wav_write_mono16k(const char *path, const int16_t *samples, size_t count) {
    FILE *fp = fopen(path, "wb");
    if (!fp) return WAV_ERR_OPEN;

    uint32_t data_size = (uint32_t)(count * sizeof(int16_t));

    RiffHeader rh;
    memcpy(rh.riff_id, "RIFF", 4);
    rh.riff_size = 36 + data_size;
    memcpy(rh.wave_id, "WAVE", 4);
    if (fwrite(&rh, sizeof(rh), 1, fp) != 1) { fclose(fp); return WAV_ERR_IO; }

    ChunkHeader fmt_h;
    memcpy(fmt_h.id, "fmt ", 4);
    fmt_h.size = (uint32_t)sizeof(FmtChunk);
    if (fwrite(&fmt_h, sizeof(fmt_h), 1, fp) != 1) { fclose(fp); return WAV_ERR_IO; }

    FmtChunk fmt;
    fmt.audio_format    = 1;
    fmt.num_channels    = 1;
    fmt.sample_rate     = 16000;
    fmt.byte_rate       = 16000 * 2;
    fmt.block_align     = 2;
    fmt.bits_per_sample = 16;
    if (fwrite(&fmt, sizeof(fmt), 1, fp) != 1) { fclose(fp); return WAV_ERR_IO; }

    ChunkHeader data_h;
    memcpy(data_h.id, "data", 4);
    data_h.size = data_size;
    if (fwrite(&data_h, sizeof(data_h), 1, fp) != 1) { fclose(fp); return WAV_ERR_IO; }

    if (count > 0 && fwrite(samples, sizeof(int16_t), count, fp) != count) {
        fclose(fp); return WAV_ERR_IO;
    }
    fclose(fp);
    return WAV_OK;
}
