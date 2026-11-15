import SwiftUI

extension View {
    /// A panel of choices beside the button it opens from: a popover on the Mac and the iPad, and a sheet where the
    /// window is narrow, as on a phone. It stays open while the choices change, so that several can be made at once,
    /// and closes with *Done*, a tap beside it or Esc (ADR-0068). The button takes `identifier`, the panel
    /// `<identifier>-panel` and its *Done* `<identifier>-done`, for the UI tests. A popover of the Mac does not size a
    /// form to its rows, so it takes `macHeight`. A button at the bottom, as one that floats, opens it above with
    /// `arrowEdge: .bottom`; below it, the panel would reach out of the window.
    func choicePanel<Content: View>(
        _ title: LocalizedStringKey,
        identifier: String,
        isPresented: Binding<Bool>,
        macHeight: CGFloat,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        accessibilityIdentifier(identifier)
            .popover(isPresented: isPresented, arrowEdge: arrowEdge) {
                ChoicePanel(
                    title: title,
                    identifier: identifier,
                    isShown: isPresented,
                    macHeight: macHeight,
                    content: content
                )
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.large])
            }
    }

    /// A text field that filters, with a button that clears it once it holds text. Esc stays with the panel around it.
    func clearable(_ text: Binding<String>) -> some View {
        modifier(ClearButton(text: text))
    }
}

private struct ChoicePanel<Content: View>: View {
    let title: LocalizedStringKey
    let identifier: String
    @Binding var isShown: Bool
    let macHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
            form.frame(width: 320, height: macHeight)
        #else
            VStack(spacing: 0) {
                // A title row of its own rather than a navigation bar, whose buttons do not grow with the text.
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    // Of glass, as the buttons of a sheet's bar are, with room for a finger and the colour of the text.
                    Button("Done") { isShown = false }
                        .bold()
                        .foregroundStyle(.primary)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .accessibilityIdentifier("\(identifier)-done")
                }
                .padding()
                form
            }
            .frame(minWidth: 320, idealWidth: 360, minHeight: 420, idealHeight: 520)
            // One ground under the title and the form, as under a bar.
            .background(Color(uiColor: .systemGroupedBackground))
        #endif
    }

    private var form: some View {
        Form { content() }
            .formStyle(.grouped)
            #if os(macOS)
                // Checkboxes, as is the Mac's custom, which carry their names; its switches in a form stand apart from
                // them.
                .toggleStyle(.checkbox)
            #endif
            .accessibilityIdentifier("\(identifier)-panel")
    }
}

private struct ClearButton: ViewModifier {
    @Binding var text: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if !text.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.strongSecondary)
                        #if os(iOS)
                            // Room enough for a finger, beyond the field's own height.
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                        #else
                            .padding(.trailing, 4)
                        #endif
                }
            }
    }
}

extension View {
    /// Buttons that float over a list or the map, at the bottom on the right, within reach of a thumb, so that the
    /// content has the full height. A list scrolls its last rows above them.
    func floatingControls<Controls: View>(@ViewBuilder _ controls: () -> Controls) -> some View {
        safeAreaInset(edge: .bottom, alignment: .trailing) {
            VStack(spacing: 12) { controls() }
                .padding([.trailing, .bottom], 16)
        }
    }

    /// The look of a button that floats: a round one of glass, with its symbol only; the name stays for VoiceOver and
    /// the tooltip.
    func floatingButton() -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            // The Mac's large size stays small beside the switches; its extra large one matches them.
            #if os(macOS)
                .controlSize(.extraLarge)
            #else
                .controlSize(.large)
            #endif
    }
}

extension View {
    /// A menu in the look of `floatingButton`. On the Mac the glass is drawn around a plain menu, as in a bordered style
    /// the Mac's VoiceOver cannot show its menu (ADR-0062), and as it drops the name of a menu with its symbol only.
    @ViewBuilder func floatingMenu(_ name: LocalizedStringKey) -> some View {
        #if os(macOS)
            labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .font(.title3)
                .frame(width: 36, height: 36)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(name)
        #else
            menuIndicator(.hidden).floatingButton()
        #endif
    }
}

/// A line above a list while its filter hides rows: what it looks for, and a button to clear it.
struct FilterNotice: View {
    let text: String
    let clear: () -> Void

    var body: some View {
        HStack {
            Label(text, systemImage: "line.3.horizontal.decrease")
                .font(.footnote)
                .foregroundStyle(Color.strongSecondary)
            Spacer()
            Button("Clear filter", action: clear)
                .font(.footnote)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
        .accessibilityIdentifier("filter-notice")
    }
}
