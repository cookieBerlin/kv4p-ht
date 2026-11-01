package android.content.res;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.Map;

/** Stub for Android resources: raw resources by id. */
public class Resources {
    private final Map<Integer, byte[]> raw;

    public Resources(Map<Integer, byte[]> raw) {
        this.raw = raw;
    }

    public InputStream openRawResource(int id) {
        return new ByteArrayInputStream(raw.get(id));
    }
}
