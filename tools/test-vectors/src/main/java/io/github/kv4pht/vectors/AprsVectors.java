package io.github.kv4pht.vectors;

import io.github.dkaukov.aprs.AprsController;
import io.github.dkaukov.aprs.AprsEvent;
import io.github.dkaukov.aprs.AprsPacket;
import io.github.dkaukov.aprs.AprsRepository;
import io.github.dkaukov.aprs.AprsSource;
import io.github.dkaukov.aprs.BeaconData;
import io.github.dkaukov.aprs.parser.APRSPacket;
import io.github.dkaukov.aprs.parser.APRSTypes;
import io.github.dkaukov.aprs.parser.Digipeater;
import io.github.dkaukov.aprs.parser.InformationField;
import io.github.dkaukov.aprs.parser.MessagePacket;
import io.github.dkaukov.aprs.parser.ObjectField;
import io.github.dkaukov.aprs.parser.Parser;
import io.github.dkaukov.aprs.parser.PositionField;
import io.github.dkaukov.aprs.parser.StationCapabilitiesField;
import io.github.dkaukov.aprs.parser.StatusField;
import io.github.dkaukov.aprs.parser.ThirdPartyField;
import io.github.dkaukov.aprs.parser.WeatherField;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

/**
 * Vectors for the APRS receive path of the Android app: {@code Parser.parseAX25} as in
 * {@code RadioAudioService.handleAx25Packet}, and the events {@code AprsController.handle} derives from it.
 * All callsigns are placeholders; positions are the examples of the APRS specification.
 */
final class AprsVectors {
    private AprsVectors() {}

