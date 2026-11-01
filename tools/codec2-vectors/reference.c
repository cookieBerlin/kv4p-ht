/*
 * Golden test vectors for Codec2 1300 (ADR-0005, ADR-0027).
 *
 * Built by generate.sh against the pristine upstream Codec2 checkout that
 * codec2-android (the Android app's FreeDV codec) pins. Encodes deterministic
 * 8 kHz test signals with one codec instance and decodes the frames with
 * another, then prints the input, the frames and the RMS of each decoded frame
 * as JSON on stdout. The decoder draws random phases for unvoiced sounds from a
 * process-wide generator (codec2_rand), so its samples are only reproducible
 * in level, not exactly.
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "codec2.h"

#define FRAMES_MAX 16

enum { PCM_SAMPLES = 320, FRAME_BYTES = 7, SAMPLE_RATE = 8000 };

typedef void (*signal_fn)(short *pcm, int samples);

static void silence(short *pcm, int samples) { memset(pcm, 0, sizeof(short) * (size_t)samples); }

/* A voiced, speech-like sound: harmonics with 1/k amplitude, the pitch rising from 110 to 220 Hz. */
static void voiced(short *pcm, int samples) {
    double phase = 0;
    for (int n = 0; n < samples; n++) {
        double f0 = 110.0 + 110.0 * n / samples;
        phase += 2 * M_PI * f0 / SAMPLE_RATE;
        double value = 0;
        for (int k = 1; k * f0 < 3800; k++) value += sin(k * phase) / k;
        double envelope = sin(M_PI * n / samples);
        pcm[n] = (short)lround(6000 * envelope * value);
    }
}

/* White noise from a 32-bit linear congruential generator. */
static void noise(short *pcm, int samples) {
    uint32_t state = 1;
    for (int n = 0; n < samples; n++) {
        state = state * 1664525u + 1013904223u;
        pcm[n] = (short)((int32_t)(state >> 16) - 32768) / 4;
    }
}

static void print_samples(const char *name, const short *pcm, int samples) {
    printf("        \"%s\": [", name);
    for (int n = 0; n < samples; n++) printf(n ? ", %d" : "%d", pcm[n]);
    printf("]");
}

static void vector(const char *name, signal_fn signal, int frames, int last) {
    static short input[FRAMES_MAX * PCM_SAMPLES];
    static short decoded[FRAMES_MAX * PCM_SAMPLES];
    static unsigned char bits[FRAMES_MAX][FRAME_BYTES];
    int samples = frames * PCM_SAMPLES;
    signal(input, samples);
    struct CODEC2 *encoder = codec2_create(CODEC2_MODE_1300);
    struct CODEC2 *decoder = codec2_create(CODEC2_MODE_1300);
    for (int f = 0; f < frames; f++) {
        codec2_encode(encoder, bits[f], input + f * PCM_SAMPLES);
        codec2_decode(decoder, decoded + f * PCM_SAMPLES, bits[f]);
    }
    codec2_destroy(encoder);
    codec2_destroy(decoder);

    printf("    {\n      \"name\": \"%s\",\n      \"input\": {\n", name);
    print_samples("pcm", input, samples);
    printf("\n      },\n      \"expected\": {\n        \"frames\": [");
    for (int f = 0; f < frames; f++) {
        printf(f ? ", \"" : "\"");
        for (int b = 0; b < FRAME_BYTES; b++) printf("%02x", bits[f][b]);
        printf("\"");
    }
    printf("],\n        \"rms\": [");
    for (int f = 0; f < frames; f++) {
        double energy = 0;
        for (int n = 0; n < PCM_SAMPLES; n++) energy += (double)decoded[f * PCM_SAMPLES + n] * decoded[f * PCM_SAMPLES + n];
        printf(f ? ", %.1f" : "%.1f", sqrt(energy / PCM_SAMPLES));
    }
    printf("]\n      }\n    }%s\n", last ? "" : ",");
}

int main(void) {
    struct CODEC2 *codec = codec2_create(CODEC2_MODE_1300);
    if (codec2_samples_per_frame(codec) != PCM_SAMPLES || codec2_bytes_per_frame(codec) != FRAME_BYTES) return 1;
    codec2_destroy(codec);

    printf("{\n  \"generator\": \"tools/codec2-vectors\",\n  \"source\": \"Codec2 %s\",\n  \"vectors\": [\n",
           CODEC2_VERSION);
    vector("silence", silence, 4, 0);
    vector("voiced", voiced, FRAMES_MAX, 0);
    vector("noise", noise, 6, 1);
    printf("  ]\n}\n");
    return 0;
}
