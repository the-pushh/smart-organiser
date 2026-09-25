import XCTest
@testable import OrganiserCore

final class AccessibilityPermissionTests: XCTestCase {
    func testNoEnableButtonUntilDenialIsConfirmed() {
        XCTAssertFalse(AccessibilityPermission.checking.shouldOfferEnable)
        XCTAssertFalse(AccessibilityPermission.unavailable.shouldOfferEnable)
        XCTAssertFalse(AccessibilityPermission.granted.shouldOfferEnable)
        XCTAssertTrue(AccessibilityPermission.denied.shouldOfferEnable)
    }
    func testWorkingAccessibilityOverridesAStaleFalseTrustFlag() {
        let permission = AccessibilityPermission.resolve(trusted: false, probe: .accessible)
        XCTAssertEqual(permission, .granted)
        XCTAssertFalse(permission.shouldOfferEnable)
    }
    func testInconclusiveReadDoesNotPretendPermissionWasDenied() {
        XCTAssertEqual(AccessibilityPermission.resolve(trusted: false, probe: .inconclusive), .unavailable)
    }
    func testGrantedTrustDoesNotNeedAWindowToBeFocused() {
        XCTAssertEqual(AccessibilityPermission.resolve(trusted: true, probe: .inconclusive), .granted)
    }
    func testConfirmedDenialOffersEnable() {
        XCTAssertEqual(AccessibilityPermission.resolve(trusted: false, probe: .accessDenied), .denied)
    }
}
