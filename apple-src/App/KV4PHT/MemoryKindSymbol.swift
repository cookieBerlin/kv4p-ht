import KV4PPersistence
import SwiftUI

extension MemoryKind {
    /// What the form and VoiceOver call it.
    var title: LocalizedStringKey {
        switch self {
        case .frequency: "Frequency"
        case .repeater: "Repeater"
        case .beacon: "Beacon"
        }
    }

    /// The symbol in the list; a frequency has none.
    var symbol: String? {
        switch self {
        case .frequency: nil
        case .repeater: "antenna.radiowaves.left.and.right"
        case .beacon: "dot.radiowaves.up.forward"
        }
    }
}

/// Marks a repeater or a beacon in a list of memories; a frequency keeps the room, so that the names line up.
struct MemoryKindSymbol: View {
    let kind: MemoryKind
    @ScaledMetric(relativeTo: .body) private var width = 24

    var body: some View {
        Group {
            if let symbol = kind.symbol {
                Label(kind.title, systemImage: symbol)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear.accessibilityHidden(true)
            }
        }
        .frame(width: width)
    }
}
