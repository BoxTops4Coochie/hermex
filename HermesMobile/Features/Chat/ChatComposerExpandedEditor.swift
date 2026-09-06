import SwiftUI
import UIKit

/// Near-full-screen expanded text editor for long drafts (#365).
///
/// Presented as a root-overlay from ChatView (not a sheet) so the layout
/// proposal is UIScreen-sized and the keyboard safe area applies at the
/// window level, ChatGPT-style: scrim, material card, top-right collapse,
/// floating send button. Shares the draft text binding with the inline
/// composer; focus is owned privately here so the inline composer resigns
/// and cannot race the editor's first responder.
struct ComposerExpandedEditor: View {
    @Binding var text: String

    let isSendDisabled: Bool
    let onSend: () -> Void
    let onCollapse: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onCollapse() }

            VStack(spacing: 0) {
                HStack {
                    Text("Compose")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                    Spacer()
                    collapseButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                ComposerTextView(
                    text: $text,
                    isFocused: $editorFocused,
                    isDisabled: false,
                    isKeyboardSendEnabled: false,
                    noHeightCap: true,
                    onKeyboardSend: {},
                    onHeightChange: { _ in },
                    onPasteFileProviders: { _ in },
                    onPasteFileURLs: { _ in },
                    onPasteImageProviders: { _ in },
                    onPasteImages: { _ in }
                )
                .padding(.horizontal, 6)
                .padding(.bottom, 18)
            }
            .adaptiveGlass(
                .regular,
                isInteractive: true,
                fallbackMaterial: .regularMaterial,
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 22, y: 8)
            .overlay(alignment: .bottomTrailing) {
                sendButton
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
        }
        .onAppear { editorFocused = true }
        .onDisappear { editorFocused = false }
    }

    private var collapseButton: some View {
        Button {
            onCollapse()
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.chatTactile(.icon))
        .accessibilityLabel("Collapse editor")
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.accentColor))
        }
        .buttonStyle(.chatTactile(.icon))
        .disabled(isSendDisabled)
        .opacity(isSendDisabled ? 0.4 : 1.0)
        .accessibilityLabel("Send message")
        .padding(18)
    }
}