    /** TNC2 lines; each is encoded with {@code APRSPacket.toAX25Frame} and parsed back as received over RF. */
    private static final String[] PACKETS = {
        "N0CALL>APRS,WIDE1-1,WIDE2-1:!4903.50N/07201.75W-Test 001234",
        "N0CALL-9>APRS:=4903.50N/07201.75W>mobile",
        "N0CALL>APRS:@092345z4903.50N/07201.75W>with time",
        "N0CALL>APRS:/092345z4903.50N/07201.75W>no messaging",
        "N0CALL>APRS:!4903.50S\\07201.75E#digi",
        "N0CALL>APRS:!4903.  N/07201.  W-two digits",
        "N0CALL>APRS:!49  .  N/072  .  W-degrees only",
        "N0CALL>APRS:!4903.5 N/07201.7 W-one digit",
        "N0CALL>APRS:!4903.50N/07201.75W>088/036course",
        "N0CALL>APRS:!4903.50N/07201.75W>xxx/036bad course",
        "N0CALL>APRS:!4903.50N/07201.75W#PHG5132phg",
        "N0CALL>APRS:!4903.50N/07201.75W#PHG51x2bad phg",
        "N0CALL>APRS:!4903.50N",
        "N0CALL>APRS:!4903.50X/07201.75W-bad sign",
        "N0CALL>APRS:!4903.50N/07201.75X-bad sign",
        "N0CALL>APRS:!4963.50N/07201.75W-bad minutes",
        "N0CALL>APRS:!9103.50N/07201.75W-too far north",
        "N0CALL>APRS:!4903,50N/07201.75W-no dot",
        "N0CALL>APRS:!4903.50N/07201.75W",
        "N0CALL>APRS:!4903.50N/07201.75W_220/004g005t077r001p002P003h50b09900wRSW",
        "N0CALL>APRS:@092345z4903.50N/07201.75W_090/000g000t-05r000p000P000h00b10218s002L123",
        "N0CALL>APRS:!4903.50N/07201.75W_short",
        "N0CALL>APRS:!/5L!!<*e7>7P[",
        "N0CALL>APRS:=/5L!!<*e7OS]S compressed comment",
        "N0CALL>APRS:=/5L!!<*e7{?!range",
        "N0CALL>APRS:=/5L!!<*e7 sTspace",
        "N0CALL>APRS:=/5L!!<*e7>S!Galtitude",
        "N0CALL>APRS:=/5L!!<*e7_ !!weather",
        "N0CALL>APRS:=/5L!!",
        "N0CALL>APRS:=/5L!\u007f<*e7>7P[",
        "N0CALL>APRS:=a5L!!<*e7>7P[overlay",
        "N0CALL>T2SP0W:`(_fn\"Oj/Mic-E",
        "N0CALL>T2SP0W-2:`(_fn\"Oj/]=",
        "N0CALL>S32U6T:`(_f n\"Oj/>\"4T}altitude",
        "N0CALL>TQSPKZ:'(_fn\"Oj/ambiguous",
        "N0CALL>T2SPLW:`(_fn\"Oj/",
        "N0CALL>T2SPL:`(_fn\"Oj/",
        "N0CALL>T2MP0W:`(_fn\"Oj/",
        "N0CALL>T2SPMW:`(_fn\"Oj/",
        "N0CALL>K2SP0W:`(_fn\"Oj/",
        "N0CALL>T2SP0W:`\u0010_fn\"Oj/",
        "N0CALL>T2SP0W:`(\u007ffn\"Oj/",
        "N0CALL>T2SP0W:`(_\u0010n\"Oj/",
        "N0CALL>T2SP0W:`(_f\u0010\"Oj/",
        "N0CALL>T2SP0W:`(_fn\u0010Oj/",
        "N0CALL>T2SP0W:`(_fn\"\u0010j/",
        "N0CALL>T2SP0W:`(_fn\"O~/",
        "N0CALL>T2SP0W:`(_fn\"Oj!",
        "N0CALL>T2SP0W:`(_",
        "N0CALL>APRS:$GPRMC,063909,A,3349.4302,N,11700.3721,W,43.022,89.3,291099,13.1,E*5D",
        "N0CALL>APRS:$GPRMC,063909,V,3349.4302,N,11700.3721,W,43.022,89.3,291099,13.1,E*5D",
        "N0CALL>APRS:$GPGGA,175059,3347.4969,N,11805.7319,W,1,12,1.0,6.8,M,-32.1,M,,*7D",
        "N0CALL>APRS:$GPGGA,175059,3347.4969,N,11805.7319,W,2,12,1.0,6.8,M,-32.1,M,,*7D",
        "N0CALL>APRS:$GPGLL,4916.45,N,12311.12,W,225444,A,A*5C",
        "N0CALL>APRS:$GPWPL,4610.586,S,00607.754,E,4*70",
        "N0CALL>APRS:$GPVTG,054.7,T,034.4,M*48",
        "N0CALL>APRS:$GPXYZ,1,2,3,4,5",
        "N0CALL>APRS:$GP",
        "N0CALL>APRS:$ULTW0000",
        "N0CALL>APRS:!ULT00000000",
        "N0CALL>APRS::N1CALL   :hello{001",
        "N0CALL>APRS::N1CALL-7 :ack001",
        "N0CALL>APRS::N1CALL   :REJ002",
        "N0CALL>APRS::n1call   :no number",
        "N0CALL>APRS::N1CALL:unpadded",
        "N0CALL>APRS::N1CALL   :{only number",
        "N0CALL>APRS::",
        "N0CALL>APRS::N1CALLnocolon",
        "N0CALL>APRS:>status text  ",
        "N0CALL>APRS:>092345zstatus with time",
        "N0CALL>APRS:>09a345zno time",
        "N0CALL>APRS:>",
        "N0CALL>APRS:;LEADER   *092345z4903.50N/07201.75W>088/036object",
        "N0CALL>APRS:;DEAD     _092345z4903.50N/07201.75W>",
        "N0CALL>APRS:;SHORT    *092345z",
        "N0CALL>APRS:;BADPOS   *092345z4903.50N/07201.75Q>x",
        "N0CALL>APRS:)AID #2!4903.50N/07201.75WA",
        "N0CALL>APRS:<IGATE,MSG_CNT=10,LOC_CNT=1",
        "N0CALL>APRS:<igate,MSG_CNT=1,LOC_CNT=3,MSG_CNT=x,LOC_CNT=-1,,FOO",
        "N0CALL>APRS:<",
        "N0CALL>APRS:_10090556c220s004g005t077r000p000P000h50b09900wRSW",
        "N0CALL>APRS:#weather t050",
        "N0CALL>APRS:}N2CALL>APRS,TCPIP,N0CALL*:>inner status",
        "N0CALL>APRS:}N2CALL>APRS:!4903.50N/07201.75W-inner position",
        "N0CALL>APRS:}N2CALL>APRS:Ainvalid inner",
        "N0CALL>APRS:}garbage",
        "N0CALL>APRS:?APRS?",
        "N0CALL>APRS:T#005,199,000,255,073,123,01101001",
        "N0CALL>APRS:T#1",
        "N0CALL>APRS:Ainvalid DTI",
        "N0CALL>APRS:5invalid DTI",
        "N0CALL>APRS:{user defined",
        "N0CALL>APRS:xunknown",
        "N0CALL>APRS:!4903.50N/07201.75W-Grüße",
        "N0CALL>APRS:!4903.50N/07201.75W-GrÃ¼Ã\u009fe",
        "N0CALL>APRS:_wx ÿ t012",
        "N0CALL>APRS,N1CALL*,WIDE2-1:>used path",
        "N0CALL>APRS:@0923",
        "N0CALL>APRS:@0923456",
        "N0CALL>APRS:/092345674903.50N/07201.75W>digit time",
        "N0CALL>APRS:@092345z4903",
        "N0CALL>APRS:!x903.50N/07201.75W-who knows",
        "N0CALL>APRS:!",
        "N0CALL>APRS:!UL",
        "N0CALL>APRS:=/5L!!<*e7>",
        "N0CALL>T2SP0W:`(_fn\"Oj/>\"4T}altitude",
        "N0CALL>T2SP0W:`(_fn\"Oj/x]comment",
        "N0CALL>T2SPLZ:`(_fn\"Oj/amb3",
        "N0CALL>T2SLLZ:`(_fn\"Oj/amb2",
        "N0CALL>T2LLLZ:`(_fn\"Oj/amb1",
        "N0CALL>T2SP0Z:`(_fn\"Oj/amb4",
        "N0CALL>TZSP0W:`(_fn\"Oj/bad ambiguity",
        "N0CALL>T2SPPW:`l_fn\"Oj/east 100",
        "N0CALL>T2SPPW:`v_fn\"Oj/zero",
        "N0CALL>T2SP0W:`(afn\"Oj/minutes",
        "N0CALL>APRS:$GPGLL,4916.45,N,12311.12,W,225444,V,A*5C",
        "N0CALL>APRS:$GPGLL,4916.45,N,12311.12,W,225444,A,,",
        "N0CALL>APRS:$PNTS,1,0,11,01,2002,231932,3539.687,N,13944.480,E,0,000,5,Name,000,1*35",
        "N0CALL>APRS:$GPWPL,9000.300,N,00607.754,E,4",
        "N0CALL>APRS:$GPWPL,4610.586,N,18000.600,E,4",
        "N0CALL>APRS:$GPWPL,9510.586,N,00607.754,E,4",
        "N0CALL>APRS:$GPWPL,4610.586,N,18100.000,E,4",
        "N0CALL>APRS:$GPWPL,4610.586,X,00607.754,E,4",
        "N0CALL>APRS:$GPWPL,4610.586,N,00607.754,X,4",
        "N0CALL>APRS:$GPWPL,4,N,00607.754,E,4",
        "N0CALL>APRS:$GPWPL,4a10.586,N,00607.754,E,4",
        "N0CALL>APRS:$GPWPL,46x0.586,N,00607.754,E,4",
        "N0CALL>APRS:$GPGGA,1,2,3",
        "N0CALL>APRS:_wx l123 L045",
        "N0CALL>APRS:<MSG_CNT=1,LOC_CNT=3",
        "N0CALL>APRS:}N2CALL>,:>no destination",
        "N0CALL>APRS:}N2CALL>APRS,-:>bad path",
        "N0CALL>APRS:}N2CALL>APRS,-X,*:>odd path",
        "N0CALL-5>APRS:}N2CALL>APRS:>relay with SSID",
        "N0CALL>APRS:@092345",
        "N0CALL>TBSP0W:`(_fn\"Oj/A to J",
    };

