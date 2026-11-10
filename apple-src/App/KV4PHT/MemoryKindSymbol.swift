import KV4PPersistence
import KV4PRadio
import SwiftUI

extension MemoryKind {
    /// What the form shows and VoiceOver reads.
    var title: String {
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

extension RadioViewModel {
    /// What VoiceOver reads for a memory in a list: the kind of a repeater or a beacon, the name, the frequency and,
    /// where the row shows it, the comment. One text, as SwiftUI on the Mac can run into an endless loop resolving a
    /// label it combines from a labelled symbol and texts.
    func spokenRow(_ memory: ChannelMemory, withComment: Bool) -> String {
        let kind = memory.kind.symbol == nil ? [] : [memory.kind.title]
        let comment = withComment && !memory.comment.isEmpty ? [memory.comment] : []
        return (kind + [memory.name, shown(memory.frequency) + " MHz"] + comment).joined(separator: ", ")
    }
}

/// Marks a repeater or a beacon in a list of memories; a frequency keeps the room, so that the names line up. Its row
/// says the kind to VoiceOver (`spokenRow`).
struct MemoryKindSymbol: View {
    let kind: MemoryKind
    @ScaledMetric(relativeTo: .body) private var width = 24

    var body: some View {
        Group {
            if let symbol = kind.symbol {
                Image(systemName: symbol).foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}
