import XCTest
@testable import OrganiserCore

final class WorkspaceResetTests: XCTestCase {
    let rect = Rect(x: 0, y: 0, width: 1, height: 1)
    var workspace: Workspace {
        Workspace(displays: [Display(id: "screen", name: "Display", frame: rect, visibleFrame: rect)],
            apps: [AppInfo(id: "editor", name: "Editor"), AppInfo(id: "music", name: "Music")],
            windows: [WindowInfo(id: "one", appID: "editor", appName: "Editor", title: "Work", frame: rect, minimized: false),
                      WindowInfo(id: "two", appID: "music", appName: "Music", title: "Player", frame: rect, minimized: false)])
    }
    var plan: LayoutPlan {
        LayoutPlan(summary: "Write", actions: [LayoutAction(kind: .launch, appID: "editor", displayID: "screen", rect: rect, reason: "Write")])
    }
    @MainActor func testEveryWindowClosesBeforeAnySelectedAppOpens() async throws {
        var events: [String] = []
        let failures = try await WorkspaceReset.run(plan: plan, workspace: workspace, closeWindow: { window in
            events.append("close:" + window.id)
        }, openApp: { action in events.append("open:" + action.appID!) })
        XCTAssertEqual(events, ["close:one", "close:two", "open:editor"])
        XCTAssertTrue(failures.isEmpty)
    }
    @MainActor func testSavePromptPreservesAppButContinuesOtherClosuresAndLaunches() async throws {
        var events: [String] = []
        var snapshot = workspace
        snapshot.windows.insert(WindowInfo(id: "another-editor", appID: "editor", appName: "Editor",
            title: "Other document", frame: rect, minimized: false), at: 1)
        let setup = LayoutPlan(summary: "Work", actions: [
            LayoutAction(kind: .launch, appID: "editor", displayID: "screen", rect: rect, reason: ""),
            LayoutAction(kind: .launch, appID: "music", displayID: "screen", rect: rect, reason: "")])
        let warnings = try await WorkspaceReset.run(plan: setup, workspace: snapshot, closeWindow: { window in
            events.append("close:" + window.id)
            if window.id == "one" { throw PlanError.invalid("Save decision required") }
        }, openApp: { events.append("open:" + $0.appID!) })
        XCTAssertEqual(events, ["close:one", "close:two", "open:music"])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("Editor was left alone"))
    }
    @MainActor func testInvalidPlanCannotCloseWindows() async {
        var closed = false
        let invalid = LayoutPlan(summary: "", actions: [LayoutAction(kind: .launch, appID: "unknown", displayID: "screen", rect: rect, reason: "")])
        do {
            _ = try await WorkspaceReset.run(plan: invalid, workspace: workspace, closeWindow: { _ in closed = true }, openApp: { _ in XCTFail("Must not open") })
            XCTFail("Expected validation failure")
        } catch {}
        XCTAssertFalse(closed)
    }
    func testResetRejectsReuseActionsAndAcceptsAppsWithExistingWindows() throws {
        XCTAssertNoThrow(try plan.validatedForReset(for: workspace))
        let reuse = LayoutPlan(summary: "", actions: [LayoutAction(kind: .arrange, windowID: "one", displayID: "screen", rect: rect, reason: "")])
        XCTAssertThrowsError(try reuse.validatedForReset(for: workspace))
    }
    @MainActor func testCancellationDoesNotOpenAppsAfterClosingStops() async {
        do {
            _ = try await WorkspaceReset.run(plan: plan, workspace: workspace, closeWindow: { _ in throw CancellationError() }, openApp: { _ in XCTFail("Must not open") })
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
