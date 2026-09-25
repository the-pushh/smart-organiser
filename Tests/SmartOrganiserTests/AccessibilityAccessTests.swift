import XCTest
import ApplicationServices
import OrganiserCore
@testable import SmartOrganiser

final class AccessibilityAccessTests: XCTestCase {
    func testOwnProcessCannotProvePermissionToControlOtherApps() {
        var read = false
        let probe = AccessibilityAccess.probe(processID: 42, ownProcessID: 42) {
            read = true
            return .success
        }
        XCTAssertFalse(read)
        XCTAssertEqual(AccessibilityPermission.resolve(trusted: false, probe: probe), .unavailable)
    }

    func testExternalProcessDenialIsPreserved() {
        let probe = AccessibilityAccess.probe(processID: 43, ownProcessID: 42) { .apiDisabled }
        XCTAssertEqual(AccessibilityPermission.resolve(trusted: false, probe: probe), .denied)
    }
}
