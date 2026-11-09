import KV4PAudio
import KV4PRadio
import SwiftUI

#if os(iOS)
    import CoreHaptics
#endif

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
        .modifier(SettingsEntry(model: model))
    }
}

/// The way to the settings. On iPhone and iPad, a reply from their packets page comes back from them, to write it.
private struct SettingsEntry: ViewModifier {
    let model: RadioViewModel
    @State private var isShowingSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                #if os(macOS)
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                #else
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                #endif
            }
            #if os(iOS)
                .navigationDestination(isPresented: $isShowingSettings) { SettingsView(model: model) }
                .onChange(of: model.aprsReplyCount) { isShowingSettings = false }
                .onChange(of: model.chatRequestCount) { isShowingSettings = false }
            #endif
    }
}

/// The connection, the frequency and the S-meter, as at the top of the Android app.
struct RadioHeader: View {
    @Bindable var model: RadioViewModel
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// The level while the squelch mark is being dragged (ADR-0050).
    @State private var draggedSquelch: Int?
    /// The room for the level beside the bars, which grows with the text.
    @ScaledMetric(relativeTo: .footnote) private var levelWidth = 68

    private var isCompact: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A phone chooses and connects the radio in the settings, which leaves the room here to the frequency.
            if !isCompact {
                connection
            }
            if let name = model.activeMemoryName {
                Text(name).font(.headline).lineLimit(1)
            }
            frequency
            HStack {
                SMeterBars(
                    value: model.sMeter,
                    squelch: model.isReady ? model.squelch : nil,
                    canDrag: model.canChangeSquelch,
                    draggedSquelch: $draggedSquelch,
                    onRelease: model.changeSquelch(to:)
                )
                // Here the finger does not cover the level. The width stays, so that the bars do not move under it.
                Text(draggedSquelch.map { "Squelch \($0)" } ?? model.sMeterText)
                    .font(.footnote.monospacedDigit())
                    .fontWeight(draggedSquelch == nil ? .regular : .semibold)
                    .foregroundStyle(draggedSquelch == nil ? Color.strongSecondary : .primary)
                    .lineLimit(1)
                    .frame(width: levelWidth, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("S-meter")
            .accessibilityValue(model.isReady ? "\(model.sMeterText), squelch \(model.squelch)" : model.sMeterText)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.changeSquelch(to: model.squelch + 1)
                case .decrement: model.changeSquelch(to: model.squelch - 1)
                @unknown default: break
                }
            }
            .help(ControlHelp.meter)
            if !isCompact {
                VolumeSlider(model: model)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        // Like an instrument, with the frequency in a size of its own: larger text would push the unit and the band
        // off the line and take the room of the lists below.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var connection: some View {
        HStack {
            RadioPicker(model: model).fixedSize()
            Spacer()
            ConnectButton(model: model).keyboardShortcut(.defaultAction)
        }
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
            Text("MHz").foregroundStyle(Color.strongSecondary).fixedSize()
            if let band = model.bandText {
                Text(band).font(.caption.bold()).foregroundStyle(Color.strongSecondary).fixedSize()
            }
            Spacer()
            Image(systemName: model.isReceiving ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(model.isReceiving ? Color.green : Color.secondary)
                .accessibilityLabel(model.isReceiving ? "Squelch open" : "Squelch closed")
                .help(ControlHelp.meter)
        }
    }
}

/// The choice of radio; while connected, it stays as it is.
struct RadioPicker: View {
    @Bindable var model: RadioViewModel

    var body: some View {
        Picker("Radio", selection: $model.selectedConnection) {
            ForEach(model.connections) { Text($0.label).tag($0) }
        }
        .disabled(!model.canConnect || model.firmwareUpdate.isRunning)
    }
}

/// Connect, or disconnect while connected or connecting.
struct ConnectButton: View {
    let model: RadioViewModel

    var body: some View {
        if model.canConnect {
            Button("Connect") { Task { await model.connect() } }
                .disabled(!model.canStartConnection)
        } else {
            Button("Disconnect") { Task { await model.disconnect() } }
        }
    }
}

/// The S-meter as a row of bars, as in the Android app. A line a little higher than the bars shows the squelch level, and
/// dragging on the bars moves it (ADR-0050).
private struct SMeterBars: View {
    private static let spacing: CGFloat = 2
    private static let markWidth: CGFloat = 2
    private static let markOverhang: CGFloat = 6
    private static let arrowWidth: CGFloat = 8
    private static let arrowHeight: CGFloat = 5
    /// A larger mark shows that it is held, also where nothing vibrates.
    private static let heldArrowScale: CGFloat = 1.3
    /// On a touch screen, a short hold tells the drag from a touch that only passes by.
    private static let holdSeconds = 0.3

