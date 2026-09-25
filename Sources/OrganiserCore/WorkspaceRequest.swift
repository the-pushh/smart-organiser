import Foundation

public struct WorkspaceRequest {
    public let prompt: String
    public let musicAppIDs: Set<String>

    public static func make(task: String, setVibe: Bool, workspace: Workspace) throws -> WorkspaceRequest {
        guard setVibe else { return WorkspaceRequest(prompt: task, musicAppIDs: []) }
        let playerNames: Set<String> = ["music", "spotify", "tidal", "deezer", "amazon music", "youtube music",
            "qobuz", "doppler", "swinsian", "vox", "plexamp", "cider", "foobar2000", "audirvana", "nuclear"]
        let knownIDs: Set<String> = ["com.spotify.client", "com.apple.Music"]
        let players = workspace.apps.filter { knownIDs.contains($0.id) || playerNames.contains($0.name.lowercased()) }
        guard !players.isEmpty else { throw PlanError.invalid("No installed music player was found to open.") }
        let options = players.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        let prompt = """
        \(task)

        Set the vibe is enabled. Choose ONE suitable installed music app yourself from: \(options).
        Include a launch action for your chosen music app after the workspace reset.
        You may choose a player that is currently open; it will be reopened. Give it a comfortable supporting
        position on an available display. Keep the main task dominant. Do not ask the user to select an app,
        genre, or playlist. This request is to OPEN AND POSITION A MUSIC APP. Do not invent a genre or claim
        that music is playing, selected, or queued. Describe the actual app/window action, not music content.
        """
        return WorkspaceRequest(prompt: prompt, musicAppIDs: Set(players.map(\.id)))
    }
    public func validateMusic(in plan: LayoutPlan, workspace: Workspace) throws {
        guard !musicAppIDs.isEmpty else { return }
        let included = plan.actions.contains { action in
            if action.kind == .launch, let id = action.appID { return musicAppIDs.contains(id) }
            if action.kind == .arrange {
                return workspace.windows.contains { $0.id == action.windowID && musicAppIDs.contains($0.appID) }
            }
            return false
        }
        guard included else { throw PlanError.invalid("The layout omitted a music app. Try arranging again.") }
    }
}
