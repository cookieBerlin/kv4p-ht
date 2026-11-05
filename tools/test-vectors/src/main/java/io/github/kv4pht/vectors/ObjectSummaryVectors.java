package io.github.kv4pht.vectors;

import com.vagell.kv4pht.ui.ObjectSummaryAccess;
import java.util.ArrayList;
import java.util.List;

/** Vectors from the unmodified `AprsObjectSummary`, which makes repeater objects readable in the APRS tab. */
final class ObjectSummaryVectors {
    private ObjectSummaryVectors() {}

    static List<Object> all() {
        String[][] cases = {
            // object name, comment
            {"N0CALL  B", "RNG0001/A=000010 70cm Voice (D-Star) 439.12500MHz +0.0000MHz, APRS for ircDDBGateway"},
            {"N0CALL C", "RNG0070 2m Voice 146.9125 -0.600 MHz"},
            {"N0CALL-4", "#145.175/439.100 N0CALL-10 Winlink Packet Gateway"},
            {"MEETING", "Club picnic"},
            {"145.500-R", "145.500MHz -0.600 MHz T100 R10k"},
            {"N0CALL", "R25m 145.500MHz"},
            {"N0CALL", "i RNG0010 BBS node"},
            {"N0CALL", "aR5k Data port"},
            {"N0CALL", "/145.500 +0.6 MHz"},
            {"N0CALL", "1450 MHz, , Voice"},
            {"N0CALL", "1234.5MHz"},
            {"N0CALL", "12345 MHz"},
            {"N0CALL", "+145.500 MHz"},
            {"N0CALL", "(Very long mode name that does not fit) 145.500MHz"},
            {"N0CALL", "()"},
            {"N0CALL", "/A=001000"},
            {"  N0   CALL  ", "  spaced   out  "},
            {"N0CALL", ""},
            {"N0CALL", null},
            {"", "Voice"},
            {null, "winlink"},
            {"N0CALL", "145.500MHz +0.000MHz"},
            {"N0CALL", "145.50MHz 100.0"},
        };
        List<Object> vectors = new ArrayList<>();
        for (String[] c : cases) {
            String[] summary = ObjectSummaryAccess.summary(c[0], c[1]);
            vectors.add(Json.obj()
                .put("name", c[0] + " / " + c[1])
                .put("input", Json.obj().put("name", c[0]).put("comment", c[1]))
                .put("expected", Json.obj().put("card", summary[0]).put("label", summary[1])));
        }
        return vectors;
    }
}
