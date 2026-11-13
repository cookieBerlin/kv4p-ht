import KV4PPersistence

extension MemoryKind {
    /// What the form shows and VoiceOver reads.
    public var title: String {
        switch self {
        case .frequency: "Frequency"
        case .repeater: "Repeater"
        case .beacon: "Beacon"
        }
    }

    /// The symbol of the kind in the lists and the form: a dial to tune, an antenna that passes signals on, a light
    /// that marks a place (ADR-0065).
    public var symbol: String {
        switch self {
        case .frequency: "dial.medium"
        case .repeater: "antenna.radiowaves.left.and.right"
        case .beacon: "light.beacon.max"
        }
    }
}

extension RadioViewModel {
    /// What VoiceOver reads for a memory in a list: its kind, the name, the frequency and, where the row shows it, the
    /// comment. One text, as SwiftUI on the Mac can run into an endless loop resolving a label it combines from a
    /// labelled symbol and texts.
    public func spokenRow(_ memory: ChannelMemory, withComment: Bool) -> String {
        let comment = withComment && !memory.comment.isEmpty ? [memory.comment] : []
        return ([memory.kind.title, memory.name, shown(memory.frequency) + " MHz"] + comment).joined(separator: ", ")
    }
}
