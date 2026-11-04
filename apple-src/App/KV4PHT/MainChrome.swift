import KV4PAudio
import KV4PRadio
import SwiftUI

extension View {
    /// With room for it, the parts around the memories and APRS: the header, the PTT bar and the settings button.
    func mainChrome(_ model: RadioViewModel, title: String) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                RadioHeader(model: model)
                Divider()
            }
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBar(model: model, showsPTT: true)
        }
        .navigationTitle(title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(macOS)
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            #else
                NavigationLink {
                    SettingsView(model: model)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            #endif
        }
    }
}

/// The connection, the frequency and the S-meter, as at the top of the Android app.
struct RadioHeader: View {
    @Bindable var model: RadioViewModel
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            connection
            if let name = model.activeMemoryName {
                Text(name).font(.headline).lineLimit(1)
            }
            frequency
            HStack {
                SMeterBars(value: model.sMeter, squelch: model.isReady ? model.squelch : nil)
                Text(model.sMeterText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 58, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("S-meter")
            .accessibilityValue(model.isReady ? "\(model.sMeterText), squelch \(model.squelch)" : model.sMeterText)
            .help(ControlHelp.meter)
            if !isCompact {
                VolumeSlider(model: model)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// A phone has no room for a labelled picker, so the chosen radio opens the list.
    private var connection: some View {
        HStack {
            if isCompact {
                if model.canConnect, !model.firmwareUpdate.isRunning {
                    Menu {
                        radioPicker
                    } label: {
                        Label(model.selectedConnection.label, systemImage: "chevron.up.chevron.down")
                    }
                } else {
                    Text(model.selectedConnection.label).foregroundStyle(.secondary)
                }
            } else {
                radioPicker.fixedSize()
            }
            Spacer()
            if model.canConnect {
                Button("Connect") { Task { await model.connect() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStartConnection)
            } else {
                Button("Disconnect") { Task { await model.disconnect() } }
            }
        }
    }

    private var radioPicker: some View {
        Picker("Radio", selection: $model.selectedConnection) {
            ForEach(model.connections) { Text($0.label).tag($0) }
        }
        .disabled(!model.canConnect || model.firmwareUpdate.isRunning)
    }

    private var frequency: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("Frequency", text: $model.frequencyText)
                .onSubmit { Task { await model.applyFrequency() } }
                #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                #endif
                .textFieldStyle(.plain)
                .font(.system(size: isCompact ? 34 : 40, weight: .medium, design: .monospaced))
                .fixedSize()
                .disabled(!model.isReady)
            Text("MHz").foregroundStyle(.secondary)
            if let band = model.bandText {
                Text(band).font(.caption.bold()).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: model.isReceiving ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(model.isReceiving ? Color.green : Color.secondary)
                .accessibilityLabel(model.isReceiving ? "Squelch open" : "Squelch closed")
                .help(ControlHelp.meter)
        }
    }
}

/// The S-meter as a row of bars, as in the Android app. A line a little higher than the bars shows the squelch level: level n
/// stands at the end of bar n, as a signal of S n lights n bars.
private struct SMeterBars: View {
    private static let spacing: CGFloat = 2
    private static let markWidth: CGFloat = 2
    private static let markOverhang: CGFloat = 6

    let value: Int
    let squelch: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<RadioViewModel.sMeterBarCount, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar < value ? color(of: SMeterZone(bar: bar)) : Color.secondary.opacity(0.25))
                    .frame(height: 16)
            }
        }
        .overlay {
            GeometryReader { geometry in
                if let squelch {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: Self.markWidth, height: geometry.size.height + 2 * Self.markOverhang)
                        .offset(x: markOffset(squelch, width: geometry.size.width), y: -Self.markOverhang)
                }
            }
        }
        .padding(.vertical, Self.markOverhang)
    }

    /// Plain yellow is hard to read on a light background.
    private func color(of zone: SMeterZone) -> Color {
        switch zone {
        case .weak: colorScheme == .dark ? .yellow : Color(red: 0.78, green: 0.62, blue: 0)
        case .normal: .green
        case .strong: .orange
        case .overload: .red
        }
    }

    private func markOffset(_ squelch: Int, width: CGFloat) -> CGFloat {
        let barEnd = (width + Self.spacing) * CGFloat(squelch) / CGFloat(RadioViewModel.sMeterBarCount) - Self.spacing
        return max(0, barEnd - Self.markWidth)
    }
}

