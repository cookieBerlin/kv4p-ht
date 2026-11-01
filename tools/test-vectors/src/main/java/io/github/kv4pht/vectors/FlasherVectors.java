package io.github.kv4pht.vectors;

import android.content.Context;
import android.content.res.Resources;
import com.hoho.android.usbserial.driver.UsbSerialPort;
import com.vagell.kv4pht.R;
import com.vagell.kv4pht.firmware.FirmwareUtils;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.zip.DataFormatException;
import java.util.zip.Inflater;
import org.dkaukov.esp32.utils.Utils;

/**
 * Vectors from the unmodified `FirmwareUtils.flashFirmware` (esp32-flash-lib), flashing synthetic images into a fake
 * ESP32 ROM bootloader. The transcript holds everything in order: serial parameters, DTR/RTS, the bytes the app writes,
 * the bytes the device answers and the callbacks.
 */
final class FlasherVectors {
    private FlasherVectors() {}

    /** How the fake device behaves. */
    enum Device {
        /** Answers like an ESP32 with the flasher stub loaded. */
        WORKING,
        /** Reports a wrong MD5 for every region. */
        WRONG_MD5,
        /** Never answers, like a radio that is not in the bootloader. */
        SILENT
    }

    /** Attempts to get two equal transcripts in a row. */
    private static final int ATTEMPTS = 5;

    static List<Object> all() throws Exception {
        // The first flash loads the library's classes, which can take longer than its 100 ms reply timeout.
        vector("warm-up", Device.WORKING);
        return Json.list(
            stable("flash", Device.WORKING),
            stable("wrong md5", Device.WRONG_MD5),
            stable("no answer", Device.SILENT));
    }

    /**
     * The library waits for replies in real time, so a stalled runner can make it miss one and retry. Only a transcript
     * that two flashes in a row produce is kept.
     */
    private static Object stable(String name, Device device) throws Exception {
        String previous = Json.write(vector(name, device));
        for (int attempt = 1; attempt < ATTEMPTS; attempt++) {
            Object next = vector(name, device);
            if (Json.write(next).equals(previous)) {
                return next;
            }
            previous = Json.write(next);
        }
        throw new IllegalStateException("flasher vector '" + name + "' differs between runs");
    }

    static List<Object> packaged() {
        return Json.list(Json.obj()
            .put("name", "packaged firmware")
            .put("input", Json.obj())
            .put("expected", Json.obj().put("version", FirmwareUtils.PACKAGED_FIRMWARE_VER)));
    }

    private static Object vector(String name, Device device) throws Exception {
        byte[] bootloader = pseudoRandom(0x600, 1);
        byte[] partitions = partitions();
        byte[] bootApp0 = filled(0x2000, (byte) 0xFF);
        byte[] app = app();
        Context context = new Context(new Resources(Map.of(
            R.raw.bootloader, bootloader,
            R.raw.partitions, partitions,
            R.raw.boot_app0, bootApp0,
            R.raw.firmware_v17, app)));
        FakeEsp32 esp32 = new FakeEsp32(device);
        FirmwareUtils.flashFirmware(context, esp32, new FirmwareUtils.FirmwareCallback() {
            @Override
            public void connectedToBootloader() {
                esp32.transcript.add(Json.obj().put("event", "connected"));
            }

            @Override
            public void reportProgress(int percent) {
                esp32.transcript.add(Json.obj().put("event", "progress").put("value", percent));
            }

            @Override
            public void doneFlashing(boolean success) {
                esp32.transcript.add(Json.obj().put("event", "done").put("success", success));
            }
        });
        return Json.obj()
            .put("name", name)
            .put("input", Json.obj()
                .put("bootloader", Json.hex(bootloader))
                .put("partitions", Json.hex(partitions))
                .put("bootApp0", Json.hex(bootApp0))
                .put("app", Json.hex(app)))
            .put("expected", Json.obj().put("transcript", esp32.transcript));
    }

    /** Bytes of a 32-bit linear congruential generator; they include SLIP's 0xC0 and 0xDB. */
    private static byte[] pseudoRandom(int length, int seed) {
        byte[] bytes = new byte[length];
        int state = seed;
        for (int i = 0; i < length; i++) {
            state = state * 1664525 + 1013904223;
            bytes[i] = (byte) (state >>> 24);
        }
        return bytes;
    }

    private static byte[] filled(int length, byte value) {
        byte[] bytes = new byte[length];
        Arrays.fill(bytes, value);
        return bytes;
    }

    /** A partition table entry, then erased flash. */
    private static byte[] partitions() {
        byte[] bytes = filled(0xC00, (byte) 0xFF);
        byte[] entry = "ªP\u0000\u0000\u0000\u0000\u0001\u0000app0".getBytes(StandardCharsets.ISO_8859_1);
        System.arraycopy(entry, 0, bytes, 0, entry.length);
        return bytes;
    }

    /** Incompressible code, then repetitive data: two compressed blocks of 16 KiB. */
    private static byte[] app() {
        byte[] code = pseudoRandom(0x4000, 7);
        byte[] text = "kv4p HT firmware test image. ".repeat(140).getBytes(StandardCharsets.US_ASCII);
        byte[] app = Arrays.copyOf(code, code.length + text.length);
        System.arraycopy(text, 0, app, code.length, text.length);
        return app;
    }

    /** An ESP32 in its ROM bootloader that loads the flasher stub (esptool serial protocol). */
    static final class FakeEsp32 implements UsbSerialPort {
        private static final byte SLIP_END = (byte) 0xC0;
        private static final byte SLIP_ESC = (byte) 0xDB;
        private static final int CHIP_MAGIC = 0x00f01d83;

