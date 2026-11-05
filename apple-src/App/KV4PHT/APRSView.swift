import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first, and a line to send messages; the settings are in `SettingsView`.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    @State private var recipient = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.isBeaconEnabled, model.canSendOnAir {
                Label(
                    "Position beacon on · accuracy: \(model.beaconAccuracy.label)",
                    systemImage: "location.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            feed
            Divider()
            if model.canSendOnAir {
                composer.padding(8)
            } else if let blocked = model.transmitBlockedText {
                Text(blocked).font(.footnote).foregroundStyle(.secondary).padding(8)
            }
        }
    }

    private var composer: some View {
        HStack {
            recipientField.frame(width: 140).help(ControlHelp.recipient)
            HelpButton(ControlHelp.recipient)
            messageField
            sendButton.labelStyle(.iconOnly)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var recipientField: some View {
        // iOS: a phone has room for the short label only.
        #if os(macOS)
            TextField("To (empty: bulletin)", text: $recipient)
        #else
            TextField("To", text: $recipient)
        #endif
    }

    private var messageField: some View {
        TextField("Message", text: $text)
            .onSubmit(send)
    }

    private var sendButton: some View {
        Button("Send", systemImage: "paperplane", action: send)
            .disabled(!model.isReady || text.isEmpty)
    }

    private func send() {
        guard !text.isEmpty else { return }
        model.sendAPRSMessage(to: recipient, text: text)
        text = ""
    }

    private var feed: some View {
        List {
            Picker("Show", selection: $model.aprsDestinationFilter) {
                Text("All packets").tag(APRSDestinationFilter.all)
                Text("Only messages for me").tag(APRSDestinationFilter.mine)
            }
            .pickerStyle(.segmented)
            ForEach(model.aprsEvents) { event in
                row(event)
            }
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
    }

    private func row(_ event: APRSEvent) -> some View {
        HStack(alignment: .top) {
            Image(systemName: Self.symbol(event.kind))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.title(event)).font(.headline)
                    Spacer()
                    if let state = Self.delivery(event.deliveryState) {
                        Label(state.0, systemImage: state.1).labelStyle(.iconOnly).help(state.0)
                    }
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

    private static func delivery(_ state: APRSEvent.DeliveryState) -> (String, String)? {
        switch state {
        case .none: nil
        case .pending: ("Waiting for acknowledgement", "clock")
        case .delivered: ("Delivered", "checkmark.circle")
        case .rejected: ("Rejected", "xmark.circle")
        case .failed: ("Not delivered", "exclamationmark.triangle")
        }
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
        let from = event.fromCallsign
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
