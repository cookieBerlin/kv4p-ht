package io.github.kv4pht.vectors;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Minimal deterministic JSON writer, so the generator needs no dependency.
 * Objects keep insertion order; arrays of scalars stay on one line.
 */
final class Json {
    private Json() {}

    /** Ordered JSON object builder. */
    static final class Obj {
        final Map<String, Object> fields = new LinkedHashMap<>();

        Obj put(String key, Object value) {
            fields.put(key, value);
            return this;
        }
    }

    static Obj obj() {
        return new Obj();
    }

    static List<Object> list(Object... values) {
        return new ArrayList<>(Arrays.asList(values));
    }

    static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b & 0xFF));
        }
        return sb.toString();
    }

    static List<Object> ints(short[] values) {
        List<Object> list = new ArrayList<>(values.length);
        for (short v : values) {
            list.add((int) v);
        }
        return list;
    }

    static String write(Object value) {
        StringBuilder sb = new StringBuilder();
        write(sb, value, 0);
        return sb.append('\n').toString();
    }

    private static void write(StringBuilder sb, Object value, int indent) {
        if (value instanceof Obj obj) {
            writeObject(sb, obj.fields, indent);
        } else if (value instanceof List<?> list) {
            writeList(sb, list, indent);
        } else {
            writeScalar(sb, value);
        }
    }

    private static void writeObject(StringBuilder sb, Map<String, Object> fields, int indent) {
        if (fields.isEmpty()) {
            sb.append("{}");
            return;
        }
        sb.append("{\n");
        int i = 0;
        for (Map.Entry<String, Object> e : fields.entrySet()) {
            pad(sb, indent + 1);
            writeString(sb, e.getKey());
            sb.append(": ");
            write(sb, e.getValue(), indent + 1);
            sb.append(++i < fields.size() ? ",\n" : "\n");
        }
        pad(sb, indent);
        sb.append('}');
    }

    private static void writeList(StringBuilder sb, List<?> list, int indent) {
        boolean scalars = list.stream().noneMatch(v -> v instanceof Obj || v instanceof List);
        if (scalars) {
            sb.append('[');
            for (int i = 0; i < list.size(); i++) {
                if (i > 0) {
                    sb.append(", ");
                }
                writeScalar(sb, list.get(i));
            }
            sb.append(']');
            return;
        }
        sb.append("[\n");
        for (int i = 0; i < list.size(); i++) {
            pad(sb, indent + 1);
            write(sb, list.get(i), indent + 1);
            sb.append(i + 1 < list.size() ? ",\n" : "\n");
        }
        pad(sb, indent);
        sb.append(']');
    }

    private static void writeScalar(StringBuilder sb, Object value) {
        if (value == null) {
            sb.append("null");
        } else if (value instanceof String s) {
            writeString(sb, s);
        } else if (value instanceof Float f) {
            if (f.isNaN() || f.isInfinite()) {
                throw new IllegalArgumentException("JSON cannot represent " + f);
            }
            sb.append(Float.toString(f));
        } else if (value instanceof Number || value instanceof Boolean) {
            sb.append(value);
        } else {
            throw new IllegalArgumentException("Unsupported JSON value: " + value.getClass());
        }
    }

    private static void writeString(StringBuilder sb, String s) {
        sb.append('"');
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                default -> {
                    if (c < 0x20 || c > 0x7E) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
    }

    private static void pad(StringBuilder sb, int indent) {
        sb.append("  ".repeat(indent));
    }
}