/// What stays at the bottom: the status, PTT and every message. The Mac shows the status as a bar of the window.
struct BottomBar: View {
    let model: RadioViewModel
    let showsPTT: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            #if os(iOS)
                StatusLine(model: model).padding(.top, 6)
            #endif
            firmware
            if model.isBluetoothBlocked {
                PermissionNotice(permission: .bluetooth).padding(.horizontal).padding(.vertical, 8)
            }
            if showsPTT {
                if model.isDenied(.microphone) {
                    PermissionNotice(permission: .microphone).padding(.horizontal).padding(.vertical, 8)
                } else {
                    PTTBar(model: model)
                }
            }
            NoticeBanner(model: model)
            #if os(macOS)
                Divider()
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(model.hasFailed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            #endif
        }
        .background(.bar)
    }

    @ViewBuilder private var firmware: some View {
        if model.isWebFlasherNeeded {
            WebFlasherNotice().padding(.horizontal).padding(.vertical, 8)
        } else if model.isFirmwareOutdated || model.firmwareUpdate != .idle {
            FirmwareUpdateRow(model: model).padding(.horizontal).padding(.vertical, 8)
        }
    }
}

/// The state of the connection; red with the reason when it has failed.
struct StatusLine: View {
    let model: RadioViewModel

    var body: some View {
        Text(model.statusText)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(model.hasFailed ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
    }
}

/// Why a function is not available, with the way to the system settings.
struct PermissionNotice: View {
    let permission: Permission
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(permission.deniedMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let settings {
                Button("Open Settings") { openURL(settings) }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }

    private var settings: URL? {
        #if os(iOS)
            URL(string: UIApplication.openSettingsURLString)
        #else
            let pane =
                switch permission {
                case .bluetooth: "Privacy_Bluetooth"
                case .microphone: "Privacy_Microphone"
                case .location: "Privacy_LocationServices"
                }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        #endif
    }
}

/// A message the user should see, such as a missing callsign, until it is dismissed.
struct NoticeBanner: View {
    let model: RadioViewModel

