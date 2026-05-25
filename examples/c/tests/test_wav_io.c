#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "wav_io.h"

static const char *FGVAD_ROOT_REL = "../../..";

static char *join_path(const char *suffix) {
    static char buf[1024];
    snprintf(buf, sizeof(buf), "%s/%s", FGVAD_ROOT_REL, suffix);
    return buf;
}

static void test_read_pure_silence_5s(void) {
    int16_t *samples = NULL;
    size_t count = 0;
    int rc = wav_read_mono16k(
        join_path("test-data/short/01-pure-silence-5s.wav"),
        &samples, &count);
    assert(rc == WAV_OK);
    assert(samples != NULL);
    /* 5 秒 16kHz mono，允许 ±1 秒容差 */
    assert(count >= 16000 * 4 && count <= 16000 * 6);
    free(samples);
    printf("OK: 01-pure-silence-5s.wav read %zu samples\n", count);
}

static void test_read_normal_utterance(void) {
    int16_t *samples = NULL;
    size_t count = 0;
    int rc = wav_read_mono16k(
        join_path("test-data/short/02-normal-utterance.wav"),
        &samples, &count);
    assert(rc == WAV_OK);
    assert(count > 0);
    free(samples);
    printf("OK: 02-normal-utterance.wav read %zu samples\n", count);
}

static void test_read_nonexistent_returns_error(void) {
    int16_t *samples = NULL;
    size_t count = 0;
    int rc = wav_read_mono16k("/tmp/nonexistent.wav", &samples, &count);
    assert(rc != WAV_OK);
    assert(samples == NULL);
    printf("OK: missing file returns error\n");
}

int main(void) {
    test_read_pure_silence_5s();
    test_read_normal_utterance();
    test_read_nonexistent_returns_error();
    printf("All wav_io tests passed.\n");
    return 0;
}