    /** AX.25 frames the RF parser refuses or reads specially. */
    private static final String[] FRAMES = {
        "82a0a4a640406060",  // too short
        "82a0a4a64040609c60868298986103f1",  // wrong PID, 16 bytes
        "82a0a4a64040609c608682989860ae92888a62406303f03e",  // path without its end bit set first? no: one digi
        "82a0a4a64040609c60868298986003f0",  // path address missing
        "82a0a4a64040609c608682989861",  // control and PID missing
        "82a0a4a64040609c60868298986103f0",  // no information field
        "82a0a4a64040e19c60868298986103f03e",  // destination with bits set
        "82a0a4a64040609c6086829898fd03f03e",  // source SSID 14 with C bit
    };

    static List<Object> parser() throws Exception {
        List<Object> vectors = new ArrayList<>();
        for (String tnc2 : PACKETS) {
            vectors.add(parse(tnc2, frame(tnc2)));
        }
        for (String hex : FRAMES) {
            vectors.add(parse(hex, bytes(hex)));
        }
        return vectors;
    }

    private static Json.Obj parse(String name, byte[] frame) {
        Json.Obj expected;
        try {
            expected = packet(Parser.parseAX25(frame, 0, frame.length));
        } catch (Exception e) {
            expected = Json.obj().put("error", true);
        }
        return Json.obj().put("name", name)
            .put("input", Json.obj().put("frame", Json.hex(frame)))
            .put("expected", expected);
    }

