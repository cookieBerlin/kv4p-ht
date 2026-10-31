package io.github.kv4pht.vectors;

import com.vagell.kv4pht.radio.Protocol;
import com.vagell.kv4pht.radio.Protocol.DeviceState;
import com.vagell.kv4pht.radio.Protocol.FirmwareVersion;
import com.vagell.kv4pht.radio.Protocol.Hello;
import com.vagell.kv4pht.radio.Protocol.HostDesiredState;
import com.vagell.kv4pht.radio.Protocol.WindowUpdate;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/** Vectors for {@link Protocol}: KISS sender and parser, message codecs, S-meter. */
final class ProtocolVectors {
    private static final int FEND = 0xC0;
    private static final int FESC = 0xDB;
    private static final int SETHARDWARE = 0x06;

    private ProtocolVectors() {}

    // MARK: Sender

    static List<Object> sender() {
        List<Object> v = new ArrayList<>();
        v.add(send("txAx25 plain", in("txAx25").put("payload", Json.hex(seq(0x01, 16))),
                s -> s.txAx25(seq(0x01, 16))));
        v.add(send("txAx25 escapes FEND and FESC", in("txAx25").put("payload", "c0dbdcdd00c0"),
                s -> s.txAx25(bytes(0xC0, 0xDB, 0xDC, 0xDD, 0x00, 0xC0))));
        v.add(send("txAx25 empty", in("txAx25").put("payload", ""), s -> s.txAx25(new byte[0])));
        v.add(send("txAx25 maximum length", in("txAx25").put("payload", Json.hex(seq(0x00, 328))),
                s -> s.txAx25(seq(0x00, 328))));
        v.add(send("txAx25 over maximum length", in("txAx25").put("payload", Json.hex(seq(0x00, 329))),
                s -> s.txAx25(seq(0x00, 329))));

        byte[] block = seq(0x80, 128);
        v.add(send("txAudio ADPCM block", in("txAudio").put("payload", Json.hex(block)).put("len", 128),
                s -> s.txAudio(block, 128)));
        v.add(send("txAudio len shorter than payload", in("txAudio").put("payload", Json.hex(block)).put("len", 10),
                s -> s.txAudio(block, 10)));
        v.add(send("txAudio len zero", in("txAudio").put("payload", Json.hex(block)).put("len", 0),
                s -> s.txAudio(block, 0)));
        byte[] oversize = seq(0x00, 2100);
        v.add(send("txAudio truncated to PROTO_MTU", in("txAudio").put("payload", Json.hex(oversize)).put("len", 2100),
                s -> s.txAudio(oversize, 2100)));

        byte[] digital = bytes(0xC0, 0x11, 0x22, 0xDB, 0x44, 0x55, 0x66);
        v.add(send("txDigital FreeDV frame", in("txDigital").put("payload", Json.hex(digital)),
                s -> s.txDigital(digital)));

        byte[] ax25 = seq(0x40, 20);
        v.add(send("txAx25OnFrequency", in("txAx25OnFrequency").put("freqTx", 144.39f).put("bandwidth", 1)
                .put("ctcssTx", 0).put("payload", Json.hex(ax25)),
                s -> s.txAx25OnFrequency(144.39f, (byte) 1, (byte) 0, ax25)));
        v.add(send("txAx25OnFrequency empty payload", in("txAx25OnFrequency").put("freqTx", 432.5f)
                .put("bandwidth", 0).put("ctcssTx", 12).put("payload", ""),
                s -> s.txAx25OnFrequency(432.5f, (byte) 0, (byte) 12, new byte[0])));
        v.add(send("txAx25OnFrequency over maximum length", in("txAx25OnFrequency").put("freqTx", 144.39f)
                .put("bandwidth", 1).put("ctcssTx", 0).put("payload", Json.hex(seq(0x00, 329))),
                s -> s.txAx25OnFrequency(144.39f, (byte) 1, (byte) 0, seq(0x00, 329))));

        for (int delay : new int[] {0, 50, 0xC0, 255, 256, -1}) {
            v.add(send("setKissTxDelay " + delay, in("setKissTxDelay").put("value", delay),
                    s -> s.setKissTxDelay(delay)));
        }

        for (Json.Obj state : desiredStates()) {
            HostDesiredState hds = hostDesiredState(state);
            v.add(send("sendDesiredState " + state.fields.get("name"),
                    in("sendDesiredState").put("state", fieldsWithoutName(state)), s -> s.sendDesiredState(hds)));
        }
        return v;
    }

