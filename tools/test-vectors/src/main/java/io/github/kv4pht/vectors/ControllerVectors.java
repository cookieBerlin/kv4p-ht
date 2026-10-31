package io.github.kv4pht.vectors;

import com.vagell.kv4pht.radio.ControllerAccess;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/**
 * Scripts for {@link com.vagell.kv4pht.radio.RadioModuleController}: each step is an API call, the expectation is
 * the desired-state frames it sent and whether the applied state is in sync afterwards.
 */
final class ControllerVectors {
    private static final int CONFIG_VALID = 1;
    private static final int PTT = 1 << 1;
    private static final int RX_AUDIO = 1 << 2;
    private static final int HIGH_POWER = 1 << 3;
    private static final int RSSI = 1 << 4;
    private static final int SQUELCHED = 1 << 10;
    private static final int TX_ALLOWED = 1 << 11;
    private static final int REPORTS = 1 << 12;
    private static final int FREEDV = 1 << 13;
    /** What the firmware reports after boot for a stored 145.5 MHz channel. */
    private static final int BOOT_FLAGS = CONFIG_VALID | HIGH_POWER | RSSI | SQUELCHED | TX_ALLOWED;

    private ControllerVectors() {}

    static List<Object> all() {
        List<Object> v = new ArrayList<>();
        v.add(script("connect: seed from HELLO, ready, open audio").attach()
                .seed(state(0, BOOT_FLAGS, 145.5f)).ready().openAudio().vector());
        v.add(script("the device confirms the sent state").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready()
                .deviceState(state(1, BOOT_FLAGS | REPORTS, 145.5f)).vector());
        v.add(script("tuning in one update sends one state").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready()
                .begin().rxFrequency(146.52f).txFrequency(146.52f).memoryId(3).end().vector());
        v.add(script("unchanged values send nothing").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready()
                .rxFrequency(145.5f).highPower(true).vector());
        v.add(script("unbalanced end is ignored").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready().end()
                .squelch(4).vector());
        v.add(script("nested updates send once").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready().begin()
                .begin().squelch(2).end().bandwidth(0).end().vector());
        v.add(script("every setter").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready().bandwidth(0)
                .txTone(5).rxTone(7).squelch(3).filters(true, true, false).filters(false, false, true)
                .highPower(false).rssi(false).txAllowed(false).vector());
        v.add(script("PTT down and up").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready().pttDown().pttUp()
                .vector());
        v.add(script("a lagging device gets the state again, at most three times").attach()
                .seed(state(0, BOOT_FLAGS, 145.5f)).ready().openAudio()
                .deviceState(state(1, BOOT_FLAGS | REPORTS, 145.5f)).deviceState(state(1, BOOT_FLAGS | REPORTS, 145.5f))
                .deviceState(state(1, BOOT_FLAGS | REPORTS, 145.5f)).deviceState(state(1, BOOT_FLAGS | REPORTS, 145.5f))
                .vector());
        v.add(script("a device error is not in sync").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready()
                .deviceState(withError(state(1, BOOT_FLAGS | REPORTS, 145.5f), 1)).vector());
        v.add(script("the watchdog releasing PTT is adopted").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready()
                .openAudio().deviceState(state(2, BOOT_FLAGS | REPORTS | RX_AUDIO, 145.5f)).pttDown()
                .deviceState(state(3, BOOT_FLAGS | REPORTS | RX_AUDIO | PTT, 145.5f))
                .deviceState(state(4, BOOT_FLAGS | REPORTS | RX_AUDIO, 145.5f)).pttDown().vector());
        v.add(script("a newer device sequence while a change is unsent").attach().seed(state(0, BOOT_FLAGS, 145.5f))
                .ready().begin().squelch(6).deviceState(state(9, BOOT_FLAGS | REPORTS, 147.0f)).end().vector());
        v.add(script("a device without radio configuration seeds defaults").attach()
                .seed(state(0, HIGH_POWER | RSSI | SQUELCHED, 0f)).ready().rxFrequency(146.52f).vector());
        v.add(script("nothing is sent before ready or without a sender").rxFrequency(146.0f).attach()
                .rxFrequency(146.52f).seed(state(0, BOOT_FLAGS, 145.5f)).squelch(2).ready().detach().squelch(5)
                .vector());
        v.add(script("FreeDV needs firmware support").attach().seed(state(0, BOOT_FLAGS, 145.5f)).ready()
                .freeDv(true).firmware(version(0x07)).freeDv(true).firmware(version(0x0F)).freeDv(true)
                .freeDv(false).vector());
        v.add(script("close audio and stop clear the session flags").attach().seed(state(0, BOOT_FLAGS, 145.5f))
                .ready().openAudio().pttDown().closeAudio().openAudio().stop().vector());
        return v;
    }

