import SwiftUI

/// Groups the typing-session bookkeeping modifiers so ChatView's body
/// modifier chain stays within Xcode's type-check budget (#316 pattern).
struct ComposerTypingSessionGate: ViewModifier {
    let composerIsFocused: Bool
    let draftMessage: String
    let onUpdate: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: composerIsFocused) { _, _ in
                onUpdate()
            }
            .onChange(of: draftMessage) { _, _ in
                onUpdate()
            }
    }
}