    private static Json.Obj packet(APRSPacket packet) {
        InformationField info = packet.getPayload();
        List<Object> digipeaters = new ArrayList<>();
        for (Digipeater digipeater : packet.getDigipeaters()) {
            digipeaters.add(digipeater.toString());
        }
        List<Object> types = new ArrayList<>();
        for (APRSTypes type : APRSTypes.values()) {
            if (info.containsType(type)) {
                types.add(type.name());
            }
        }
        Json.Obj result = Json.obj()
            .put("source", packet.getSourceCall())
            .put("destination", packet.getDestinationCall())
            .put("digipeaters", digipeaters)
            .put("dti", String.valueOf(packet.getDti()))
            .put("hasFault", packet.hasFault())
            .put("comment", packet.getComment())
            .put("infoComment", info.getComment())
            .put("types", types);
        if (info instanceof MessagePacket message) {
            result.put("message", Json.obj().put("target", message.getTargetCallsign())
                .put("body", message.getMessageBody()).put("number", message.getMessageNumber())
                .put("ack", message.isAck()).put("rej", message.isRej()).put("hasFault", message.hasFault()));
        }
        PositionField position = (PositionField) info.getAprsData(APRSTypes.T_POSITION);
        if (position != null) {
            result.put("position", position(position));
        }
        WeatherField weather = (WeatherField) info.getAprsData(APRSTypes.T_WX);
        if (weather != null) {
            result.put("weather", Json.obj().put("windDirection", weather.getWindDirection())
                .put("windSpeed", weather.getWindSpeed()).put("windGust", weather.getWindGust())
                .put("temp", weather.getTemp()).put("rainLastHour", weather.getRainLastHour())
                .put("rainLast24Hours", weather.getRainLast24Hours())
                .put("rainSinceMidnight", weather.getRainSinceMidnight())
                .put("humidity", weather.getHumidity()).put("pressure", weather.getPressure())
                .put("luminosity", weather.getLuminosity())
                .put("snowfallLast24Hours", weather.getSnowfallLast24Hours())
                .put("comment", weather.getComment()));
        }
        ObjectField object = (ObjectField) info.getAprsData(APRSTypes.T_OBJECT);
        if (object != null) {
            result.put("object", Json.obj().put("name", object.getObjectName()).put("live", object.isLive())
                .put("comment", object.getComment()).put("position", position(object.getPosition())));
        }
        StatusField status = (StatusField) info.getAprsData(APRSTypes.T_STATUS);
        if (status != null) {
            result.put("status", status.getStatusText());
        }
        StationCapabilitiesField capabilities =
            (StationCapabilitiesField) info.getAprsData(APRSTypes.T_STATCAPA);
        if (capabilities != null) {
            result.put("capabilities", Json.obj().put("displayText", capabilities.getDisplayText())
                .put("igate", capabilities.isIgate()).put("messageCount", capabilities.getMessageCount())
                .put("localStationCount", capabilities.getLocalStationCount()));
        }
        ThirdPartyField thirdParty = (ThirdPartyField) info.getAprsData(APRSTypes.T_THIRDPARTY);
        if (thirdParty != null) {
            result.put("thirdParty", packet(thirdParty.getInnerPacket()));
        }
        return result;
    }

