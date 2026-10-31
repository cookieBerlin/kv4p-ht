package com.vagell.kv4pht.ui;

import java.util.List;

/**
 * Lets the vector generator read the tone table of the unmodified {@link ToneHelper}, which is package-visible.
 * Part of tools/test-vectors, not of the Android app.
 */
public final class ToneAccess {
    private ToneAccess() {}

    public static List<String> tones() {
        return ToneHelper.VALID_TONE_STRINGS;
    }
}
