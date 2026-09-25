import AppKit
import SwiftUI

@MainActor
final class PromptInputFocus {
    weak var field: PromptTextField?

    @discardableResult func focus() -> Bool {
        guard let field, field.isEditable, let window = field.window else { return false }
        let accepted = window.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
        return accepted
    }
}

final class PromptTextField: NSTextField {
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PromptInput: NSViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let focus: PromptInputFocus
    let submit: () -> Void
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> PromptTextField {
        let field = PromptTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.textColor = .labelColor
        field.placeholderString = "What are you planning to do?"
        field.setAccessibilityLabel("What are you planning to do?")
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        focus.field = field
        return field
    }
    func updateNSView(_ field: PromptTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.isEditable = enabled
        field.isSelectable = enabled
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PromptInput
        init(_ parent: PromptInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.insertNewline(_:)) { parent.submit(); return true }
            if command == #selector(NSResponder.cancelOperation(_:)) { parent.dismiss(); return true }
            return false
        }
    }
}
