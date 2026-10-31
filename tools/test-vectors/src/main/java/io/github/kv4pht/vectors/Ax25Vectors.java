package io.github.kv4pht.vectors;

import com.vagell.kv4pht.javAX25.ax25.Packet;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Vectors for the javAX25 {@link Packet}: encoding with CRC, parsing and formatting. */
final class Ax25Vectors {
    private Ax25Vectors() {}

    static List<Object> all() {
        List<Object> v = new ArrayList<>();
        v.add(packet("position without path", "APRS", "N0CALL", new String[] {}, "!4903.50N/07201.75W-Test"));
        v.add(packet("position with WIDE path", "APRS", "N0CALL-9", new String[] {"WIDE1-1", "WIDE2-2"},
                "=4903.50N/07201.75W>mobile"));
        v.add(packet("message with SSID 15", "APZ001", "N0CALL-15", new String[] {"WIDE2-1"},
                ":N0CALL-1 :hello{001"));
        v.add(packet("lower case and long call are normalised", "aprs", "n0call7x", new String[] {}, ">status"));
        v.add(packet("invalid SSID becomes 0", "APRS", "N0CALL-16", new String[] {}, ">status"));
        v.add(packet("empty payload", "APRS", "N0CALL", new String[] {}, ""));
        v.add(packet("eight digipeaters", "APRS", "N0CALL", new String[] {
            "WIDE1-1", "WIDE2-1", "WIDE3-1", "WIDE4-1", "WIDE5-1", "WIDE6-1", "WIDE7-1", "RELAY"}, ">x"));
        v.add(packet("binary payload", "APRS", "N0CALL", new String[] {}, "ÀÛ\u0000ÿ"));
        return v;
    }

    private static Json.Obj packet(String name, String destination, String source, String[] path, String payload) {
        byte[] payloadBytes = payload.getBytes(StandardCharsets.ISO_8859_1);
        Packet built = new Packet(destination, source, path, Packet.AX25_CONTROL_APRS,
                Packet.AX25_PROTOCOL_NO_LAYER_3, payloadBytes);
        byte[] frame = built.bytesWithoutCRC();

        Packet parsed = new Packet(frame);
        parsed.parse();
        List<Object> parsedPath = new ArrayList<>();
        if (parsed.path != null) {
            for (String p : parsed.path) {
                parsedPath.add(p);
            }
        }
        List<Object> inputPath = new ArrayList<>(List.of((Object[]) path));
        return Json.obj().put("name", name)
                .put("input", Json.obj().put("destination", destination).put("source", source)
                        .put("path", inputPath).put("control", Packet.AX25_CONTROL_APRS)
                        .put("protocol", Packet.AX25_PROTOCOL_NO_LAYER_3).put("payload", Json.hex(payloadBytes)))
                .put("expected", Json.obj().put("bytes", Json.hex(frame))
                        .put("bytesWithCRC", Json.hex(built.bytesWithCRC()))
                        .put("parsed", Json.obj().put("destination", parsed.destination).put("source", parsed.source)
                                .put("path", parsedPath).put("payload", Json.hex(parsed.payload)))
                        .put("formatted", Packet.format(frame)));
    }
}
