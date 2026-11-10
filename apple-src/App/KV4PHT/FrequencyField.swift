import KV4PRadio
import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The frequency at the top: entered as a number, or stepped digit by digit in the channel raster (ADR-0064). The Mac
/// steps the digit under the pointer with the scroll wheel and the one at the cursor with ↑ and ↓; iPhone and iPad step
/// a digit with a vertical swipe on it. ⌥, or a long press before the swipe, steps by the digit exactly.
struct FrequencyField: View {
    /// The lowest digit, which steps by the raster.
    static let rasterDigit = 100

    @Bindable var model: RadioViewModel
    let size: CGFloat
    @FocusState private var isFocused: Bool
    @State private var width: CGFloat = 0
    #if os(macOS)
        @State private var hovered: Int?
        @State private var scroll = ScrollSteps()
        @State private var scrollMonitor: Any?
        @State private var keyMonitor: Any?
    #else
        @State private var swipe: Swipe?
    #endif

    var body: some View {
        TextField("Frequency", text: text, prompt: Text(placeholder))
            .focused($isFocused)
            .onSubmit { Task { await model.applyFrequency() } }
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .disabled(!model.isReady)
            .accessibilityIdentifier("frequency")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(Self.rasterDigit, by: 1)
                case .decrement: step(Self.rasterDigit, by: -1)
                @unknown default: break
                }
            }
            #if os(macOS)
                .background(alignment: .leading) { highlight }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hovered = character(at: location.x)
                    case .ended: hovered = nil
                    }
                }
                .onChange(of: hovered != nil) { _, isOver in watchScrolling(isOver) }
                .onChange(of: isFocused) { _, isFocused in watchKeys(isFocused) }
                .onDisappear {
                    watchScrolling(false)
                    watchKeys(false)
                }
                .help(ControlHelp.frequency)
            #else
                .keyboardType(.decimalPad)
                .toolbar {
                    if isFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isFocused = false
                                Task { await model.applyFrequency() }
                            }
                        }
                    }
                }
                .simultaneousGesture(swipeGesture)
            #endif
    }

    /// The shape of a frequency, until the radio reports one.
    private var placeholder: String { "---" + model.decimalSeparator + "----" }

    /// Digits and one separator only.
    private var text: Binding<String> {
        Binding {
            model.frequencyText
        } set: {
            model.frequencyText = NumberInput.filtered($0, allowsSeparator: true)
        }
    }

    /// The character at `x`: the font has one width for all.
    private func character(at x: CGFloat) -> Int? {
        let count = model.frequencyText.count
        guard count > 0, width > 0, x >= 0 else { return nil }
        return Int(x / (width / CGFloat(count)))
    }

    private func step(_ digit: Int, by count: Int, exact: Bool = false) {
        Task { await model.stepFrequency(digit: digit, by: count, exact: exact) }
    }

    private func step(atCharacter index: Int?, by count: Int, exact: Bool) {
        guard count != 0, let index, let digit = FrequencyStep.digit(atCharacter: index, in: model.frequencyText)
        else { return }
        step(digit, by: count, exact: exact)
    }

    #if os(macOS)
        /// The digit the scroll wheel would step.
        @ViewBuilder private var highlight: some View {
            let count = model.frequencyText.count
            if model.canStepFrequency, let hovered, count > 0,
                FrequencyStep.digit(atCharacter: hovered, in: model.frequencyText) != nil
            {
                let characterWidth = width / CGFloat(count)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: characterWidth)
                    .offset(x: CGFloat(hovered) * characterWidth)
                    .accessibilityHidden(true)
            }
        }

        /// The scroll wheel steps the digit under the pointer instead of scrolling the window, and only then.
        private func watchScrolling(_ isOver: Bool) {
            if let scrollMonitor, !isOver {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
            } else if scrollMonitor == nil, isOver {
                scroll.reset()
                scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                    MainActor.assumeIsolated { scrolled(event) } ? nil : event
                }
            }
        }

        /// Up is higher, also with natural scrolling.
        private func scrolled(_ event: NSEvent) -> Bool {
            guard model.canStepFrequency, let hovered else { return false }
            if event.phase == .began { scroll.reset() }
            let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            let count = scroll.steps(for: delta, isPrecise: event.hasPreciseScrollingDeltas)
            step(atCharacter: hovered, by: count, exact: event.modifierFlags.contains(.option))
            return true
        }

        /// ↑ and ↓ while the field is being edited; its field editor would otherwise move the cursor with them.
        private func watchKeys(_ isFocused: Bool) {
            if let keyMonitor, !isFocused {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            } else if keyMonitor == nil, isFocused {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    MainActor.assumeIsolated { pressed(event) } ? nil : event
                }
            }
        }

        private func pressed(_ event: NSEvent) -> Bool {
            let up: UInt16 = 126
            let down: UInt16 = 125
            guard event.keyCode == up || event.keyCode == down,
                let editor = NSApp.keyWindow?.firstResponder as? NSTextView
            else { return false }
            stepAtCursor(in: editor, by: event.keyCode == up ? 1 : -1, exact: event.modifierFlags.contains(.option))
            return true
        }

        /// The cursor stays where it was, also as the text is replaced.
        private func stepAtCursor(in editor: NSTextView, by count: Int, exact: Bool) {
            let offset = editor.selectedRange().location
            guard model.canStepFrequency, let digit = FrequencyStep.digit(atCursor: offset, in: model.frequencyText)
            else { return }
            Task {
                await model.stepFrequency(digit: digit, by: count, exact: exact)
                editor.setSelectedRange(NSRange(location: min(offset, editor.string.utf16.count), length: 0))
            }
        }
    #else
        /// A vertical swipe on a digit; a hold before it steps by the digit exactly.
        private struct Swipe {
            static let distance: CGFloat = 24
            static let holdSeconds = 0.4
            var character: Int?
            var began: Date
            var exact: Bool?
            var steps = 0
        }

        private var swipeGesture: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard model.canStepFrequency else { return }
                    var current = swipe ?? Swipe(character: character(at: value.startLocation.x), began: value.time)
                    let height = -value.translation.height
                    if current.exact == nil, abs(height) >= Swipe.distance / 2 {
                        guard abs(height) > abs(value.translation.width) else {
                            swipe = Swipe(character: nil, began: current.began)  // a sideways swipe: not ours
                            return
                        }
                        current.exact = value.time.timeIntervalSince(current.began) >= Swipe.holdSeconds
                    }
                    let steps = Int(height / Swipe.distance)
                    if let exact = current.exact, steps != current.steps {
                        step(atCharacter: current.character, by: steps - current.steps, exact: exact)
                        current.steps = steps
                    }
                    swipe = current
                }
                .onEnded { _ in swipe = nil }
        }
    #endif
}

/// − and + beside the frequency on iPhone and iPad: a step by the raster, repeated while held.
struct FrequencyStepButtons: View {
    let model: RadioViewModel

    /// The size Apple asks for a touch target; it stays, as the line has no room for more.
    private let size: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            button("Frequency down", systemImage: "minus", id: "frequency-down", count: -1)
            button("Frequency up", systemImage: "plus", id: "frequency-up", count: 1)
        }
        .buttonRepeatBehavior(.enabled)
        .disabled(!model.canStepFrequency)
    }

    private func button(_ title: LocalizedStringKey, systemImage: String, id: String, count: Int) -> some View {
        Button {
            step(count)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: size, height: size)
                .background(.quaternary, in: Circle().inset(by: size / 8))
                .contentShape(.circle)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }

    private func step(_ count: Int) {
        Task { await model.stepFrequency(digit: FrequencyField.rasterDigit, by: count) }
    }
}
