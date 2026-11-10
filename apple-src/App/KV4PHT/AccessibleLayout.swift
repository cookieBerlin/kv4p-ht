import SwiftUI

/// A row that becomes a column with the accessibility text sizes, where its parts no longer fit side by side.
struct AdaptiveStack<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content
    @Environment(\.dynamicTypeSize) private var textSize

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout =
            textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

extension View {
    /// The look of the small buttons beside a list: a grey capsule with dark text, which is easy to read, and blue while
    /// what it starts is running. The large size gives the finger room enough.
    @ViewBuilder func capsuleButton(isActive: Bool = false) -> some View {
        Group {
            if isActive {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered).tint(.primary)
            }
        }
        .buttonBorderShape(.capsule)
        #if os(iOS)
            .controlSize(.large)
        #endif
    }
}

extension View {
    /// A name for the Mac's VoiceOver, which reads a list or a text field as an element of its own; iOS takes it from
    /// the rows of a list and the placeholder of a field (ADR-0062).
    @ViewBuilder func macName(_ name: LocalizedStringKey) -> some View {
        #if os(macOS)
            accessibilityLabel(name)
        #else
            self
        #endif
    }
}

extension View {
    /// A menu in the look of `capsuleButton`. On the Mac drawn around a plain menu, as in a bordered style the Mac's
    /// VoiceOver cannot show its menu (ADR-0062).
    @ViewBuilder func capsuleMenu() -> some View {
        #if os(macOS)
            buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: .capsule)
                .fixedSize()
        #else
            capsuleButton().fixedSize()
        #endif
    }
}

extension Color {
    /// For small text that must stay readable: darker than the system's secondary grey, which is too faint for it.
    static let strongSecondary = Color.primary.opacity(0.7)
    /// For small links: darker than the system's blue on a light background and lighter on a dark one.
    static let strongAccent = Color("StrongAccent")
    /// The background of the bars above and below the lists: opaque, as text that a list scrolls behind a translucent bar
    /// shows through it, too faint to read (ADR-0062).
    #if os(macOS)
        static let opaqueBar = Color(nsColor: .windowBackgroundColor)
    #else
        static let opaqueBar = Color(uiColor: .secondarySystemBackground)
    #endif
}

/// A count in a capsule, such as the new messages; its colour darkened, so that the white digits stand out.
struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text(count, format: .number)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .background(color.mix(with: .black, by: 0.25), in: .capsule)
    }
}
