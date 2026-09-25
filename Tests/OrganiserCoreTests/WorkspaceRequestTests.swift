import XCTest
@testable import OrganiserCore

final class WorkspaceRequestTests: XCTestCase {
    let rect = Rect(x: 0, y: 0, width: 1, height: 1)
    var workspace: Workspace {
        Workspace(displays: [], apps: [AppInfo(id: "com.spotify.client", name: "Spotify"), AppInfo(id: "com.apple.Music", name: "Music")], windows: [])
    }
    func request(_ workspace: Workspace) throws -> WorkspaceRequest {
        try WorkspaceRequest.make(task: "Write", setVibe: true, workspace: workspace)
    }
    func testVibeAcceptsEitherPlayerChosenByThePlanner() throws {
        let request = try request(workspace)
        XCTAssertEqual(request.musicAppIDs, ["com.spotify.client", "com.apple.Music"])
        XCTAssertThrowsError(try request.validateMusic(in: LayoutPlan(summary: "", actions: []), workspace: workspace))
        for id in request.musicAppIDs {
            let action = LayoutAction(kind: .launch, appID: id, displayID: "screen", rect: rect, reason: "Music")
            XCTAssertNoThrow(try request.validateMusic(in: LayoutPlan(summary: "", actions: [action]), workspace: workspace))
        }
    }
    func testAnExistingPlayerMustBeArrangedRatherThanMinimized() throws {
        var snapshot = workspace
        snapshot.windows = [WindowInfo(id: "music", appID: "com.apple.Music", appName: "Music", title: "Music", frame: rect, minimized: true)]
        let request = try request(snapshot)
        let arrange = LayoutAction(kind: .arrange, windowID: "music", displayID: "screen", rect: rect, reason: "Music nearby")
        XCTAssertNoThrow(try request.validateMusic(in: LayoutPlan(summary: "", actions: [arrange]), workspace: snapshot))
        let minimize = LayoutAction(kind: .minimize, windowID: "music", reason: "Hide")
        XCTAssertThrowsError(try request.validateMusic(in: LayoutPlan(summary: "", actions: [minimize]), workspace: snapshot))
    }
    func testNoVibeDoesNotRequireAnInstalledPlayer() throws {
        let empty = Workspace(displays: [], apps: [], windows: [])
        XCTAssertThrowsError(try request(empty))
        let plain = try WorkspaceRequest.make(task: "Read", setVibe: false, workspace: empty)
        XCTAssertTrue(plain.musicAppIDs.isEmpty)
    }
    func testOtherInstalledMusicPlayersAreEligibleButNonMusicAppsAreNot() throws {
        var snapshot = workspace
        snapshot.apps = [AppInfo(id: "tidal.player", name: "TIDAL"), AppInfo(id: "editor", name: "Code")]
        let request = try request(snapshot)
        XCTAssertEqual(request.musicAppIDs, ["tidal.player"])
        let unrelated = LayoutAction(kind: .launch, appID: "editor", displayID: "screen", rect: rect, reason: "Music")
        XCTAssertThrowsError(try request.validateMusic(in: LayoutPlan(summary: "", actions: [unrelated]), workspace: snapshot))
    }
}
