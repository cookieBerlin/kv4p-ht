import SwiftUI

#if os(iOS)
    import UIKit

    /// Closes the keyboard, wherever a text field has it.
    @MainActor
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    extension View {
        /// Follows whether the keyboard is shown.
        func observesKeyboard(_ isShown: Binding<Bool>) -> some View {
            onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isShown.wrappedValue = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isShown.wrappedValue = false
            }
        }
    }
#endif

/// Closes the keyboard, beside a line to write in, while it is shown. A button of the keyboard's own toolbar floats over
/// the line on iOS 27, so it stays in the line instead. Nothing on the Mac.
struct KeyboardDismissButton: View {
    @State private var isShown = false

    var body: some View {
        #if os(iOS)
            Group {
                if isShown {
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") { dismissKeyboard() }
                        .labelStyle(.iconOnly)
                }
            }
            .observesKeyboard($isShown)
        #endif
    }
}