    private static Script script(String name) {
        return new Script(name);
    }

    /** DeviceState with one radio channel; other fields as the firmware reports them in RX. */
    private static byte[] state(int sequence, int flags, float freq) {
        return ByteBuffer.allocate(26).order(ByteOrder.LITTLE_ENDIAN).putInt(sequence).putInt(-1)
                .putShort((short) flags).put((byte) 1).putFloat(freq).putFloat(freq).put((byte) 0).put((byte) 0)
                .put((byte) 0).put((byte) 'f').put((byte) 2).put((byte) 0).put((byte) 0).array();
    }

    private static byte[] withError(byte[] state, int error) {
        byte[] copy = state.clone();
        copy[24] = (byte) error;
        return copy;
    }

    private static byte[] version(int features) {
        return ByteBuffer.allocate(17).order(ByteOrder.LITTLE_ENDIAN).putShort((short) 17).put((byte) 'f')
                .putInt(4096).put((byte) 0).putFloat(134.0f).putFloat(174.0f).put((byte) features).array();
    }

    /** Records each call and its outcome. */
    private static final class Script {
        private final String name;
        private final ControllerAccess controller = new ControllerAccess();
        private final List<Object> calls = new ArrayList<>();
        private final List<Object> outcomes = new ArrayList<>();

        Script(String name) {
            this.name = name;
        }

        Json.Obj vector() {
            return Json.obj().put("name", name).put("input", Json.obj().put("steps", calls))
                    .put("expected", Json.obj().put("steps", outcomes));
        }

        private Script step(Json.Obj call, Runnable action) {
            action.run();
            List<Object> sent = new ArrayList<>();
            controller.takeFrames().forEach(frame -> sent.add(Json.hex(frame)));
            calls.add(call);
            outcomes.add(Json.obj().put("sent", sent).put("inSync", controller.inSync()));
            return this;
        }

        private static Json.Obj call(String op) {
            return Json.obj().put("call", op);
        }

        Script attach() { return step(call("attach"), controller::attach); }
        Script detach() { return step(call("detach"), controller::detach); }
        Script ready() { return step(call("ready"), controller::ready); }
        Script seed(byte[] s) { return step(call("seed").put("bytes", Json.hex(s)), () -> controller.seed(s)); }
        Script deviceState(byte[] s) {
            return step(call("deviceState").put("bytes", Json.hex(s)), () -> controller.deviceState(s));
        }
        Script firmware(byte[] v) {
            return step(call("firmware").put("bytes", Json.hex(v)), () -> controller.firmware(v));
        }
        Script pttDown() { return step(call("pttDown"), controller::pttDown); }
        Script pttUp() { return step(call("pttUp"), controller::pttUp); }
        Script begin() { return step(call("begin"), controller::begin); }
        Script end() { return step(call("end"), controller::end); }
        Script bandwidth(int b) { return step(call("bandwidth").put("int", b), () -> controller.bandwidth((byte) b)); }
        Script txFrequency(float f) {
            return step(call("txFrequency").put("float", f), () -> controller.txFrequency(f));
        }
        Script rxFrequency(float f) {
            return step(call("rxFrequency").put("float", f), () -> controller.rxFrequency(f));
        }
        Script memoryId(int id) { return step(call("memoryId").put("int", id), () -> controller.memoryId(id)); }
        Script txTone(int t) { return step(call("txTone").put("int", t), () -> controller.txTone((byte) t)); }
        Script rxTone(int t) { return step(call("rxTone").put("int", t), () -> controller.rxTone((byte) t)); }
        Script squelch(int s) { return step(call("squelch").put("int", s), () -> controller.squelch(s)); }
        Script filters(boolean pre, boolean high, boolean low) {
            return step(call("filters").put("pre", pre).put("high", high).put("low", low),
                    () -> controller.filters(pre, high, low));
        }
        Script highPower(boolean on) { return step(call("highPower").put("bool", on), () -> controller.highPower(on)); }
        Script rssi(boolean on) { return step(call("rssi").put("bool", on), () -> controller.rssi(on)); }
        Script txAllowed(boolean on) { return step(call("txAllowed").put("bool", on), () -> controller.txAllowed(on)); }
        Script freeDv(boolean on) { return step(call("freeDv").put("bool", on), () -> controller.freeDv(on)); }
        Script openAudio() { return step(call("openAudio"), controller::openAudio); }
        Script closeAudio() { return step(call("closeAudio"), controller::closeAudio); }
        Script stop() { return step(call("stop"), controller::stop); }
    }
}
