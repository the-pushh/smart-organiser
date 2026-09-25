import XCTest
@testable import OrganiserCore

final class WorkspaceTests: XCTestCase {
    let rect = Rect(x: 0, y: 0, width: 0.5, height: 1)
    var workspace: Workspace {
        Workspace(displays: [Display(id: "left", name: "External", frame: Rect(x: -1920, y: -300, width: 1920, height: 1080),
            visibleFrame: Rect(x: -1920, y: -275, width: 1920, height: 1000))],
            apps: [AppInfo(id: "editor", name: "Editor"), AppInfo(id: "notes", name: "Notes")],
            windows: [WindowInfo(id: "one", appID: "editor", appName: "Editor", title: "Work", frame: Rect(x: 0, y: 0, width: 800, height: 600), minimized: false)])
    }
    func arrange(_ id: String = "one") -> LayoutAction {
        LayoutAction(kind: .arrange, windowID: id, displayID: "left", rect: rect, reason: "Editor left")
    }
    func testCoordinatesRespectNegativeDisplayOriginsAndUsableArea() {
        XCTAssertEqual(rect.placed(in: workspace.displays[0].visibleFrame), Rect(x: -1920, y: -275, width: 960, height: 1000))
    }
    func testAcceptsCapturedWindowAndInstalledLaunch() throws {
        let plan = LayoutPlan(summary: "Work", actions: [arrange(), LayoutAction(kind: .launch, appID: "notes", displayID: "left", rect: Rect(x: 0.5, y: 0, width: 0.5, height: 1), reason: "Notes right")])
        XCTAssertEqual(try plan.validated(for: workspace, allowClose: false).actions.count, 2)
    }
    func testRejectsStaleWindowAndUnknownDisplay() {
        XCTAssertThrowsError(try LayoutPlan(summary: "", actions: [arrange("stale")]).validated(for: workspace, allowClose: false))
        var action = arrange(); action.displayID = "unplugged"
        XCTAssertThrowsError(try LayoutPlan(summary: "", actions: [action]).validated(for: workspace, allowClose: false))
    }
    func testCloseRequiresExplicitOption() throws {
        let plan = LayoutPlan(summary: "", actions: [LayoutAction(kind: .close, windowID: "one", reason: "Close")])
        XCTAssertThrowsError(try plan.validated(for: workspace, allowClose: false))
        XCTAssertEqual(try plan.validated(for: workspace, allowClose: true).actions.count, 1)
    }
    func testRejectsOffscreenNonfiniteAndTinyRectangles() {
        for rect in [Rect(x: -0.1, y: 0, width: 0.5, height: 1), Rect(x: 0.8, y: 0, width: 0.5, height: 1),
                     Rect(x: 0, y: 0, width: .infinity, height: 1), Rect(x: .nan, y: 0, width: 1, height: 1),
                     Rect(x: 0, y: 0, width: 0.01, height: 1)] {
            var action = arrange(); action.rect = rect
            XCTAssertThrowsError(try LayoutPlan(summary: "", actions: [action]).validated(for: workspace, allowClose: false))
        }
    }
    func testRejectsConflictingActions() {
        let plan = LayoutPlan(summary: "", actions: [arrange(), LayoutAction(kind: .minimize, windowID: "one", reason: "Hide")])
        XCTAssertThrowsError(try plan.validated(for: workspace, allowClose: false))
    }
    func testCannotLaunchUnlistedAppOrGuessAnExistingWindow() {
        for id in ["unknown", "editor"] {
            let action = LayoutAction(kind: .launch, appID: id, displayID: "left", rect: rect, reason: "Launch")
            XCTAssertThrowsError(try LayoutPlan(summary: "", actions: [action]).validated(for: workspace, allowClose: false))
        }
    }
    func testRejectsEmptyAndOversizedPlans() {
        for actions in [[], Array(repeating: arrange(), count: 41)] {
            XCTAssertThrowsError(try LayoutPlan(summary: "", actions: actions).validated(for: workspace, allowClose: false))
        }
    }
    func testJSONContractDecodesAndRejectsUnsupportedActions() throws {
        let json = #"{"summary":"Focus","actions":[{"kind":"arrange","windowID":"one","displayID":"left","rect":{"x":0,"y":0,"width":1,"height":1},"reason":"Work"}]}"#
        let plan = try JSONDecoder().decode(LayoutPlan.self, from: Data(json.utf8))
        XCTAssertEqual(try plan.validated(for: workspace, allowClose: false).summary, "Focus")
        XCTAssertThrowsError(try JSONDecoder().decode(LayoutPlan.self, from: Data(json.replacingOccurrences(of: "arrange", with: "shell").utf8)))
    }
}
