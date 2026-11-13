/// What a held key sends on the Mac, as its button does while held: PTT with the space bar, the access tone with ⌥
/// and the space bar (ADR-0075).
public enum TransmitKey: Equatable, Sendable {
    case ptt, accessTone
}

extension RadioViewModel {
    /// Whether the key can transmit now: only where its button is there and can be pressed.
    public func canPress(_ key: TransmitKey) -> Bool {
        switch key {
        case .ptt: isReady && canSendOnAir && !isDenied(.microphone) && !isSendingAccessTone
        case .accessTone: canSendAccessTone && canTransmit && (!isTransmitting || isSendingAccessTone)
        }
    }

    /// The tone returns when it is over.
    public func press(_ key: TransmitKey) async {
        switch key {
        case .ptt: await pressPTT()
        case .accessTone: await pressAccessTone()
        }
    }

    public func release(_ key: TransmitKey) async {
        switch key {
        case .ptt: await releasePTT()
        case .accessTone: await releaseAccessTone()
        }
    }
}
