import XCTest
import ApplicationServices
@testable import SmartOrganiser

final class DialogDetectionTests: XCTestCase {
    @MainActor func testElectronModalContentDoesNotPreserveNormalEditorWindow() {
        XCTAssertFalse(WindowController.isBlockingDialog(role: kAXWindowRole, subrole: kAXStandardWindowSubrole, modal: true))
        XCTAssertFalse(WindowController.isBlockingDialog(role: kAXWindowRole, subrole: kAXDialogSubrole, modal: false))
        XCTAssertFalse(WindowController.isBlockingDialog(role: "AXWebArea", subrole: kAXDialogSubrole, modal: true))
    }
    @MainActor func testNativeSheetsAndDialogWindowsRemainProtected() {
        XCTAssertTrue(WindowController.isBlockingDialog(role: kAXSheetRole, subrole: nil, modal: false))
        XCTAssertTrue(WindowController.isBlockingDialog(role: kAXWindowRole, subrole: kAXDialogSubrole, modal: true))
    }
}
