import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first.
struct APRSView: View {
    let model: RadioViewModel

    var body: some View {
        List(model.aprsEvents) { event in
            HStack(alignment: .top) {
                Image(systemName: Self.symbol(event.kind))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(Self.title(event)).font(.headline)
                        Spacer()
                        if event.packetCount > 1 {
                            Text("×\(event.packetCount)").foregroundStyle(.secondary)
                        }
                        Text(Date(timeIntervalSince1970: Double(event.lastSeenMs) / 1000), style: .time)
                            .foregroundStyle(.secondary)
                    }
                    if let text = Self.text(event), !text.isEmpty {
                        Text(text)
                    }
                    if event.kind == .position || event.kind == .weather, event.latitude != 0 || event.longitude != 0 {
                        Text(String(format: "%.5f, %.5f", event.latitude, event.longitude))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .textSelection(.enabled)
        }
        .overlay {
            if model.aprsEvents.isEmpty {
                ContentUnavailableView(
                    "No APRS packets yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Tune to the APRS frequency of your region, e.g. 144.800 or 144.390 MHz.")
                )
            }
        }
        .navigationTitle("APRS")
    }

    private static func symbol(_ kind: APRSEvent.Kind) -> String {
        switch kind {
        case .message: "envelope"
        case .object: "flag"
        case .position: "mappin.and.ellipse"
        case .weather: "cloud.sun"
        case .status: "text.bubble"
        case .stationCapabilities: "antenna.radiowaves.left.and.right"
        case .unknown: "questionmark.circle"
        }
    }

    private static func title(_ event: APRSEvent) -> String {
        let from = event.fromCallsign ?? "?"
        switch event.kind {
        case .message: return "\(from) → \(event.toCallsign ?? "?")"
        case .object: return "\(event.objectName ?? "?") (\(from))"
        default: return event.relayCallsign.map { "\(from) via \($0)" } ?? from
        }
    }

    private static func text(_ event: APRSEvent) -> String? {
        switch event.kind {
        case .message: event.body
        case .weather:
            [
                String(format: "%.0f °F", event.temperature),
                String(format: "%.0f %%", event.humidity),
                event.pressure > 0 ? String(format: "%.1f hPa", event.pressure) : "",
                event.windDirection.map { "wind \($0) \(event.windForce) mph" } ?? "",
            ].filter { !$0.isEmpty }.joined(separator: " · ")
        default: event.comment
        }
    }
}
