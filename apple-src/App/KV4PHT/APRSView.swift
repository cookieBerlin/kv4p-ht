import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The APRS packets heard on air, newest first, and a line to send messages.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    /// The callsign as typed; the model keeps it normalised in the settings.
    @State private var callsign = ""
    @State private var recipient = ""
    @State private var text = ""
    #if os(iOS)
        @State private var isShowingSettings = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            feed
            Divider()
            composer.padding(8)
        }
        .onAppear { callsign = model.callsign }
        #if os(iOS)
            .toolbar {
                Button("APRS settings", systemImage: "gearshape") { isShowingSettings = true }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    settings
                    .navigationTitle("APRS settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { isShowingSettings = false } }
                }
            }
        #endif
    }

    #if os(macOS)
        private var composer: some View {
            VStack(alignment: .leading) {
                HStack {
                    beaconToggle
                    symbolPicker.frame(width: 200)
                    approximateToggle
                    frequencyPicker.frame(width: 220)
                    digipeatToggle
                }
                HStack {
                    iGateToggle
                    feedToggle
                    internetStatus
                }
                HStack {
                    callsignField.frame(width: 110)
                    recipientField.frame(width: 140)
                    messageField
                    sendButton
                }
                .textFieldStyle(.roundedBorder)
            }
        }
    #else
        /// iOS: the settings move into a sheet, so the message line fits a phone.
        private var composer: some View {
            HStack {
                recipientField.frame(width: 110)
                messageField
                sendButton.labelStyle(.iconOnly)
            }
            .textFieldStyle(.roundedBorder)
        }

        private var settings: some View {
            Form {
                Section("Station") {
                    callsignField
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("Position beacon") {
                    beaconToggle
                    symbolPicker
                    approximateToggle
                    frequencyPicker
                }
                Section {
                    digipeatToggle
                    iGateToggle
                    feedToggle
                    internetStatus
                }
            }
        }
    #endif

    private var beaconToggle: some View {
        Toggle("Position beacon", isOn: $model.isBeaconEnabled)
            .disabled(!model.canBeacon || model.callsign.isEmpty)
    }

    private var symbolPicker: some View {
        Picker("Symbol", selection: $model.beaconSymbol) {
            ForEach(APRSSymbol.allCases, id: \.self) { Text($0.name) }
        }
    }

    private var approximateToggle: some View {
        Toggle("Approximate position", isOn: $model.isBeaconApproximate)
    }

    private var frequencyPicker: some View {
        Picker("on", selection: $model.beaconFrequency) {
            Text("Current frequency").tag(Float?.none)
            ForEach(AppSettings.beaconFrequencyOptions, id: \.self) { frequency in
                Text(HamFrequency.format(frequency) + " MHz").tag(Float?.some(frequency))
            }
        }
    }

    private var digipeatToggle: some View {
        Toggle("Digipeat", isOn: $model.isDigipeatingEnabled)
            .disabled(model.callsign.isEmpty)
    }

    private var iGateToggle: some View {
        Toggle("iGate (report RF packets online)", isOn: $model.isIGateEnabled)
            .disabled(!model.canUseInternet || model.callsign.isEmpty)
    }

    private var feedToggle: some View {
        Toggle("Show nearby APRS-IS packets", isOn: $model.isInternetFeedEnabled)
            .disabled(!model.canUseInternet || model.callsign.isEmpty)
    }

    @ViewBuilder private var internetStatus: some View {
        if model.isIGateEnabled || model.isInternetFeedEnabled {
            Label(
                model.isInternetConnected ? "APRS-IS connected" : "Connecting to APRS-IS…",
                systemImage: model.isInternetConnected ? "network" : "network.slash"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var callsignField: some View {
        TextField("Your callsign", text: $callsign)
            .onChange(of: callsign) { model.callsign = callsign }
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
            .disabled(!model.isReady || text.isEmpty || model.callsign.isEmpty)
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
        .navigationTitle("APRS")
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