    var body: some View {
        if let notice = model.notice {
            HStack(alignment: .firstTextBaseline) {
                Text(notice)
                    .foregroundStyle(model.isNoticeSuccess ? Color.green : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Dismiss", systemImage: "xmark.circle.fill") { model.dismissNotice() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

struct VolumeSlider: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Slider(value: $model.volume, in: 0...1) {
            Text("Volume")
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
        }
    }
}

/// PTT stays in reach below the memories and APRS.
struct PTTBar: View {
    let model: RadioViewModel

    var body: some View {
        VStack(spacing: 6) {
            if let blocked = model.transmitBlockedText {
                Text(blocked).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if model.canSendOnAir {
                HStack(spacing: 8) {
                    PTTButton(model: model).disabled(!model.isReady || model.isSendingAccessTone)
                    if model.canSendAccessTone {
                        AccessToneButton(model: model)
                            .disabled(!model.canTransmit || (model.isTransmitting && !model.isSendingAccessTone))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Press and hold to transmit; with sticky PTT, each press toggles.
private struct PTTButton: View {
    let model: RadioViewModel
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

    var body: some View {
        Label(model.isOnAir ? "On air" : "Push to talk", systemImage: model.isTransmitting ? "mic.fill" : "mic")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(model.isTransmitting ? Color.white : isEnabled ? Color.primary : Color.secondary)
            .background(
                model.isTransmitting ? Color.red : Color.secondary.opacity(isEnabled ? 0.2 : 0.08),
                in: .rect(cornerRadius: 8)
            )
            .holdable(onDown: pressed, onUp: released)
            .sensoryFeedback(.impact(weight: .light), trigger: isPressed) { _, pressed in pressed }
            .sensoryFeedback(.impact, trigger: model.isTransmitting)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await model.isTransmitting ? model.releasePTT() : model.pressPTT() } }
    }

    private func pressed() {
        guard isEnabled, !isPressed else { return }
        isPressed = true
        Task { await model.pressPTT() }
    }

    private func released() {
        guard isPressed else { return }
        isPressed = false
        Task { await model.releasePTT() }
    }
}

/// Press and hold to send the tone that opens a repeater (ADR-0045). It ends by itself, also if still held.
private struct AccessToneButton: View {
    let model: RadioViewModel
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPressed = false

    var body: some View {
        Label(title, systemImage: "waveform")
            .labelStyle(.titleAndIcon)
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(minWidth: 96, minHeight: 64)
            .foregroundStyle(model.isSendingAccessTone ? Color.white : isEnabled ? Color.primary : Color.secondary)
            .background(
                model.isSendingAccessTone ? Color.red : Color.secondary.opacity(isEnabled ? 0.2 : 0.08),
                in: .rect(cornerRadius: 8)
            )
            .holdable(onDown: pressed, onUp: released)
            #if os(iOS)
                .task(id: isPressed && model.isSendingAccessTone) { await vibrateWhileSending() }
            #endif
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(ControlHelp.accessTone)
            .help(ControlHelp.accessTone)
            .accessibilityAction {
                Task { await model.isSendingAccessTone ? model.releaseAccessTone() : model.pressAccessTone() }
            }
    }

    /// Which tone goes out, as a memory can have its own.
    private var title: String {
        model.accessTone.map { "Tone\n\($0.frequency) Hz" } ?? "Tone"
    }

    private func pressed() {
        guard isEnabled, !isPressed else { return }
        isPressed = true
        Task { await model.pressAccessTone() }
    }

    private func released() {
        guard isPressed else { return }
        isPressed = false
        Task { await model.releaseAccessTone() }
    }

    #if os(iOS)
        /// Only here the iPhone vibrates all the time: the finger has to stay, unlike with PTT.
        private func vibrateWhileSending() async {
            guard isPressed, model.isSendingAccessTone else { return }
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            while !Task.isCancelled {
                generator.impactOccurred()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    #endif
}

extension View {
    /// Reports when a press starts and when it ends.
    fileprivate func holdable(onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> some View {
        contentShape(.rect)
            #if os(iOS)
                // SwiftUI reports a held touch late, only UIKit reports it when the finger lands.
                .overlay {
                    TouchArea(onDown: onDown, onUp: onUp)
                }
            #else
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in onDown() }
                        .onEnded { _ in onUp() }
                )
            #endif
    }
}

#if os(iOS)
    /// Reports a touch when the finger lands and when it ends, also if the finger has moved off the area.
    private struct TouchArea: UIViewRepresentable {
        let onDown: () -> Void
        let onUp: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> UIControl {
            let control = UIControl()
            control.addTarget(context.coordinator, action: #selector(Coordinator.down), for: .touchDown)
            control.addTarget(
                context.coordinator,
                action: #selector(Coordinator.up),
                for: [.touchUpInside, .touchUpOutside, .touchCancel]
            )
            return control
        }

        func updateUIView(_ control: UIControl, context: Context) {
            context.coordinator.onDown = onDown
            context.coordinator.onUp = onUp
        }

        @MainActor
        final class Coordinator: NSObject {
            var onDown: () -> Void = {}
            var onUp: () -> Void = {}

            @objc func down() {
                onDown()
            }

            @objc func up() {
                onUp()
            }
        }
    }
#endif
