package android.content;

import android.content.res.Resources;

/** Stub for the Android context: only the raw resources `FirmwareUtils` reads. */
public class Context {
    private final Resources resources;

    public Context(Resources resources) {
        this.resources = resources;
    }

    public Resources getResources() {
        return resources;
    }
}
