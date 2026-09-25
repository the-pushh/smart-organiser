import XCTest
@testable import OrganiserCore

final class WindowModeTransitionTests: XCTestCase {
    @MainActor func testArrangeExitsFullScreenAndWaitsBeforeReturning() async throws {
        var fullScreen = true
        var writes: [Bool] = []
        var waits = 0
        try await WindowModeTransition.setFullScreen(false, read: { fullScreen }, write: { writes.append($0) }, pause: { _ in
            waits += 1
            if waits == 3 { fullScreen = false }
        })
        XCTAssertEqual(writes, [false])
        XCTAssertFalse(fullScreen)
        XCTAssertGreaterThanOrEqual(waits, 3)
    }
}

extension WindowModeTransitionTests {
    @MainActor func testNormalWindowsAreNotToggled() async throws {
        try await WindowModeTransition.setFullScreen(false, read: { false }, write: { _ in XCTFail("Unexpected toggle") }, pause: { _ in XCTFail("Unexpected wait") })
        try await WindowModeTransition.setFullScreen(false, read: { nil }, write: { _ in XCTFail("Unexpected toggle") }, pause: { _ in XCTFail("Unexpected wait") })
    }
    @MainActor func testUndoCanRestoreFullScreen() async throws {
        var state = false
        var waits = 0
        try await WindowModeTransition.setFullScreen(true, read: { state }, write: { state = $0 }, pause: { _ in waits += 1 })
        XCTAssertTrue(state)
        XCTAssertGreaterThanOrEqual(waits, 2)
    }
    @MainActor func testAStuckTransitionReportsFailureInsteadOfPretendingItMoved() async {
        var writes = 0
        do {
            try await WindowModeTransition.setFullScreen(false, read: { true }, write: { _ in writes += 1 }, pause: { _ in })
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("did not finish leaving")) }
        XCTAssertEqual(writes, 1)
    }
    @MainActor func testRefusedTransitionPropagatesAndDoesNotWait() async {
        do {
            try await WindowModeTransition.setFullScreen(false, read: { true }, write: { _ in throw PlanError.invalid("Refused") }, pause: { _ in XCTFail("Should not poll after refusal") })
            XCTFail("Expected refusal")
        } catch { XCTAssertEqual(error.localizedDescription, "Refused") }
    }
    @MainActor func testCancellationDuringTransitionStopsFurtherWork() async {
        do {
            try await WindowModeTransition.setFullScreen(false, read: { true }, write: { _ in }, pause: { _ in throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