    private static Json.Obj in(String call) {
        return Json.obj().put("call", call);
    }

    private static Json.Obj send(String name, Json.Obj input, Consumer<Protocol.Sender> action) {
        List<Object> frames = new ArrayList<>();
        Protocol.Sender sender = new Protocol.Sender(bytes -> frames.add(Json.hex(bytes)), false);
        Json.Obj expected = Json.obj();
        try {
            action.accept(sender);
            expected.put("frames", frames);
        } catch (IllegalArgumentException e) {
            expected.put("error", "invalidArgument");
        }
        return Json.obj().put("name", name).put("input", input).put("expected", expected);
    }

    private static List<Json.Obj> desiredStates() {
        return List.of(
                desired("all zero", 0, 0, 0, 0, 0f, 0f, 0, 0, 0),
                desired("VHF simplex", 1, 3, 0x1015, 1, 146.52f, 146.52f, 0, 4, 0),
                desired("UHF repeater with CTCSS", 0x7FFFFFFF, -1, 0x3FFF, 0, 444.95f, 449.95f, 12, 8, 12),
                desired("bytes that need escaping", 0xC0DBC0DB, 0xDB, 0xC0, 0xC0, 145.5f, 145.5f, 0xDB, 0xC0, 0xDB),
                desired("negative sequence", Integer.MIN_VALUE, 0, 0xFFFF, 0xFF, 134.0f, 174.0f, 0xFF, 0xFF, 0xFF));
    }

    private static Json.Obj desired(String name, int sequence, int memoryId, int flags, int bw, float freqTx,
            float freqRx, int ctcssTx, int squelch, int ctcssRx) {
        return Json.obj().put("name", name).put("sequence", sequence).put("memoryId", memoryId).put("flags", flags)
                .put("bw", bw).put("freqTx", freqTx).put("freqRx", freqRx).put("ctcssTx", ctcssTx)
                .put("squelch", squelch).put("ctcssRx", ctcssRx);
    }

    private static Json.Obj fieldsWithoutName(Json.Obj state) {
        Json.Obj copy = Json.obj();
        state.fields.forEach((k, val) -> {
            if (!k.equals("name")) {
                copy.put(k, val);
            }
        });
        return copy;
    }

    private static HostDesiredState hostDesiredState(Json.Obj s) {
        return HostDesiredState.builder()
                .sequence(i(s, "sequence"))
                .memoryId(i(s, "memoryId"))
                .flags(i(s, "flags"))
                .bw((byte) i(s, "bw"))
                .freqTx((Float) s.fields.get("freqTx"))
                .freqRx((Float) s.fields.get("freqRx"))
                .ctcssTx((byte) i(s, "ctcssTx"))
                .squelch((byte) i(s, "squelch"))
                .ctcssRx((byte) i(s, "ctcssRx"))
                .build();
    }

    private static int i(Json.Obj s, String key) {
        return (Integer) s.fields.get(key);
    }

    // MARK: Parser

