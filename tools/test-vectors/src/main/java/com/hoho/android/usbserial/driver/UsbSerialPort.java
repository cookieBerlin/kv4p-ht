package com.hoho.android.usbserial.driver;

import java.io.IOException;

/**
 * Stub of the usb-serial-for-android port (android-src/KV4PHT/usbSerialForAndroid) with the members
 * `FirmwareUtils` uses.
 */
public interface UsbSerialPort {
    int DATABITS_8 = 8;
    int PARITY_NONE = 0;
    int STOPBITS_1 = 1;

    int read(byte[] dest, int length, int timeout) throws IOException;

    void write(byte[] src, int length, int timeout) throws IOException;

    void setParameters(int baudRate, int dataBits, int stopBits, int parity) throws IOException;

    void setDTRandRTS(boolean dtr, boolean rts) throws IOException;
}
