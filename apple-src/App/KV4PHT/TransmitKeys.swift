import KV4PRadio
import SwiftUI

#if os(macOS)
    import AppKit

    extension View {
        /// The Mac transmits while the space bar is held, as while PTT is, and sends the access tone while ⌥ and the
        /// space bar are (ADR-0075). Only in the window it is on, and never while a text field takes the typing.
        func transmitKeys(_ model: RadioViewModel) -> some View {
            modifier(TransmitKeys(model: model))
        }
    }

    private struct TransmitKeys: ViewModifier {
        let model: RadioViewModel
        @State private var monitor = TransmitKeyMonitor()

        func body(content: Content) -> some View {
            content
                .background(WindowReader { monitor.window = $0 })
                .onAppear { monitor.start(model) }
                .onDisappear { monitor.stop() }
                // The release of a key held while the app goes behind another never comes here.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    monitor.releaseHeld()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                    if (note.object as? NSWindow) === monitor.window { monitor.releaseHeld() }
                }
        }
    }

    /// Watches the keys of the app's window, as SwiftUI tells the release of a key only to a view with the focus.
    @MainActor
    private final class TransmitKeyMonitor {
        private static let space: UInt16 = 49

        weak var window: NSWindow?
        private var token: Any?
        private var held: TransmitKey?
        private weak var model: RadioViewModel?

        func start(_ model: RadioViewModel) {
            self.model = model
            guard token == nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                // The monitor runs on the main thread; only what is needed of the event goes in.
                let key = Key(
                    code: event.keyCode,
                    isDown: event.type == .keyDown,
                    modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
                    window: event.windowNumber
                )
                let isTaken = MainActor.assumeIsolated { self?.takes(key) ?? false }
                return isTaken ? nil : event
            }
        }

        func stop() {
            releaseHeld()
            if let token { NSEvent.removeMonitor(token) }
            token = nil
        }

        private struct Key: Sendable {
            let code: UInt16
            let isDown: Bool
            let modifiers: UInt
            let window: Int
        }

        /// Whether the key is taken here, rather than passed on.
        private func takes(_ key: Key) -> Bool {
            guard key.code == Self.space, let model, let window, key.window == window.windowNumber else { return false }
            guard key.isDown else {
                guard held != nil else { return false }
                releaseHeld()
                return true
            }
            // A held key repeats; the first press counts.
            if held != nil { return true }
            // A text field takes the space bar for itself.
            if window.firstResponder is NSText { return false }
            let modifiers = NSEvent.ModifierFlags(rawValue: key.modifiers)
            let transmitKey: TransmitKey = modifiers == .option ? .accessTone : .ptt
            guard modifiers.isEmpty || modifiers == .option, model.canPress(transmitKey) else { return false }
            held = transmitKey
            Task { await model.press(transmitKey) }
            return true
        }

        func releaseHeld() {
            guard let key = held, let model else { return }
            held = nil
            Task { await model.release(key) }
        }
    }

    /// The window a view is in, once it is in one.
    private struct WindowReader: NSViewRepresentable {
        let found: (NSWindow?) -> Void

        func makeNSView(context: Context) -> NSView {
            WindowView(found: found)
        }

        func updateNSView(_ view: NSView, context: Context) {}

        private final class WindowView: NSView {
            let found: (NSWindow?) -> Void

            init(found: @escaping (NSWindow?) -> Void) {
                self.found = found
                super.init(frame: .zero)
            }

            required init?(coder: NSCoder) { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                found(window)
            }
        }
    }
#endif
