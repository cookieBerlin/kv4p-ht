import Foundation
import KV4PAPRS
import KV4PRadio
import SwiftUI

/// The icon after the text, for a link that leaves the app.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.title
            configuration.icon
        }
    }
}

/// The APRS packets heard on air, newest first, and a line to send messages; the settings are in `SettingsView`.
struct APRSView: View {
    @Bindable var model: RadioViewModel
    @State private var recipient = ""
    @State private var text = ""
    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase

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
            if model.offersDistances {
                Button("Show distances", systemImage: "location") { model.askForDistances() }
            }
            Picker("Show", selection: $model.aprsDestinationFilter) {
                Text("All packets").tag(APRSDestinationFilter.all)
                Text("Only messages for me").tag(APRSDestinationFilter.mine)
            }
            .pickerStyle(.segmented)
            ForEach(model.aprsEvents) { event in
                row(event)
            }
        }
        .onAppear {
            isOnScreen = true
            updateVisibility()
        }
        .onDisappear {
            isOnScreen = false
            updateVisibility()
        }
        .onChange(of: scenePhase) { updateVisibility() }
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

    private func updateVisibility() {
        model.isAPRSVisible = isOnScreen && scenePhase == .active
    }

    private func row(_ event: APRSEvent) -> some View {
        HStack(alignment: .top) {
            icon(event)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Self.title(event)).font(.headline).strikethrough(event.isRemovedObject)
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
                if let text = event.text(units: model.units, locale: .current) {
                    Text(text).font(event.isRawText ? .footnote.monospaced() : .body)
                }
                if let caption = event.caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                if let position = model.position(of: event) {
                    location(position)
                }
            }
        }
        .textSelection(.enabled)
    }

    /// A packet's symbol, or what kind of packet it is. It tells more when looked at closer: a tooltip on the Mac, holding it
    /// on iPhone and iPad, as holding the text of the row selects it.
    private func icon(_ event: APRSEvent) -> some View {
        Group {
            if let symbol = event.symbol {
                APRSSymbolView(symbol: symbol)
            } else {
                Image(systemName: Self.symbol(event.kind)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 24)
        #if os(macOS)
            .help(event.details.joined(separator: "\n"))
        #else
            .contentShape(.rect)
            .contextMenu {
                ForEach(event.details, id: \.self) { Text($0) }
            }
        #endif
        .accessibilityLabel(event.details.joined(separator: ", "))
    }

    /// The coordinates lead to the map; the distance stands below them, as a phone has little room.
    @ViewBuilder private func location(_ position: StationPosition) -> some View {
        let coordinates = String(format: "%.5f, %.5f", position.point.latitude, position.point.longitude)
        if let map = position.mapURL {
            Link(destination: map) {
                Label(coordinates, systemImage: "arrow.up.right").labelStyle(TrailingIcon())
            }
            .font(.caption.monospacedDigit())
            .accessibilityLabel("Open \(coordinates) in Maps")
        }
        if let distance = position.distanceMeters {
            Text(
                [model.units.distance(meters: distance, locale: .current), position.direction?.label]
                    .compactMap(\.self).joined(separator: " ")
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
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
}
