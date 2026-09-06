import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposerTextInputView: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var inputHeight: CGFloat
    @Binding var measuredHeight: CGFloat

    let isDisabled: Bool
    let isKeyboardSendEnabled: Bool
    let verticalPadding: CGFloat
    let onKeyboardSend: () -> Void
    let onPasteFileProviders: ([NSItemProvider]) -> Void
    let onPasteFileURLs: ([URL]) -> Void
    let onPasteImageProviders: ([NSItemProvider]) -> Void
    let onPasteImages: ([UIImage]) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ComposerTextView(
                text: $text,
                isFocused: $isFocused,
                isDisabled: isDisabled,
                isKeyboardSendEnabled: isKeyboardSendEnabled,
                onKeyboardSend: onKeyboardSend,
                onHeightChange: updateMeasuredHeight,
                onPasteFileProviders: onPasteFileProviders,
                onPasteFileURLs: onPasteFileURLs,
                onPasteImageProviders: onPasteImageProviders,
                onPasteImages: onPasteImages
            )
            .frame(height: inputHeight)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, 16)

            if text.isEmpty {
                Text("Ask anything... /commands")
                    .foregroundStyle(Color(.placeholderText))
                    .padding(.horizontal, 16)
                    .padding(.vertical, verticalPadding)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 42, alignment: .topLeading)
    }

    private func updateMeasuredHeight(_ newHeight: CGFloat) {
        guard inputHeight != newHeight || measuredHeight != newHeight else { return }

        DispatchQueue.main.async {
            guard inputHeight != newHeight || measuredHeight != newHeight else { return }
            inputHeight = newHeight
            measuredHeight = newHeight
        }
    }
}

private struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let isDisabled: Bool
    let isKeyboardSendEnabled: Bool
    /// Expanded-editor mode: no height cap, internal scrolling instead (#365).
    var noHeightCap: Bool = false
    let onKeyboardSend: () -> Void
    let onHeightChange: (CGFloat) -> Void
    let onPasteFileProviders: ([NSItemProvider]) -> Void
    let onPasteFileURLs: ([URL]) -> Void
    let onPasteImageProviders: ([NSItemProvider]) -> Void
    let onPasteImages: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onHeightChange: onHeightChange)
    }

    func makeUIView(context: Context) -> PastingTextView {
        let textView = PastingTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContentType = .none
        textView.isKeyboardSendEnabled = isKeyboardSendEnabled
        textView.onKeyboardSend = onKeyboardSend
        textView.pasteConfiguration = UIPasteConfiguration(
            acceptableTypeIdentifiers: [
                UTType.fileURL.identifier,
                UTType.image.identifier,
                UTType.text.identifier
            ]
        )
        textView.onPasteFileProviders = onPasteFileProviders
        textView.onPasteFileURLs = onPasteFileURLs
        textView.onPasteImageProviders = onPasteImageProviders
        textView.onPasteImages = onPasteImages
        context.coordinator.isHeightCapped = !noHeightCap
        context.coordinator.reportHeight(for: textView)
        return textView
    }

    func updateUIView(_ textView: PastingTextView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        if textView.text != text {
            textView.text = text
        }
        // Mirror the chat RTL toggle onto the text view itself (#259): SwiftUI's
        // layoutDirection environment does not propagate into a wrapped UITextView,
        // so set the base direction directly so the cursor/empty-field rests on the
        // trailing edge. `.natural` keeps the LTR default untouched, and per-run
        // bidi still resolves mixed Arabic+Latin/URL content within the line.
        let isRTL = context.environment.layoutDirection == .rightToLeft
        textView.semanticContentAttribute = isRTL ? .forceRightToLeft : .unspecified
        textView.textAlignment = isRTL ? .right : .natural
        textView.isEditable = !isDisabled
        textView.isSelectable = !isDisabled
        textView.textColor = isDisabled ? .secondaryLabel : .label
        textView.isKeyboardSendEnabled = isKeyboardSendEnabled
        textView.onKeyboardSend = onKeyboardSend
        textView.onPasteFileProviders = onPasteFileProviders
        textView.onPasteFileURLs = onPasteFileURLs
        textView.onPasteImageProviders = onPasteImageProviders
        textView.onPasteImages = onPasteImages
        context.coordinator.syncFocus(for: textView, shouldFocus: isFocused, isDisabled: isDisabled)
        context.coordinator.isHeightCapped = !noHeightCap
        context.coordinator.reportHeight(for: textView)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        var onHeightChange: (CGFloat) -> Void
        private var pendingFocusTarget: Bool?
        private var pendingFocusTask: Task<Void, Never>?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            _text = text
            _isFocused = isFocused
            self.onHeightChange = onHeightChange
        }

        func syncFocus(for textView: UITextView, shouldFocus: Bool, isDisabled: Bool) {
            if isDisabled, isFocused {
                Task { @MainActor [weak self] in
                    self?.isFocused = false
                }
            }

            let target = shouldFocus && !isDisabled
            guard textView.isFirstResponder != target else {
                // The live state already matches the request: a scheduled
                // focus/resign Task from an older snapshot is now obsolete,
                // so cancel it and disarm the pending marker together.
                pendingFocusTask?.cancel()
                pendingFocusTask = nil
                pendingFocusTarget = nil
                return
            }
            guard pendingFocusTarget != target else { return }

            pendingFocusTarget = target
            // True cancellation, not just a point-in-time re-check (raid-4
            // finding): a previously scheduled focus/resign Task must never
            // run after a newer decision replaces it — checking `isFocused`
            // at execution time leaves an interleave where a stale resign
            // evicts a fresh becomeFirstResponder between the re-check and
            // the call. Cancelling the old Task closes that window.
            pendingFocusTask?.cancel()
            let task = Task { @MainActor [weak self, weak textView] in
                await Task.yield()
                try? Task.checkCancellation()
                guard let self, let textView else { return }

                if target, textView.window == nil {
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
                try? Task.checkCancellation()

                self.pendingFocusTarget = nil
                if target {
                    guard self.isFocused, textView.isEditable, textView.window != nil else { return }
                    textView.becomeFirstResponder()
                } else if textView.isFirstResponder {
                    // Re-read the binding before evicting: a tap (or send-focus
                    // restore) may have re-requested keyboard focus after this
                    // resign was scheduled from a stale isFocused snapshot.
                    // Without this re-check SwiftUI sends false -> resign -> the
                    // keyboard drops right after rising on rapid transcript
                    // updates during streaming.
                    guard !self.isFocused else { return }
                    textView.resignFirstResponder()
                }
            }
            pendingFocusTask = task
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !isFocused {
                isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if isFocused {
                isFocused = false
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            reportHeight(for: textView)
        }

        func reportHeight(for textView: UITextView) {
            guard textView.bounds.width > 0 else { return }

            let fittingSize = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
            let height = ceil(textView.sizeThatFits(fittingSize).height)
            if isHeightCapped {
                onHeightChange(min(96, max(22, height)))
            } else {
                onHeightChange(max(22, height))
            }
        }

        /// Expanded-editor instances run uncapped — the editor scrolls inside
        /// the full-height card rather than growing the inline composer (#365).
        var isHeightCapped: Bool = true
    }

    final class PastingTextView: UITextView {
        var isKeyboardSendEnabled = false
        var onKeyboardSend: () -> Void = {}
        var onPasteFileProviders: ([NSItemProvider]) -> Void = { _ in }
        var onPasteFileURLs: ([URL]) -> Void = { _ in }
        var onPasteImageProviders: ([NSItemProvider]) -> Void = { _ in }
        var onPasteImages: ([UIImage]) -> Void = { _ in }

        func canPasteItemProviders(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                    || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
            }
        }

        func pasteItemProviders(_ itemProviders: [NSItemProvider]) {
            let fileProviders = itemProviders.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            }

            if fileProviders.isEmpty {
                let imageProviders = itemProviders.filter {
                    $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                }

                if imageProviders.isEmpty {
                    paste(nil)
                } else {
                    onPasteImageProviders(imageProviders)
                }
                return
            }

            onPasteFileProviders(fileProviders)
        }

        override var keyCommands: [UIKeyCommand]? {
            let sendCommand = UIKeyCommand(
                title: ComposerKeyboardCommand.title,
                action: #selector(sendMessageFromKeyboard),
                input: ComposerKeyboardCommand.input,
                modifierFlags: ComposerKeyboardCommand.modifierFlags
            )
            return (super.keyCommands ?? []) + [sendCommand]
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(sendMessageFromKeyboard) {
                return isKeyboardSendEnabled
            }

            if action == #selector(paste(_:)), hasPasteboardContent {
                return true
            }

            return super.canPerformAction(action, withSender: sender)
        }

        @objc private func sendMessageFromKeyboard() {
            guard isKeyboardSendEnabled else { return }
            onKeyboardSend()
        }

        override func paste(_ sender: Any?) {
            let fileProviders = pasteboardFileProviders

            if !fileProviders.isEmpty {
                onPasteFileProviders(fileProviders)
                return
            }

            let fileURLs = pasteboardFileURLs
            if !fileURLs.isEmpty {
                onPasteFileURLs(fileURLs)
                return
            }

            let imageProviders = pasteboardImageProviders
            if !imageProviders.isEmpty {
                onPasteImageProviders(imageProviders)
                return
            }

            let images = UIPasteboard.general.images ?? []
            if !images.isEmpty {
                onPasteImages(images)
                return
            }

            super.paste(sender)
        }

        private var hasPasteboardContent: Bool {
            let pasteboard = UIPasteboard.general
            return pasteboard.hasStrings
                || !pasteboardFileProviders.isEmpty
                || !pasteboardFileURLs.isEmpty
                || !pasteboardImageProviders.isEmpty
                || !(pasteboard.images?.isEmpty ?? true)
        }

        private var pasteboardFileProviders: [NSItemProvider] {
            UIPasteboard.general.itemProviders.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            }
        }

        private var pasteboardFileURLs: [URL] {
            UIPasteboard.general.urls?.filter(\.isFileURL) ?? []
        }

        private var pasteboardImageProviders: [NSItemProvider] {
            UIPasteboard.general.itemProviders.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            }
        }
    }
}

enum ComposerKeyboardCommand {
    static let title = String(localized: "Send Message")
    static let input = "\r"
    static let modifierFlags: UIKeyModifierFlags = .command
}