    let value: Int
    let squelch: Int?
    let canDrag: Bool
    @Binding var draggedSquelch: Int?
    let onRelease: (Int) -> Void
    /// Ends by itself when the drag ends, also when it is cancelled.
    @GestureState private var dragLevel: Int?
    /// The released level, until the model has it, so that the mark does not jump back in between.
    @State private var releasedLevel: Int?
    @State private var barsWidth: CGFloat = 0
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
                    let level = dragLevel ?? releasedLevel ?? squelch
                    VStack(spacing: 0) {
                        arrow(pointingDown: true)
                        Rectangle().fill(Color.primary).frame(width: Self.markWidth, height: geometry.size.height)
                        arrow(pointingDown: false)
                    }
                    .offset(x: markOffset(level, width: geometry.size.width), y: -Self.arrowHeight)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { barsWidth = $0 }
        .padding(.vertical, Self.markOverhang)
        .contentShape(.rect)
        .gesture(
            markGesture
                .updating($dragLevel) { level, state, _ in state = level }
                .onEnded { level in
                    guard let level else { return }
                    releasedLevel = level == squelch ? nil : level
                    onRelease(level)
                },
            isEnabled: canDrag
        )
        .onChange(of: dragLevel) { draggedSquelch = dragLevel }
        .onChange(of: squelch) { releasedLevel = nil }
        .onChange(of: canDrag) { releasedLevel = nil }
        .sensoryFeedback(trigger: dragLevel) { old, new in
            guard new != nil else { return nil }
            return old == nil ? .impact : .selection
        }
    }

    /// The level the drag stands on, or nil while it has not begun.
    private var markGesture: some Gesture<Int?> {
        #if os(iOS)
            LongPressGesture(minimumDuration: Self.holdSeconds)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .map { stage -> Int? in
                    guard case .second(true, let drag) = stage else { return nil }
                    return drag.map { level(at: $0.location.x) } ?? squelch
                }
        #else
            DragGesture(minimumDistance: 0).map { drag -> Int? in level(at: drag.location.x) }
        #endif
    }

    private func level(at position: CGFloat) -> Int {
        SquelchMark.level(at: position, width: barsWidth, spacing: Self.spacing)
    }

    /// An arrow above or below the line, with its tip on the line; it grows away from there.
    private func arrow(pointingDown: Bool) -> some View {
        SquelchArrow()
            .fill(Color.primary)
            .frame(width: Self.arrowWidth, height: Self.arrowHeight)
            .rotationEffect(pointingDown ? .zero : .degrees(180))
            .scaleEffect(dragLevel == nil ? 1 : Self.heldArrowScale, anchor: pointingDown ? .bottom : .top)
            .animation(.easeOut(duration: 0.1), value: dragLevel == nil)
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
        SquelchMark.position(of: squelch, width: width, spacing: Self.spacing) - Self.arrowWidth / 2
    }
}

/// A filled triangle with its tip at the bottom.
private struct SquelchArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// What stays at the bottom: the status, PTT and every message. The Mac shows the status as a bar of the window.
struct BottomBar: View {
    let model: RadioViewModel
    let showsPTT: Bool
    /// On a phone, the way to the settings, where it connects. There, PTT stands in for the status while connected,
    /// and the status for PTT otherwise.
    var openSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            #if os(iOS)
                if let openSettings {
                    if !model.isReady {
                        ConnectionStatus(model: model, openSettings: openSettings).padding(.vertical, 8)
                    }
                } else {
                    StatusLine(model: model).padding(.top, 6)
                }
            #endif
            firmware
            if model.isBluetoothBlocked {
                PermissionNotice(permission: .bluetooth).padding(.horizontal).padding(.vertical, 8)
            }
            if showsPTT, openSettings == nil || model.isReady {
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
                    .foregroundStyle(model.isStatusFailure ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            #endif
        }
        .background(.bar)
    }

    @ViewBuilder private var firmware: some View {
        if model.needsFirmwareUpdateElsewhere {
            FirmwareElsewhereNotice().padding(.horizontal).padding(.vertical, 8)
        } else if model.offersFirmwareSettings {
            #if os(macOS)
                FirmwareSettingsNotice(model: model).padding(.horizontal).padding(.vertical, 8)
            #endif
        }
    }
}

