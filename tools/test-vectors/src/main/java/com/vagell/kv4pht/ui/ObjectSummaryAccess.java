package com.vagell.kv4pht.ui;

/**
 * Lets the vector generator read the unmodified {@link AprsObjectSummary}, which is package-private.
 * Part of tools/test-vectors, not of the Android app.
 */
public final class ObjectSummaryAccess {
    private ObjectSummaryAccess() {}

    /** The card text and the map label. */
    public static String[] summary(String name, String comment) {
        AprsObjectSummary summary = AprsObjectSummary.from(name, comment);
        return new String[] {summary.cardText, summary.mapLabel};
    }
}
