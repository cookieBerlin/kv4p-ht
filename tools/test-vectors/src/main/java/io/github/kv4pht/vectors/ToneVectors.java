package io.github.kv4pht.vectors;

import com.vagell.kv4pht.ui.ToneAccess;
import com.vagell.kv4pht.ui.ToneHelper;
import java.util.ArrayList;
import java.util.List;

/** Vectors for {@link ToneHelper}: the SA818 CTCSS table and how entered tones are normalised. */
final class ToneVectors {
    private ToneVectors() {}

    static List<Object> all() {
        List<Object> v = new ArrayList<>();
        List<Object> table = new ArrayList<>();
        for (String tone : ToneAccess.tones()) {
            table.add(Json.obj().put("label", tone).put("index", ToneHelper.getToneIndex(tone)));
        }
        v.add(Json.obj().put("name", "tone table").put("input", Json.obj().put("type", "table"))
                .put("expected", Json.obj().put("tones", table)));
        String[] inputs = {
            "", "   ", "None", "67", " 67 ", "67.0", "100", "100.0", "71.5", "71.95", "72.9", "73.0", "0", "1",
            "1.5", "65.9", "66.0", "250.3", "251.3", "251.4", "300", "88.4", "abc", "-67",
        };
        for (String input : inputs) {
            v.add(Json.obj().put("name", "normalize \"" + input + "\"")
                    .put("input", Json.obj().put("type", "normalize").put("tone", input))
                    .put("expected", Json.obj().put("normalized", ToneHelper.normalizeTone(input))
                            .put("index", ToneHelper.getToneIndex(input))));
        }
        return v;
    }
}