    private static Json.Obj position(PositionField field) {
        return Json.obj()
            .put("latitude", field.getPosition().getLatitude())
            .put("longitude", field.getPosition().getLongitude())
            .put("ambiguity", field.getPosition().getPositionAmbiguity())
            .put("symbolTable", String.valueOf(field.getPosition().getSymbolTable()))
            .put("symbolCode", String.valueOf(field.getPosition().getSymbolCode()))
            .put("source", field.getPositionSource())
            .put("comment", field.getComment())
            .put("hasFault", field.hasFault());
    }

    // MARK: Events

    /** Steps of one receiver: milliseconds since the start and a TNC2 line received over RF. */
    private static final Object[][][] SESSIONS = {
        {
            {0L, "N0CALL>APRS,WIDE2-1:!4903.50N/07201.75W-position"},
            {10_000L, "N0CALL>APRS,N1CALL*,WIDE2*:!4903.50N/07201.75W-position"},
            {41_000L, "N0CALL>APRS:!4903.50N/07201.75W-position"},
            {41_500L, "N0CALL>APRS:!4903.51N/07201.75W-moved"},
        },
        {
            {0L, "N0CALL>APRS::N1CALL   :hello{001"},
            {600_000L, "N0CALL>APRS::N1CALL   :hello{001"},
            {2_000_000L, "N0CALL>APRS::N1CALL   :hello{001"},
            {2_000_100L, "N0CALL>APRS::N1CALL   :no number"},
            {2_040_000L, "N0CALL>APRS::N1CALL   :no number"},
            {2_041_000L, "N1CALL>APRS::N0CALL   :ack001"},
            {2_042_000L, "N1CALL>APRS::N0CALL   :rej001"},
        },
        {
            {0L, "N0CALL>APRS:_10090556c220s004g005t077r000p000P000h50b09900wRSW"},
            {1L, "N0CALL>APRS:!4903.50N/07201.75W_220/004g005t-05r001p002P003h00b09900s004"},
            {2L, "N0CALL>APRS:>status text"},
            {3L, "N0CALL>APRS:;LEADER   *092345z4903.50N/07201.75W>object"},
            {4L, "N0CALL>APRS:<IGATE,MSG_CNT=10,LOC_CNT=1"},
            {5L, "N0CALL>APRS:?APRS?"},
            {6L, "N0CALL>APRS:Ainvalid"},
            {7L, "N0CALL>APRS:}N2CALL>APRS,TCPIP,N0CALL*:>relayed status"},
            {8L, "N0CALL>APRS:}N2CALL>APRS:Ainvalid inner"},
            {9L, "N0CALL>APRS:=4903.50N/07201.75W>  "},
            {10L, "N0CALL>T2SP0W:`(_fn\"Oj/Mic-E"},
            {11L, "N0CALL>APRS:=/5L!!<*e7>7P[compressed"},
            {12L, "N0CALL>APRS:!4903.50N"},
            {13L, "N0CALL>APRS:#weather t050"},
            {14L, "N0CALL>APRS:_wx l123"},
        },
    };

    static List<Object> events() throws Exception {
        List<Object> vectors = new ArrayList<>();
        int index = 0;
        for (Object[][] session : SESSIONS) {
            MutableClock clock = new MutableClock();
            MemoryRepository repository = new MemoryRepository();
            AprsController controller = new AprsController(repository, new NoCallbacks(), clock);
            List<Object> steps = new ArrayList<>();
            for (Object[] step : session) {
                clock.millis = (Long) step[0];
                byte[] frame = frame((String) step[1]);
                controller.handle(Parser.parseAX25(frame, 0, frame.length), AprsSource.RX_RF, 144_390_000L, frame);
                steps.add(Json.obj().put("timeMs", step[0]).put("frame", Json.hex(frame)));
            }
            List<Object> events = new ArrayList<>();
            for (AprsEvent event : repository.events) {
                events.add(event(event));
            }
            vectors.add(Json.obj().put("name", "session " + ++index)
                .put("input", Json.obj().put("steps", steps))
                .put("expected", Json.obj().put("events", events).put("packets", repository.packets.size())));
        }
        return vectors;
    }

