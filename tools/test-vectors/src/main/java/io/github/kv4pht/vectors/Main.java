package io.github.kv4pht.vectors;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Writes golden test vectors produced by the unmodified Android code to
 * apple-src/Packages/&lt;Module&gt;/Tests/&lt;Module&gt;Tests/Vectors/.
 * Output is deterministic; CI regenerates it and fails on any diff.
 */
public final class Main {
    private Main() {}

    public static void main(String[] args) throws Exception {
        Path packages = Path.of(args[0]);
        write(packages, "KV4PProtocol", "kiss-sender.json", "Protocol.Sender", ProtocolVectors.sender());
        write(packages, "KV4PProtocol", "kiss-parser.json", "Protocol.KissParser", ProtocolVectors.parser());
        write(packages, "KV4PProtocol", "messages.json", "Protocol message decoders", ProtocolVectors.messages());
        write(packages, "KV4PProtocol", "s-meter.json", "Protocol.calculateSMeterValue", ProtocolVectors.sMeter());
        write(packages, "KV4PRadio", "desired-state.json", "RadioModuleController", ControllerVectors.all());
        write(packages, "KV4PProtocol", "ctcss.json", "ToneHelper", ToneVectors.all());
        write(packages, "KV4PAudio", "ima-adpcm.json", "ImaAdpcm", AdpcmVectors.all());
        write(packages, "KV4PAPRS", "ax25-packets.json", "javAX25 Packet", Ax25Vectors.all());
        write(packages, "KV4PAPRS", "aprs-parser.json", "java-aprs Parser.parseAX25", AprsVectors.parser());
        write(packages, "KV4PAPRS", "aprs-events.json", "java-aprs AprsController.handle", AprsVectors.events());
        write(packages, "KV4PAPRS", "aprs-messaging.json", "java-aprs AprsController messaging",
            AprsVectors.messaging());
        write(packages, "KV4PAPRS", "aprs-beacons.json", "java-aprs AprsController.submitPositionBeacon",
            AprsVectors.beacons());
        write(packages, "KV4PAPRS", "aprs-digipeating.json", "java-aprs AprsController digipeating",
            AprsVectors.digipeating());
        write(packages, "KV4PAPRS", "aprs-internet.json", "java-aprs AprsController APRS-IS and iGate",
            AprsVectors.internet());
        write(packages, "KV4PAPRS", "aprs-is-login.json", "java-aprs AprsIsClient login", AprsVectors.login());
        write(packages, "KV4PAPRS", "aprs-encoding.json", "java-aprs MessagePacket and APRSPacket.toAX25Frame",
            AprsVectors.encoding());
    }

    private static void write(Path packages, String module, String file, String source, List<Object> vectors)
            throws IOException {
        Path dir = packages.resolve(module).resolve("Tests").resolve(module + "Tests").resolve("Vectors");
        Files.createDirectories(dir);
        Json.Obj root = Json.obj()
                .put("generator", "tools/test-vectors")
                .put("source", source)
                .put("vectors", vectors);
        Files.writeString(dir.resolve(file), Json.write(root), StandardCharsets.UTF_8);
    }
}
