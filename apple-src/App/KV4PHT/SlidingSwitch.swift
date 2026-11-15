import SwiftUI

/// A choice of one among a few, such as map or list, or the packets, the chats and the map beside the memories: a
/// track of glass in which a thumb slides to the one chosen. Each shows its symbol, and with `showsTitles` its title
/// beside it where there is room, and a count where it has one; with large text or in a narrow column, the symbols
/// stand alone. VoiceOver and the UI tests see a button each, the chosen one marked as selected, within a group named by
/// `label`.
struct SlidingSwitch<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let symbol: String
        var count = 0
    }

    let label: LocalizedStringKey
    @Binding var selection: Value
    let options: [Option]
    var showsTitles = false

    @Namespace private var space
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
        // As high as the large buttons beside it, and growing with the text.
        @ScaledMetric(relativeTo: .body) private var height = 44
        @ScaledMetric(relativeTo: .body) private var width = 52
        private let inset: CGFloat = 3
    #else
        private let height: CGFloat = 24
        private let width: CGFloat = 32
        private let inset: CGFloat = 2
    #endif

    init(_ label: LocalizedStringKey, selection: Binding<Value>, options: [Option], showsTitles: Bool = false) {
        self.label = label
        _selection = selection
        self.options = options
        self.showsTitles = showsTitles
    }

    var body: some View {
        if showsTitles {
            ViewThatFits(in: .horizontal) {
                track(withTitles: true)
                track(withTitles: false)
            }
        } else {
            track(withTitles: false)
        }
    }

    private func track(withTitles: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                segment(option, withTitles: withTitles)
            }
        }
        .padding(inset)
        // Tinted grey beneath the glass, so that the white thumb stands out also over a white background; of glass, as
        // the buttons floating beside it, so that it stands out over the map as over a list.
        .background(Color.primary.opacity(0.12), in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: Option, withTitles: Bool) -> some View {
        Button {
            withAnimation(.snappy) { selection = option.value }
        } label: {
            content(option, withTitles: withTitles)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, withTitles ? 12 : 0)
                .frame(minWidth: width, minHeight: height)
                .background {
                    if selection == option.value {
                        // Lighter than the track in dark too, as the system's segmented switch has it.
                        Capsule()
                            .fill(colorScheme == .dark ? Color(white: 0.5) : .white)
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: space)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(option.title)
        // With the count, as "Chats (2)", as the page bar of a phone reads it.
        .accessibilityLabel(option.count > 0 ? "\(option.title) (\(option.count))" : option.title)
        .accessibilityAddTraits(selection == option.value ? .isSelected : [])
    }

    private func content(_ option: Option, withTitles: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: option.symbol)
                .overlay(alignment: .topTrailing) {
                    if option.count > 0, !withTitles {
                        CountBadge(count: option.count, color: .red)
                            .fixedSize()
                            .offset(x: 12, y: -10)
                    }
                }
            if withTitles {
                Text(option.title)
                if option.count > 0 {
                    CountBadge(count: option.count, color: .red)
                }
            }
        }
    }
}
