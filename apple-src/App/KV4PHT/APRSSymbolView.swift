import KV4PAPRS
import SwiftUI

/// The icon of an APRS symbol, with the mark of an overlay; what a packet has but this app does not know is a pin.
struct APRSSymbolView: View {
    let symbol: APRSSymbolInfo

    var body: some View {
        icon
            .overlay(alignment: .bottomTrailing) {
                if let overlay = symbol.overlay {
                    Text(String(overlay))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 2)
                        .background(.black.opacity(0.75), in: .rect(cornerRadius: 3))
                }
            }
    }

    @ViewBuilder private var icon: some View {
        switch symbol.icon {
        case .character(let text): Text(text)
        case .system(let name): Image(systemName: name)
        case nil: Image(systemName: "mappin")
        }
    }
}

extension APRSSymbol {
    /// For a row of a menu, which shows no icon of its own making: a character goes in front of the name.
    @ViewBuilder var menuLabel: some View {
        switch icon {
        case .character(let text): Text("\(text) \(name)")
        case .system(let image): Label(name, systemImage: image)
        case nil: Text(name)
        }
    }
}
