import KV4PPersistence
import KV4PRadio
import SwiftUI

/// Marks the kind of a memory in a list of memories, in a column of its own, so that the names line up. Its row says
/// the kind to VoiceOver (`spokenRow`).
struct MemoryKindSymbol: View {
    let kind: MemoryKind
    @ScaledMetric(relativeTo: .body) private var width = 24

    var body: some View {
        Image(systemName: kind.symbol)
            .foregroundStyle(.secondary)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}