    private static Json.Obj event(AprsEvent event) {
        return Json.obj().put("id", event.getId()).put("type", event.getType())
            .put("firstSeenMs", event.getFirstSeenMs()).put("lastSeenMs", event.getLastSeenMs())
            .put("packetCount", event.getPacketCount()).put("dedupKey", event.getDedupKey())
            .put("fromCallsign", event.getFromCallsign()).put("toCallsign", event.getToCallsign())
            .put("messageIdentifier", event.getMessageIdentifier()).put("body", event.getBody())
            .put("positionLat", event.getPositionLat()).put("positionLong", event.getPositionLong())
            .put("comment", event.getComment()).put("objectName", event.getObjectName())
            .put("temperature", event.getTemperature()).put("humidity", event.getHumidity())
            .put("pressure", event.getPressure()).put("rain", event.getRain()).put("snow", event.getSnow())
            .put("windForce", event.getWindForce()).put("windDirection", event.getWindDirection())
            .put("relayCallsign", event.getRelayCallsign()).put("internetOnly", event.isInternetOnly())
            .put("deliveryState", event.getDeliveryState());
    }

    /** Encodes a TNC2 line without parsing its information field, so unparsable packets get a frame too. */
    private static byte[] frame(String tnc2) {
        int arrow = tnc2.indexOf('>');
        int colon = tnc2.indexOf(':');
        String path = tnc2.substring(arrow + 1, colon);
        return new APRSPacket(tnc2.substring(0, arrow), path.split(",")[0], Digipeater.parseList(path, false),
            tnc2.substring(colon + 1).getBytes(StandardCharsets.ISO_8859_1)).toAX25Frame();
    }

    private static byte[] bytes(String hex) {
        byte[] out = new byte[hex.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
        }
        return out;
    }

    private static final class MutableClock extends Clock {
        long millis;

        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return Instant.ofEpochMilli(millis); }
        @Override public long millis() { return millis; }
    }

    /** The Room repository of the app, reduced to the queries the receive path uses. */
    private static final class MemoryRepository implements AprsRepository {
        final List<AprsEvent> events = new ArrayList<>();
        final List<AprsPacket> packets = new ArrayList<>();

        @Override public long insert(AprsPacket packet) {
            packets.add(packet);
            return packets.size();
        }

        @Override public long insert(AprsEvent event) {
            long id = events.size() + 1;
            events.add(event.toBuilder().id(id).build());
            return id;
        }

        @Override public void update(AprsEvent event) {
            events.set((int) event.getId() - 1, event);
        }

        @Override public List<AprsEvent> loadPendingReliableEvents() { return new ArrayList<>(); }

        @Override public AprsEvent findById(long id) { return events.get((int) id - 1); }

        /** {@code AprsEventDao.getRecentByDedupKey}. */
        @Override public AprsEvent findRecentByDedupKey(String dedupKey, long sinceMs) {
            AprsEvent found = null;
            for (AprsEvent event : events) {
                if (event.getDedupKey().equals(dedupKey) && event.getLastSeenMs() >= sinceMs
                    && (found == null || event.getLastSeenMs() > found.getLastSeenMs())) {
                    found = event;
                }
            }
            return found;
        }

        @Override public AprsEvent findPendingOutgoingEvent(String local, String remote, String identifier) {
            return null;  // the receive path has no outgoing messages
        }

        @Override public AprsPacket findInitialRfTransmission(long eventId) { return null; }
    }

    /** No callsign is configured, so nothing is transmitted or gated. */
    private static final class NoCallbacks implements AprsController.Callbacks {
        @Override public void onIncomingMessage(AprsEvent event, boolean forLocal) {}
        @Override public AprsController.RfTransmission submitRf(APRSPacket packet, Long frequencyHz,
                AprsController.RfTransmissionPurpose purpose) { return null; }
        @Override public BeaconData getBeaconData() { return null; }
        @Override public boolean submitAprsIs(String line, Runnable onSent) { return false; }
    }
}
