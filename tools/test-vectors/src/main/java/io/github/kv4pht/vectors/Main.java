package io.github.kv4pht.vectors;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.dkaukov.esp32.chip.Esp32ChipId;

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
        write(packages, "KV4PAPRS", "aprs-feed-filter.json", "AprsFeedPolicy.isVisibleToMine", FeedVectors.mine());
        write(packages, "KV4PFlasher", "flasher.json", "FirmwareUtils.flashFirmware (esp32-flash-lib)",
            FlasherVectors.all());
        write(packages, "KV4PFlasher", "packaged-firmware.json", "FirmwareUtils.PACKAGED_FIRMWARE_VER",
            FlasherVectors.packaged());
        writeStub(packages);
    }

    /** The esptool flasher stub esp32-flash-lib loads into an ESP32, copied unchanged as a resource. */
    private static void writeStub(Path packages) throws IOException {
        String name = Esp32ChipId.ESP32.getStubName();
        Path dir = packages.resolve("KV4PFlasher").resolve("Sources").resolve("KV4PFlasher").resolve("Resources");
        Files.createDirectories(dir);
        try (InputStream stub = Main.class.getClassLoader().getResourceAsStream(name)) {
            Files.write(dir.resolve("esp32-stub.json"), stub.readAllBytes());
        }
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
