import XCTest
@testable import OrganiserCore

final class TaskWorkspaceTests: XCTestCase {
    let unit = Rect(x: 0, y: 0, width: 1, height: 1)
    var workspace: Workspace {
        Workspace(displays: [
            Display(id: "main", name: "Main", frame: unit, visibleFrame: unit),
            Display(id: "side", name: "Side", frame: unit, visibleFrame: unit)
        ], apps: [AppInfo(id: "browser", name: "Browser", supportsWebURLs: true),
                  AppInfo(id: "editor", name: "Editor"), AppInfo(id: "music", name: "Music")], windows: [])
    }
    func plan() -> LayoutPlan {
        LayoutPlan(summary: "Study", actions: [
            LayoutAction(kind: .launch, appID: "browser", urls: ["https://example.org/search?q=chord%20theory"], reason: "Reference"),
            LayoutAction(kind: .launch, appID: "music", reason: "Music"),
            LayoutAction(kind: .launch, appID: "editor", reason: "Notes")
        ], grids: [DisplayGrid(displayID: "main", rows: [
            .init(weight: 2, cells: [.init(appID: "editor", weight: 3), .init(appID: "browser", weight: 2)]),
            .init(weight: 1, cells: [.init(appID: "music", weight: 1)])
        ])])
    }
    func testWeightedGridFillsDisplayAndPreservesLaunchOrderAndURLs() throws {
        let result = try plan().resolvingGrid(for: workspace)
        XCTAssertEqual(result.actions.compactMap(\.appID), ["browser", "music", "editor"])
        let browser = try XCTUnwrap(result.actions[0].rect)
        let music = try XCTUnwrap(result.actions[1].rect)
        let editor = try XCTUnwrap(result.actions[2].rect)
        XCTAssertEqual(editor.x, 0)
        XCTAssertEqual(editor.width, 0.6, accuracy: 0.00001)
        XCTAssertEqual(browser.x, editor.width, accuracy: 0.00001)
        XCTAssertEqual(browser.x + browser.width, 1, accuracy: 0.00001)
        XCTAssertEqual(music.y, editor.height, accuracy: 0.00001)
        XCTAssertEqual(music.y + music.height, 1, accuracy: 0.00001)
        XCTAssertEqual(result.actions.compactMap(\.rect).reduce(0) { $0 + $1.width * $1.height }, 1, accuracy: 0.00001)
        XCTAssertEqual(result.actions[0].urls, plan().actions[0].urls)
    }
    func testSingleAppOnEachDisplayFillsBothDisplays() throws {
        var input = plan()
        input.actions.remove(at: 1)
        input.grids = [
            .init(displayID: "main", rows: [.init(weight: 1, cells: [.init(appID: "editor", weight: 1)])]),
            .init(displayID: "side", rows: [.init(weight: 1, cells: [.init(appID: "browser", weight: 1)])])
        ]
        let result = try input.resolvingGrid(for: workspace)
        XCTAssertEqual(result.actions[0].displayID, "side")
        XCTAssertEqual(result.actions[1].displayID, "main")
        XCTAssertEqual(result.actions.map(\.rect), [unit, unit])
    }
    func testGridRejectsDuplicateMissingAndCrampedCells() {
        var input = plan()
        input.grids![0].rows[0].cells[0].appID = "browser"
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
        input = plan(); input.grids![0].rows.removeLast()
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
        input = plan(); input.grids![0].rows[0].weight = 100
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
        input = plan(); input.grids![0].rows[0].weight = .infinity
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
    }
    func testURLValidationRejectsCommandsCredentialsAndMalformedAddresses() {
        for url in ["javascript:alert(1)", "file:///etc/passwd", "spotify:track:abc", "https://", "https://user:secret@example.com", "https://example.org/a b", "https://example.org/\n"] {
            XCTAssertThrowsError(try WebPage.validatedURL(url), url)
        }
        XCTAssertNoThrow(try WebPage.validatedURL("https://example.org/search?q=minor%20blues&key=A"))
    }
    func testOnlyKnownCurrentProjectCanBeOpened() throws {
        var snapshot = workspace
        snapshot.projectDirectory = "/workspace/current-repo"
        var input = plan()
        input.actions[2].projectPath = snapshot.projectDirectory
        XCTAssertNoThrow(try input.resolvingGrid(for: snapshot))
        input.actions[2].projectPath = "/private/other"
        XCTAssertThrowsError(try input.resolvingGrid(for: snapshot))
    }
    func testNewDocumentIntentSurvivesGridResolutionAndCoding() throws {
        var input = plan()
        input.actions[2].createNewDocument = true
        let decoded = try JSONDecoder().decode(LayoutPlan.self, from: JSONEncoder().encode(input))
        let resolved = try decoded.resolvingGrid(for: workspace)
        XCTAssertEqual(resolved.actions[2].createNewDocument, true)
    }
    func testNewDocumentCannotTargetBrowser() {
        var input = plan()
        input.actions[0].createNewDocument = true
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
    }
    func testBrowserRequiresARelevantPage() {
        var input = plan()
        input.actions[0].urls = nil
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
    }
    func testWebPagesCannotBeSentToANonBrowser() {
        var input = plan()
        input.actions[1].urls = ["https://example.org"]
        XCTAssertThrowsError(try input.resolvingGrid(for: workspace))
    }
    func testModelJSONDecodesAndResolvesWithoutRectangles() throws {
        let json = """
        {"summary":"Reference", "actions":[{"kind":"launch","appID":"browser","urls":["https://example.org"],"reason":"Reference"}],
        "grids":[{"displayID":"main","rows":[{"weight":1,"cells":[{"appID":"browser","weight":1}]}]}]}
        """
        let plan = try JSONDecoder().decode(LayoutPlan.self, from: Data(json.utf8)).resolvingGrid(for: workspace)
        XCTAssertEqual(plan.actions.first?.rect, unit)
    }
    @MainActor func testUnsafePageIsRejectedBeforeAnyWindowCloses() async {
        var input = plan()
        input.actions[0].urls = ["file:///tmp/local"]
        input.actions = input.actions.map {
            var action = $0; action.displayID = "main"; action.rect = unit; return action
        }
        var snapshot = workspace
        snapshot.windows = [.init(id: "old", appID: "editor", appName: "Editor", title: "", frame: unit, minimized: false)]
        do {
            _ = try await WorkspaceReset.run(plan: input, workspace: snapshot,
                closeWindow: { _ in XCTFail("Invalid URLs must not close any window") },
                openApp: { _ in XCTFail("Invalid URLs must not open anything") })
            XCTFail("Expected rejection")
        } catch {}
    }
}