    static List<Object> parser() {
        byte[] hello = helloBytes();
        List<Object> v = new ArrayList<>();
        v.add(parse("DATA frame", frame(0x00, seq(0x01, 20))));
        v.add(parse("DATA frame with escaped bytes", frame(0x00, bytes(0xC0, 0xDB, 0x01, 0xC0))));
        v.add(parse("garbage before first FEND is ignored", concat(bytes(0x01, 0x02, 0xDB, 0xDC), frame(0x00, seq(0, 4)))));
        v.add(parse("empty frames are ignored", bytes(FEND, FEND, FEND)));
        v.add(parse("frames sharing one FEND", concat(frame(0x00, seq(1, 3)), dropLeading(frame(0x00, seq(9, 3))))));
        v.add(parse("unknown escape drops the frame", concat(
                bytes(FEND, 0x00, 0x01, FESC, 0x42, 0x02, FEND), frame(0x00, seq(5, 2)))));
        v.add(parse("trailing FESC before FEND", bytes(FEND, 0x00, 0x01, 0x02, FESC, FEND)));
        v.add(parse("frame without closing FEND is not emitted", bytes(FEND, 0x00, 0x01, 0x02)));
        v.add(parse("DATA payload at maximum length", frame(0x00, seq(0, 328))));
        v.add(parse("DATA payload over maximum length", frame(0x00, seq(0, 329))));
        v.add(parse("DATA frame on port 1 is ignored", frame(0x10, seq(0, 4))));
        v.add(parse("TXDELAY frame is ignored", frame(0x01, bytes(0x32))));
        v.add(parse("oversize frame is dropped", concat(frame(0x00, seq(0, 2100)), frame(0x00, seq(7, 2)))));

        v.add(parse("HELLO", vendor(0x06, hello)));
        v.add(parse("DEVICE_STATE", vendor(0x0B, deviceStateBytes(5, 1, 0x0705, 'f', 1, 0, 120))));
        v.add(parse("WINDOW_UPDATE", vendor(0x09, le(4).putInt(2048).array())));
        v.add(parse("RX_AUDIO", vendor(0x0C, seq(0x80, 128))));
        v.add(parse("RX_DIGITAL", vendor(0x0E, bytes(0x01, 0xC0, 0x03, 0xDB, 0x05, 0x06, 0x07))));
        v.add(parse("DEBUG_INFO", vendor(0x01, "boot ok".getBytes())));
        for (int cmd : new int[] {0x02, 0x03, 0x04, 0x05}) {
            v.add(parse(String.format("DEBUG command 0x%02x", cmd), vendor(cmd, "msg".getBytes())));
        }
        v.add(parse("vendor frame without payload", vendor(0x09, new byte[0])));
        v.add(parse("vendor payload at PROTO_MTU", vendor(0x0C, seq(0, 2048))));
        v.add(parse("unknown vendor command is ignored", vendor(0x7F, seq(0, 3))));
        v.add(parse("wrong vendor prefix is ignored", frame(SETHARDWARE, concat("KV4Q".getBytes(), bytes(0x01, 0x06)))));
        v.add(parse("wrong protocol version is ignored", frame(SETHARDWARE, concat("KV4P".getBytes(), bytes(0x02, 0x06)))));
        v.add(parse("vendor header too short is ignored", frame(SETHARDWARE, "KV4P".getBytes())));
        v.add(parse("mixed stream", concat(vendor(0x09, le(4).putInt(512).array()), frame(0x00, seq(0x30, 5)),
                vendor(0x0C, seq(0, 8)))));
        return v;
    }

    private static Json.Obj parse(String name, byte[] stream) {
        List<Object> events = new ArrayList<>();
        Protocol.KissParser parser = new Protocol.KissParser(
                (cmd, buffer, offset, len) -> events.add(Json.obj().put("type", "command")
                        .put("command", cmd.getValue()).put("payload", Json.hex(slice(buffer, offset, len)))),
                (buffer, offset, len) -> events.add(Json.obj().put("type", "ax25")
                        .put("payload", Json.hex(slice(buffer, offset, len)))));
        parser.processBytes(stream);
        return Json.obj().put("name", name).put("input", Json.obj().put("stream", Json.hex(stream)))
                .put("expected", Json.obj().put("events", events));
    }

    private static byte[] slice(ByteBuffer buffer, int offset, int len) {
        byte[] out = new byte[len];
        for (int i = 0; i < len; i++) {
            out[i] = buffer.get(offset + i);
        }
        return out;
    }

