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

extension Color {
    /// For small text that must stay readable: darker than the system's secondary grey, which is too faint for it.
    static let strongSecondary = Color.primary.opacity(0.7)
    /// For small links: darker than the system's blue on a light background and lighter on a dark one.
    static let strongAccent = Color("StrongAccent")
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
