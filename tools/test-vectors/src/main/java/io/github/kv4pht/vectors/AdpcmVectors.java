package io.github.kv4pht.vectors;

import com.vagell.kv4pht.radio.ImaAdpcm;
import java.util.ArrayList;
import java.util.List;

/** Vectors for {@link ImaAdpcm}: block encode/decode and the stateful encoder. */
final class AdpcmVectors {
    /** Samples per 128-byte block on the wire (4-byte header + 124 bytes of nibbles). */
    private static final int BLOCK_SAMPLES = 249;
    private static final int SAMPLE_RATE = 16000;

    private AdpcmVectors() {}

    static List<Object> all() {
        List<Object> v = new ArrayList<>();
        v.add(roundTrip("silence", new short[BLOCK_SAMPLES]));
        v.add(roundTrip("sine 1 kHz", sine(BLOCK_SAMPLES, 1000, 8000, 0)));
        v.add(roundTrip("sine 3 kHz loud", sine(BLOCK_SAMPLES, 3000, 30000, 0)));
        v.add(roundTrip("full-scale square (clipping)", square(BLOCK_SAMPLES, 500)));
        v.add(roundTrip("noise", noise(BLOCK_SAMPLES, 12345)));
        v.add(roundTrip("ramp", ramp(BLOCK_SAMPLES)));
        v.add(roundTrip("impulse", impulse(BLOCK_SAMPLES)));
        v.add(roundTrip("odd sample count", sine(9, 1000, 8000, 0)));
        v.add(roundTrip("even sample count", sine(8, 1000, 8000, 0)));
        v.add(roundTrip("single sample", new short[] {-1234}));
        v.add(roundTrip("no samples", new short[0]));

        v.add(stream("stateful encoder sine stream", sine(3 * BLOCK_SAMPLES, 1000, 12000, 0)));
        v.add(stream("stateful encoder noise stream", noise(3 * BLOCK_SAMPLES, 777)));

        v.add(decode("decode clamps step index", "34127f00" + "f0f0f0f0", 9));
        v.add(decode("decode stops at sample limit", "00000000" + "77777777", 3));
        v.add(decode("decode header only", "00800000", 249));
        v.add(decode("decode too short", "000000", 249));
        v.add(decode("decode zero samples", "0000000077", 0));
        return v;
    }

    private static Json.Obj roundTrip(String name, short[] pcm) {
        byte[] adpcm = new byte[ImaAdpcm.encodedSize(pcm.length) + 1];
        int encoded = ImaAdpcm.encodeBlock(pcm, 0, pcm.length, adpcm, 0);
        byte[] block = java.util.Arrays.copyOf(adpcm, encoded);
        short[] decoded = new short[pcm.length];
        int written = ImaAdpcm.decodeBlock(block, 0, block.length, decoded, 0, pcm.length);
        return Json.obj().put("name", name)
                .put("input", Json.obj().put("call", "encodeBlock").put("pcm", Json.ints(pcm)))
                .put("expected", Json.obj().put("encodedSize", ImaAdpcm.encodedSize(pcm.length))
                        .put("adpcm", Json.hex(block))
                        .put("decoded", Json.ints(java.util.Arrays.copyOf(decoded, written))));
    }

    private static Json.Obj stream(String name, short[] pcm) {
        ImaAdpcm.Encoder encoder = new ImaAdpcm.Encoder();
        List<Object> blocks = new ArrayList<>();
        for (int offset = 0; offset < pcm.length; offset += BLOCK_SAMPLES) {
            byte[] adpcm = new byte[ImaAdpcm.encodedSize(BLOCK_SAMPLES)];
            int encoded = encoder.encodeBlock(pcm, offset, BLOCK_SAMPLES, adpcm, 0);
            blocks.add(Json.hex(java.util.Arrays.copyOf(adpcm, encoded)));
        }
        return Json.obj().put("name", name)
                .put("input", Json.obj().put("call", "Encoder.encodeBlock").put("blockSamples", BLOCK_SAMPLES)
                        .put("pcm", Json.ints(pcm)))
                .put("expected", Json.obj().put("blocks", blocks));
    }

    private static Json.Obj decode(String name, String adpcmHex, int samples) {
        byte[] adpcm = hexBytes(adpcmHex);
        short[] pcm = new short[Math.max(samples, 1)];
        int written = ImaAdpcm.decodeBlock(adpcm, 0, adpcm.length, pcm, 0, samples);
        return Json.obj().put("name", name)
                .put("input", Json.obj().put("call", "decodeBlock").put("adpcm", adpcmHex).put("samples", samples))
                .put("expected", Json.obj().put("decoded", Json.ints(java.util.Arrays.copyOf(pcm, written))));
    }

    private static short[] sine(int n, double hz, double amplitude, double phase) {
        short[] out = new short[n];
        for (int i = 0; i < n; i++) {
            out[i] = (short) Math.round(amplitude * Math.sin(2 * Math.PI * hz * i / SAMPLE_RATE + phase));
        }
        return out;
    }

    private static short[] square(int n, double hz) {
        short[] out = new short[n];
        int half = (int) (SAMPLE_RATE / hz / 2);
        for (int i = 0; i < n; i++) {
            out[i] = (i / half) % 2 == 0 ? Short.MAX_VALUE : Short.MIN_VALUE;
        }
        return out;
    }

    /** Deterministic noise from a 32-bit LCG, so the vectors never change. */
    private static short[] noise(int n, int seed) {
        short[] out = new short[n];
        int state = seed;
        for (int i = 0; i < n; i++) {
            state = state * 1664525 + 1013904223;
            out[i] = (short) (state >> 16);
        }
        return out;
    }

    private static short[] ramp(int n) {
        short[] out = new short[n];
        for (int i = 0; i < n; i++) {
            out[i] = (short) (Short.MIN_VALUE + (long) i * 65535 / (n - 1));
        }
        return out;
    }

    private static short[] impulse(int n) {
        short[] out = new short[n];
        out[n / 2] = Short.MAX_VALUE;
        return out;
    }

    private static byte[] hexBytes(String hex) {
        byte[] out = new byte[hex.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
        }
        return out;
    }
}