    /** Builds an escaped KISS frame as the firmware would send it. */
    private static byte[] frame(int commandByte, byte[] body) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(FEND);
        out.write(commandByte);
        for (byte b : body) {
            int value = b & 0xFF;
            if (value == FEND) {
                out.write(FESC);
                out.write(0xDC);
            } else if (value == FESC) {
                out.write(FESC);
                out.write(0xDD);
            } else {
                out.write(value);
            }
        }
        out.write(FEND);
        return out.toByteArray();
    }

    private static byte[] vendor(int command, byte[] payload) {
        return frame(SETHARDWARE, concat("KV4P".getBytes(), bytes(0x01, command), payload));
    }

    private static byte[] dropLeading(byte[] frame) {
        byte[] out = new byte[frame.length - 1];
        System.arraycopy(frame, 1, out, 0, out.length);
        return out;
    }

    // MARK: Messages

    static List<Object> messages() {
        List<Object> v = new ArrayList<>();
        for (Json.Obj state : desiredStates()) {
            v.add(Json.obj().put("name", "HostDesiredState " + state.fields.get("name"))
                    .put("input", Json.obj().put("type", "HostDesiredState").put("state", fieldsWithoutName(state)))
                    .put("expected", Json.obj().put("bytes", Json.hex(hostDesiredState(state).toBytes()))));
        }

        v.add(decode("DeviceState receiving", "DeviceState", deviceStateBytes(7, 2, 0x0705, 'f', 1, 0, 128)));
        v.add(decode("DeviceState transmitting with error", "DeviceState",
                deviceStateBytes(-2, 0, 0x0B0B, 'f', 0, 3, 0)));
        v.add(decode("DeviceState radio not found", "DeviceState", deviceStateBytes(0, 0, 0x0000, 'x', 2, 9, 255)));
        v.add(decode("DeviceState unknown status and mode", "DeviceState",
                deviceStateBytes(1, 1, 0xFFFF, 'q', 7, 255, 1)));
        v.add(decode("DeviceState wrong length", "DeviceState", 25, deviceStateBytes(1, 1, 0x0001, 'f', 1, 0, 0)));

        v.add(decode("FirmwareVersion VHF all features", "FirmwareVersion",
                versionBytes(17, 'f', 4096, 0, 134.0f, 174.0f, 0x0B)));
        v.add(decode("FirmwareVersion UHF no features", "FirmwareVersion",
                versionBytes(16, 'x', 1024, 1, 400.0f, 480.0f, 0x00)));
        v.add(decode("FirmwareVersion only physical PTT", "FirmwareVersion",
                versionBytes(17, 'u', 0, 0, 144.0f, 148.0f, 0x02)));
        v.add(decode("FirmwareVersion unknown status and high version", "FirmwareVersion",
                versionBytes(0xFFFF, 'z', -1, 1, 420.0f, 450.0f, 0xF4)));
        v.add(decode("FirmwareVersion unknown module type", "FirmwareVersion",
                versionBytes(17, 'f', 4096, 2, 134.0f, 174.0f, 0x0B)));
        v.add(decode("FirmwareVersion wrong length", "FirmwareVersion", 16,
                versionBytes(17, 'f', 4096, 0, 134.0f, 174.0f, 0x0B)));

        v.add(decode("Hello", "Hello", helloBytes()));
        v.add(decode("Hello wrong length", "Hello", 42, helloBytes()));
        v.add(decode("Hello unknown module type", "Hello",
                concat(versionBytes(17, 'f', 4096, 9, 134.0f, 174.0f, 0x0B),
                        deviceStateBytes(0, 0, 0, 'f', 2, 0, 0))));

        v.add(decode("WindowUpdate", "WindowUpdate", le(4).putInt(4096).array()));
        v.add(decode("WindowUpdate large", "WindowUpdate", le(4).putInt(-1).array()));
        v.add(decode("WindowUpdate wrong length", "WindowUpdate", 3, le(4).putInt(4096).array()));
        return v;
    }

    private static Json.Obj decode(String name, String type, byte[] bytes) {
        return decode(name, type, bytes.length, bytes);
    }

    private static Json.Obj decode(String name, String type, int len, byte[] bytes) {
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        Json.Obj expected = Json.obj();
        try {
            Object value = switch (type) {
                case "DeviceState" -> DeviceState.from(buffer, 0, len).map(ProtocolVectors::json).orElse(null);
                case "FirmwareVersion" -> FirmwareVersion.from(buffer, 0, len).map(ProtocolVectors::json).orElse(null);
                case "Hello" -> Hello.from(buffer, 0, len).map(h -> Json.obj()
                        .put("version", json(h.getVersion())).put("deviceState", json(h.getDeviceState())))
                        .orElse(null);
                case "WindowUpdate" -> WindowUpdate.from(buffer, 0, len)
                        .map(w -> Json.obj().put("size", w.getSize())).orElse(null);
                default -> throw new IllegalStateException(type);
            };
            expected.put("value", value);
        } catch (IllegalArgumentException e) {
            expected.put("error", "invalidArgument");
        }
        return Json.obj().put("name", name)
                .put("input", Json.obj().put("type", type).put("bytes", Json.hex(bytes)).put("len", len))
                .put("expected", expected);
    }

    private static Json.Obj json(DeviceState s) {
        return Json.obj().put("appliedSequence", s.getAppliedSequence()).put("memoryId", s.getMemoryId())
                .put("flags", s.getFlags()).put("bw", (int) s.getBw()).put("freqTx", s.getFreqTx())
                .put("freqRx", s.getFreqRx()).put("ctcssTx", (int) s.getCtcssTx()).put("squelch", (int) s.getSquelch())
                .put("ctcssRx", (int) s.getCtcssRx()).put("radioModuleStatus", s.getRadioModuleStatus().name())
                .put("mode", s.getMode().name()).put("lastError", s.getLastError())
                .put("latestRssi", s.getLatestRssi()).put("hasRadioConfig", s.hasRadioConfig());
    }

    private static Json.Obj json(FirmwareVersion f) {
        return Json.obj().put("ver", (int) f.getVer()).put("radioModuleStatus", f.getRadioModuleStatus().name())
                .put("windowSize", f.getWindowSize()).put("moduleType", f.getModuleType().name())
                .put("minRadioFreq", f.getMinRadioFreq()).put("maxRadioFreq", f.getMaxRadioFreq())
                .put("hasHl", f.isHasHl()).put("hasPhysPtt", f.isHasPhysPtt())
                .put("hasFreeDv2400b", f.isHasFreeDv2400b());
    }

    private static byte[] helloBytes() {
        return concat(versionBytes(17, 'f', 4096, 0, 134.0f, 174.0f, 0x0B),
                deviceStateBytes(0, 0, 0x0000, 'f', 2, 0, 0));
    }

    private static byte[] versionBytes(int ver, char status, int window, int module, float min, float max,
            int features) {
        return le(17).putShort((short) ver).put((byte) status).putInt(window).put((byte) module).putFloat(min)
                .putFloat(max).put((byte) features).array();
    }

    private static byte[] deviceStateBytes(int sequence, int memoryId, int flags, char status, int mode,
            int lastError, int rssi) {
        return le(26).putInt(sequence).putInt(memoryId).putShort((short) flags).put((byte) 1).putFloat(146.52f)
                .putFloat(146.52f).put((byte) 0).put((byte) 4).put((byte) 0).put((byte) status).put((byte) mode)
                .put((byte) lastError).put((byte) rssi).array();
    }

    // MARK: S-meter

    static List<Object> sMeter() {
        List<Object> v = new ArrayList<>();
        for (int rssi = 0; rssi <= 255; rssi++) {
            v.add(Json.obj().put("name", "rssi " + rssi).put("input", Json.obj().put("rssi", rssi))
                    .put("expected", Json.obj().put("sMeter", Protocol.calculateSMeterValue(rssi))));
        }
        return v;
    }

    // MARK: Byte helpers

    private static ByteBuffer le(int size) {
        return ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN);
    }

    static byte[] bytes(int... values) {
        byte[] out = new byte[values.length];
        for (int i = 0; i < values.length; i++) {
            out[i] = (byte) values[i];
        }
        return out;
    }

    static byte[] seq(int start, int count) {
        byte[] out = new byte[count];
        for (int i = 0; i < count; i++) {
            out[i] = (byte) (start + i);
        }
        return out;
    }

    static byte[] concat(byte[]... parts) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (byte[] p : parts) {
            out.writeBytes(p);
        }
        return out.toByteArray();
    }
}
