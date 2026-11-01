package io.github.kv4pht.vectors;

import com.vagell.kv4pht.data.AprsFeedPolicy;
import io.github.dkaukov.aprs.AprsEvent;
import java.util.ArrayList;
import java.util.List;

/** Vectors from the unmodified `AprsFeedPolicy.isVisibleToMine`, the APRS tab's "Only mine" filter. */
final class FeedVectors {
    private FeedVectors() {}

    static List<Object> mine() {
        String[][] cases = {
            // type, from, to, local callsign
            {"message", "N1CALL", "N0CALL", "N0CALL"},
            {"message", "N0CALL", "N1CALL", "n0call "},
            {"message", "N0CALL-0", "N1CALL", "N0CALL"},
            {"message", "N1CALL", "N0CALL-0", "N0CALL-0"},
            {"message", "N1CALL", "N0CALL-7", "N0CALL"},
            {"message", "N1CALL", "N2CALL", "N0CALL"},
            {"message", "N1CALL", "ALL", "N0CALL"},
            {"message", "N1CALL", "qst", "N0CALL"},
            {"message", "N1CALL", "CQ", "N0CALL"},
            {"message", "N1CALL", "BLN1", "N0CALL"},
            {"message", "N1CALL", "BLNWX", ""},
            {"message", null, null, "N0CALL"},
            {"message", "N1CALL", "N2CALL", null},
            {"position", "N1CALL", "APRS", "N0CALL"},
            {"weather", "N1CALL", null, "N0CALL"},
            {"object", "N1CALL", "APRS", "N0CALL"},
            {"status", "N1CALL", "APRS", "N0CALL"},
        };
        List<Object> vectors = new ArrayList<>();
        for (String[] c : cases) {
            int type = switch (c[0]) {
                case "message" -> AprsEvent.MESSAGE_TYPE;
                case "position" -> AprsEvent.POSITION_TYPE;
                case "weather" -> AprsEvent.WEATHER_TYPE;
                case "object" -> AprsEvent.OBJECT_TYPE;
                default -> AprsEvent.STATUS_TYPE;
            };
            AprsEvent event = AprsEvent.builder().type(type).fromCallsign(c[1]).toCallsign(c[2]).build();
            vectors.add(Json.obj()
                .put("name", c[0] + " " + c[1] + " > " + c[2] + " for " + c[3])
                .put("input", Json.obj().put("type", type).put("from", c[1]).put("to", c[2]).put("callsign", c[3]))
                .put("expected", Json.obj().put("visible", AprsFeedPolicy.isVisibleToMine(event, c[3]))));
        }
        return vectors;
    }
}
