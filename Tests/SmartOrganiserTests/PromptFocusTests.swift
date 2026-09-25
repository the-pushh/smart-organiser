import AppKit
import XCTest
@testable import SmartOrganiser

final class PromptFocusTests: XCTestCase {
    @MainActor func testPromptUsesAnActivatingKeyboardWindow() {
        _ = NSApplication.shared
        let panel = LauncherPanel.makeForPrompt()
        defer { panel.close() }
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel), "The summoned prompt must activate instead of leaving keyboard input in the background app.")
    }
}

extension PromptFocusTests {
    @MainActor func testFocusInstallsTheTextFieldEditorAndAcceptsTyping() {
        _ = NSApplication.shared
        let panel = LauncherPanel.makeForPrompt()
        defer { panel.close() }
        let field = PromptTextField(frame: NSRect(x: 20, y: 20, width: 420, height: 25))
        field.isEditable = true
        panel.contentView = field
        let focus = PromptInputFocus()
        focus.field = field
        XCTAssertTrue(focus.focus())
        guard let editor = field.currentEditor() as? NSTextView else { return XCTFail("No keyboard editor attached") }
        XCTAssertTrue(panel.firstResponder === editor)
        editor.insertText("Plan my writing session", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.string, "Plan my writing session")
    }
}