        final List<Object> transcript = new ArrayList<>();
        private final Device device;
        private final ByteArrayOutputStream frame = new ByteArrayOutputStream();
        private final ByteArrayOutputStream replies = new ByteArrayOutputStream();
        private byte[] unread = new byte[0];
        private boolean inFrame;
        private boolean escaped;
        private boolean stub;
        private int regionOffset;
        private ByteArrayOutputStream region = new ByteArrayOutputStream();
        private Inflater inflater;

        FakeEsp32(Device device) {
            this.device = device;
        }

        @Override
        public int read(byte[] dest, int length, int timeout) {
            if (unread.length == 0) {
                Utils.delayMS(1);
                return 0;
            }
            int count = Math.min(length, unread.length);
            System.arraycopy(unread, 0, dest, 0, count);
            unread = Arrays.copyOfRange(unread, count, unread.length);
            return count;
        }

        @Override
        public void write(byte[] src, int length, int timeout) {
            byte[] bytes = Arrays.copyOf(src, length);
            transcript.add(Json.obj().put("event", "write").put("bytes", Json.hex(bytes)));
            for (byte b : bytes) {
                receive(b);
            }
            if (replies.size() > 0) {
                byte[] reply = replies.toByteArray();
                replies.reset();
                transcript.add(Json.obj().put("event", "reply").put("bytes", Json.hex(reply)));
                byte[] all = Arrays.copyOf(unread, unread.length + reply.length);
                System.arraycopy(reply, 0, all, unread.length, reply.length);
                unread = all;
            }
        }

        @Override
        public void setParameters(int baudRate, int dataBits, int stopBits, int parity) {
            transcript.add(Json.obj().put("event", "baud").put("value", baudRate));
        }

        @Override
        public void setDTRandRTS(boolean dtr, boolean rts) {
            transcript.add(Json.obj().put("event", "lines").put("dtr", dtr).put("rts", rts));
        }

        private void receive(byte b) {
            if (b == SLIP_END) {
                if (inFrame && frame.size() > 0) {
                    handle(frame.toByteArray());
                }
                frame.reset();
                inFrame = true;
                escaped = false;
            } else if (escaped) {
                frame.write(b == (byte) 0xDC ? 0xC0 : b == (byte) 0xDD ? 0xDB : b);
                escaped = false;
            } else if (b == SLIP_ESC) {
                escaped = true;
            } else if (inFrame) {
                frame.write(b);
            }
        }

        private void handle(byte[] packet) {
            if (device == Device.SILENT) {
                return;
            }
            ByteBuffer header = ByteBuffer.wrap(packet).order(ByteOrder.LITTLE_ENDIAN);
            byte op = header.get(1);
            ByteBuffer data = ByteBuffer.wrap(packet, 8, packet.length - 8).slice().order(ByteOrder.LITTLE_ENDIAN);
            switch (op) {
                case 0x0A -> reply(op, CHIP_MAGIC, new byte[0]); // READ_REG
                case 0x06 -> { // MEM_END: the stub starts and says hello
                    reply(op, 0, new byte[0]);
                    send("OHAI".getBytes(StandardCharsets.US_ASCII));
                    stub = true;
                }
                case 0x02 -> begin(data.getInt(12), false); // FLASH_BEGIN
                case 0x10 -> begin(data.getInt(12), true); // FLASH_DEFL_BEGIN
                case 0x03, 0x11 -> { // FLASH_DATA, FLASH_DEFL_DATA
                    byte[] chunk = Arrays.copyOfRange(packet, 8 + 16, 8 + 16 + data.getInt(0));
                    store(chunk);
                    reply(op, 0, new byte[0]);
                }
                case 0x13 -> reply(op, 0, md5(data.getInt(4))); // SPI_FLASH_MD5
                default -> reply(op, 0, new byte[0]); // SYNC, CHANGE_BAUDRATE, MEM_BEGIN, MEM_DATA
            }
        }

        private void begin(int offset, boolean compressed) {
            regionOffset = offset;
            region = new ByteArrayOutputStream();
            inflater = compressed ? new Inflater() : null;
            reply(compressed ? (byte) 0x10 : (byte) 0x02, 0, new byte[0]);
        }

        private void store(byte[] chunk) {
            if (inflater == null) {
                region.writeBytes(chunk);
                return;
            }
            inflater.setInput(chunk);
            byte[] buffer = new byte[0x10000];
            try {
                int count;
                while ((count = inflater.inflate(buffer)) > 0) {
                    region.write(buffer, 0, count);
                }
            } catch (DataFormatException e) {
                throw new IllegalStateException("region at " + regionOffset + " is not zlib data", e);
            }
        }

        private byte[] md5(int size) {
            try {
                byte[] digest = MessageDigest.getInstance("MD5").digest(Arrays.copyOf(region.toByteArray(), size));
                if (device == Device.WRONG_MD5) {
                    digest[0] ^= 0x01;
                }
                return digest;
            } catch (java.security.NoSuchAlgorithmException e) {
                throw new IllegalStateException(e);
            }
        }

        /** Response: direction 1, opcode, length, value, data, then the status (ROM: 4 bytes, stub: 2 bytes). */
        private void reply(byte op, int value, byte[] data) {
            byte[] status = new byte[stub ? 2 : 4];
            ByteBuffer packet = ByteBuffer.allocate(8 + data.length + status.length).order(ByteOrder.LITTLE_ENDIAN);
            packet.put((byte) 0x01).put(op).putShort((short) (data.length + status.length)).putInt(value);
            packet.put(data).put(status);
            send(packet.array());
        }

        private void send(byte[] packet) {
            replies.writeBytes(Utils.slipEncode(packet));
        }
    }
}
