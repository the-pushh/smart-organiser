import XCTest
@testable import SmartOrganiser

final class OnboardingStateTests: XCTestCase {
    @MainActor func testCompletedOnboardingIsNotShownWhilePermissionIsRechecked() {
        let suite = "organiser-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: OnboardingState.completionKey)
        let state = OnboardingState(defaults: defaults)
        XCTAssertTrue(state.completed)
        XCTAssertEqual(state.permission, .checking)
        XCTAssertFalse(state.needed, "A completed introduction must not replay while permissions are rechecked.")
    }
}

extension OnboardingStateTests {
    @MainActor func testLetsBeginPersistsAcrossRelaunches() {
        let suite = "organiser-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstLaunch = OnboardingState(defaults: defaults)
        XCTAssertTrue(firstLaunch.needed)
        firstLaunch.finish()
        XCTAssertFalse(firstLaunch.needed)
        let relaunched = OnboardingState(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(relaunched.completed)
        XCTAssertFalse(relaunched.needed)
    }
}