#if os(macOS)
    /// The radio needs another firmware; the update itself is in the settings.
    struct FirmwareSettingsNotice: View {
        let model: RadioViewModel
        @Environment(\.openSettings) private var openSettings

        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Text("The radio needs a firmware update.").foregroundStyle(.orange)
                Spacer()
                Button("Open Settings") {
                    model.requestFirmwareSettings()
                    openSettings()
                }
            }
        }
    }
#endif

/// The state of the connection; red with the reason when it has failed.
struct StatusLine: View {
    let model: RadioViewModel

    var body: some View {
        Text(model.statusText)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(model.isStatusFailure ? Color.red : Color.strongSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
    }
}

#if os(iOS)
    /// Without a connection, the status in place of PTT; while the radio can be connected, it leads to the settings.
    private struct ConnectionStatus: View {
        let model: RadioViewModel
        let openSettings: () -> Void

        var body: some View {
            if model.canConnect {
                Button(action: openSettings) {
                    VStack(spacing: 4) {
                        StatusLine(model: model)
                        Label("Connect in Settings", systemImage: "gearshape")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                StatusLine(model: model).frame(minHeight: 44)
            }
        }
    }
#endif

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
            URL(
                string: permission == .notifications
                    ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString
            )
        #else
            let security = "com.apple.preference.security?"
            let pane =
                switch permission {
                case .bluetooth: security + "Privacy_Bluetooth"
                case .microphone: security + "Privacy_Microphone"
                case .location: security + "Privacy_LocationServices"
                case .notifications: "com.apple.Notifications-Settings.extension"
                }
            return URL(string: "x-apple.systempreferences:\(pane)")
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
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A phone shows the microphone alone, which says enough and keeps its size with large text.
    private var isSymbolOnly: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    private var label: some View {
        Label(model.isOnAir ? "On air" : "Push to talk", systemImage: model.isTransmitting ? "mic.fill" : "mic")
    }

    var body: some View {
        Group {
            if isSymbolOnly {
                label.labelStyle(.iconOnly).font(.largeTitle)
            } else {
                label.font(.headline)
            }
        }
        // No large view of the content: it shows on a long press, which is how PTT is held.
        .dynamicTypeSize(...(isSymbolOnly ? .accessibility1 : .accessibility5))
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

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A phone shows the tone burst with its frequency below, as PTT shows only its symbol there.
    private var isSymbolOnly: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    @ViewBuilder private var label: some View {
        if isSymbolOnly {
            VStack(spacing: 2) {
                Image("tone.burst").font(.title)
                    .imageScale(.large)
                if let tone = model.accessTone {
                    Text("\(tone.frequency) Hz").font(.caption)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tone")
            .accessibilityValue(model.accessTone.map { "\($0.frequency) Hz" } ?? "")
        } else {
            Label(title, systemImage: "waveform")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
    }

    var body: some View {
        label
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
        /// Only here the iPhone vibrates all the time: the finger has to stay, unlike with PTT. One continuous pattern
        /// rather than an impact every few milliseconds, which asks the system for less.
        private func vibrateWhileSending() async {
            guard isPressed, model.isSendingAccessTone, let vibration = ContinuousVibration() else { return }
            vibration.start()
            // Ends when the task is cancelled, as the tone ends or the button is let go.
            try? await Task.sleep(for: .seconds(3600))
            vibration.stop()
        }
    #endif
}

#if os(iOS)
    /// A vibration that lasts until it is stopped; longer than any access tone. `nil` where the device cannot vibrate.
    @MainActor
    private final class ContinuousVibration {
        private let engine: CHHapticEngine
        private let player: any CHHapticPatternPlayer

        init?() {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
                let engine = try? CHHapticEngine(),
                let pattern = try? CHHapticPattern(
                    events: [
                        CHHapticEvent(
                            eventType: .hapticContinuous,
                            parameters: [
                                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
                            ],
                            relativeTime: 0,
                            duration: 30
                        )
                    ],
                    parameters: []
                ),
                let player = try? engine.makePlayer(with: pattern)
            else { return nil }
            // Haptics only: otherwise the engine also takes part in the app's audio session, which carries the radio.
            engine.playsHapticsOnly = true
            // The engine stops itself when idle; stopping it after the pattern made Core Haptics report an error.
            engine.isAutoShutdownEnabled = true
            self.engine = engine
            self.player = player
        }

        func start() {
            try? engine.start()
            try? player.start(atTime: CHHapticTimeImmediate)
        }

        func stop() {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
    }
#endif

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
