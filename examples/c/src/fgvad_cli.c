#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <getopt.h>
#include "fgvad.h"
#include "wav_io.h"
#include "event_fmt.h"

typedef enum { MODE_SHORT, MODE_LONG } Mode;

static void usage(const char *prog) {
    fprintf(stderr,
        "用法: %s <short|long> <input.wav> [-o <dump_dir>]\n"
        "  short      短时模式(命令/查询语义,尾静音到点结束)\n"
        "  long       长时模式(连续多句,动态尾端点)\n"
        "  -o DIR     可选,把每句切成独立 sentence_NNN.wav 写入 DIR\n",
        prog);
}

int main(int argc, char **argv) {
    if (argc < 3) { usage(argv[0]); return 2; }

    Mode mode;
    if (strcmp(argv[1], "short") == 0) mode = MODE_SHORT;
    else if (strcmp(argv[1], "long") == 0) mode = MODE_LONG;
    else { usage(argv[0]); return 2; }

    const char *input_path = argv[2];
    const char *dump_dir = NULL;

    /* 从 argv[3] 起解析 -o */
    int opt;
    optind = 3;
    while ((opt = getopt(argc, argv, "o:")) != -1) {
        if (opt == 'o') dump_dir = optarg;
        else { usage(argv[0]); return 2; }
    }

    /* 读 WAV */
    int16_t *samples = NULL;
    size_t sample_count = 0;
    int rc = wav_read_mono16k(input_path, &samples, &sample_count);
    if (rc != WAV_OK) {
        fprintf(stderr, "读取 WAV 失败: %s (rc=%d, 需要 mono/16kHz/i16)\n",
                input_path, rc);
        return 1;
    }
    fprintf(stderr, "已读入 %zu 个采样点 (~%.2f 秒)\n",
            sample_count, (double)sample_count / 16000.0);

    /* 创建 VAD 实例 */
    struct FgVad *vad;
    if (mode == MODE_SHORT) {
        vad = fgvad_new_short(3000, 2000, 30000);
    } else {
        vad = fgvad_new_long(3000, 30000, 0, 2000, 600, true);
    }
    if (!vad) {
        fprintf(stderr, "fgvad 实例创建失败\n");
        free(samples);
        return 1;
    }

    fgvad_start(vad);

    /* 一次性喂全 PCM(demo 简化;真实流式见 README) */
    struct FgVadResults *results = fgvad_process(vad, samples, sample_count);
    if (!results) {
        fprintf(stderr, "fgvad_process 失败\n");
        fgvad_free(vad); free(samples);
        return 1;
    }

    size_t n = fgvad_results_count(results);
    size_t sent_idx = 0, force_cut = 0;
    char ts[FGVAD_TIMESTAMP_BUF_SIZE];

    for (size_t i = 0; i < n; i++) {
        struct FgVadResultView v = fgvad_result_view(results, i);
        if (v.event == FgVadEvent_None_) continue;

        fgvad_format_timestamp(v.stream_offset_sample, ts, sizeof(ts));

        if (v.event == FgVadEvent_SentenceEnded ||
            v.event == FgVadEvent_SentenceForceCut) {
            sent_idx++;
            double dur_ms = (double)v.audio_len / 16.0;
            printf("[%s] %-22s duration=%7.0fms  end_reason=%s\n",
                   ts, fgvad_event_label(v.event), dur_ms,
                   fgvad_end_reason_label(v.end_reason));
            if (v.event == FgVadEvent_SentenceForceCut) force_cut++;

            /* dump 句子(Task 5 实现) */
            if (dump_dir) {
                /* TODO Task 5: 写 sentence_NNN.wav 到 dump_dir */
                (void)sent_idx;
            }
        } else {
            printf("[%s] %-22s state=%s\n",
                   ts, fgvad_event_label(v.event), fgvad_state_label(v.state));
        }
    }

    enum FgVadState final_state = fgvad_state(vad);
    enum FgVadEndReason final_reason = fgvad_end_reason(vad);
    fgvad_results_free(results);
    fgvad_stop(vad);
    fgvad_free(vad);
    free(samples);

    printf("---\n");
    printf("Summary: %zu 句 (ForceCut %zu), 终态=%s, end_reason=%s\n",
           sent_idx, force_cut,
           fgvad_state_label(final_state),
           fgvad_end_reason_label(final_reason));
    return 0;
}
