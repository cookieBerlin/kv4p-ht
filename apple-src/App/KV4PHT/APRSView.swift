import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first, and a line to send messages.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    /// Kept between launches; the app ships without a callsign.
    @AppStorage("aprsCallsign") private var storedCallsign = ""
    @State private var recipient = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            feed
            Divider()
            composer.padding(8)
        }
        .onAppear { model.callsign = storedCallsign }
    }

    private var composer: some View {
        VStack(alignment: .leading) {
            HStack {
                Toggle("Position beacon", isOn: $model.isBeaconEnabled)
                    .disabled(!model.canBeacon || storedCallsign.isEmpty)
                Picker("Symbol", selection: $model.beaconSymbol) {
                    ForEach(APRSSymbol.allCases, id: \.self) { Text($0.name) }
                }
                .frame(width: 200)
                Toggle("Approximate position", isOn: $model.isBeaconApproximate)
                Toggle("Digipeat", isOn: $model.isDigipeatingEnabled)
                    .disabled(storedCallsign.isEmpty)
            }
            HStack {
                Toggle("iGate (report RF packets online)", isOn: $model.isIGateEnabled)
                Toggle("Show nearby APRS-IS packets", isOn: $model.isInternetFeedEnabled)
                if model.isIGateEnabled || model.isInternetFeedEnabled {
                    Label(
                        model.isInternetConnected ? "APRS-IS connected" : "Connecting to APRS-IS…",
                        systemImage: model.isInternetConnected ? "network" : "network.slash"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .disabled(!model.canUseInternet || storedCallsign.isEmpty)
            messageLine
        }
    }

    private var messageLine: some View {
        HStack {
            TextField("Your callsign", text: $storedCallsign)
                .frame(width: 110)
                .onChange(of: storedCallsign) { model.callsign = storedCallsign }
            TextField("To (empty: bulletin)", text: $recipient)
                .frame(width: 140)
            TextField("Message", text: $text)
                .onSubmit(send)
            Button("Send", systemImage: "paperplane", action: send)
                .disabled(!model.isReady || text.isEmpty || storedCallsign.isEmpty)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func send() {
        guard !text.isEmpty else { return }
        model.sendAPRSMessage(to: recipient, text: text)
        text = ""
    }

    private var feed: some View {
        List(model.aprsEvents) { event in
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
