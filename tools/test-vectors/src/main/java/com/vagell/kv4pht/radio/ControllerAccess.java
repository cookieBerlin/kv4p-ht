package com.vagell.kv4pht.radio;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

/**
 * Lets the vector generator drive the unmodified {@link RadioModuleController}, whose API is package-private.
 * Part of tools/test-vectors, not of the Android app; it only forwards calls.
 */
public final class ControllerAccess {
    private final RadioModuleController controller = new RadioModuleController();
    private final List<byte[]> frames = new ArrayList<>();
    private final Protocol.Sender sender = new Protocol.Sender(bytes -> frames.add(bytes.clone()), false);

    /** Frames sent since the last call. */
    public List<byte[]> takeFrames() {
        List<byte[]> taken = new ArrayList<>(frames);
        frames.clear();
        return taken;
    }

    public boolean inSync() { return controller.isAppliedStateInSync(); }

    public void attach() { controller.attachSender(sender); }
    public void detach() { controller.detachSender(); }
    public void ready() { controller.markTransportReady(); }
    public void seed(byte[] deviceState) { controller.seedFromDeviceState(decode(deviceState)); }
    public void deviceState(byte[] deviceState) { controller.updateDeviceState(decode(deviceState)); }
    public void firmware(byte[] version) {
        controller.seedFirmwareVersion(Protocol.FirmwareVersion.from(ByteBuffer.wrap(version), 0, version.length)
                .orElseThrow());
    }
    public void pttDown() { controller.pttDown(); }
    public void pttUp() { controller.pttUp(); }
    public void begin() { controller.beginUpdate(); }
    public void end() { controller.endUpdate(); }
    public void bandwidth(byte value) { controller.setBandwidth(value); }
    public void txFrequency(float value) { controller.setTxFrequency(value); }
    public void rxFrequency(float value) { controller.setRxFrequency(value); }
    public void memoryId(int value) { controller.setMemoryId(value); }
    public void txTone(byte value) { controller.setTxTone(value); }
    public void rxTone(byte value) { controller.setRxTone(value); }
    public void squelch(int value) { controller.setSquelch(value); }
    public void filters(boolean pre, boolean high, boolean low) { controller.setFilters(pre, high, low); }
    public void highPower(boolean on) { controller.setHighPower(on); }
    public void rssi(boolean on) { controller.setRssi(on); }
    public void txAllowed(boolean on) { controller.setTxAllowed(on); }
    public void freeDv(boolean on) { controller.setFreeDv2400b(on); }
    public void openAudio() { controller.openAudio(); }
    public void closeAudio() { controller.closeAudio(); }
    public void stop() { controller.stop(); }

    private static Protocol.DeviceState decode(byte[] bytes) {
        return Protocol.DeviceState.from(ByteBuffer.wrap(bytes), 0, bytes.length).orElseThrow();
    }
}
