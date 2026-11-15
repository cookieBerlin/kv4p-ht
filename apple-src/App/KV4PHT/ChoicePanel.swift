import SwiftUI

extension View {
    /// A panel of choices beside the button it opens from: a popover on the Mac and the iPad, and a sheet where the
    /// window is narrow, as on a phone. It stays open while the choices change, so that several can be made at once,
    /// and closes with *Done*, a tap beside it or Esc (ADR-0068). The button takes `identifier`, the panel
    /// `<identifier>-panel` and its *Done* `<identifier>-done`, for the UI tests. A popover of the Mac does not size a
    /// form to its rows, so it takes `macHeight`.
    func choicePanel<Content: View>(
        _ title: LocalizedStringKey,
        identifier: String,
        isPresented: Binding<Bool>,
        macHeight: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        accessibilityIdentifier(identifier)
            .popover(isPresented: isPresented, arrowEdge: .top) {
                ChoicePanel(
                    title: title,
                    identifier: identifier,
                    isShown: isPresented,
                    macHeight: macHeight,
                    content: content
                )
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
            }
    }

    /// A text field that filters, with a button that clears it once it holds text; on the Mac, Esc clears it too.
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
            NavigationStack {
                form
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShown = false }
                                .accessibilityIdentifier("\(identifier)-done")
                        }
                    }
            }
            .frame(minWidth: 320, idealWidth: 360, minHeight: 420, idealHeight: 520)
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
            #if os(macOS)
                .onExitCommand { text = "" }
            #endif
    }
}
