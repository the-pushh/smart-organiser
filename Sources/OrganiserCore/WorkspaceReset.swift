import Foundation

public extension LayoutPlan {
    func validatedForReset(for workspace: Workspace) throws -> LayoutPlan {
        guard actions.allSatisfy({ $0.kind == .launch }) else {
            throw PlanError.invalid("A fresh workspace must contain only app-opening actions.")
        }
        // Existing windows are closed by the controller, never by model-generated actions.
        let cleared = Workspace(displays: workspace.displays, apps: workspace.apps, windows: [], projectDirectory: workspace.projectDirectory)
        return try validated(for: cleared, allowClose: false)
    }
}

@MainActor
public enum WorkspaceReset {
    public static func run(plan: LayoutPlan, workspace: Workspace,
                           closeWindow: (WindowInfo) async throws -> Void,
                           openApp: (LayoutAction) async throws -> Void) async throws -> [String] {
        _ = try plan.validatedForReset(for: workspace)
        var failures: [String] = []
        var preservedApps = Set<String>()
        for window in workspace.windows {
            try Task.checkCancellation()
            guard !preservedApps.contains(window.appID) else { continue }
            do { try await closeWindow(window) }
            catch is CancellationError { throw CancellationError() }
            catch {
                preservedApps.insert(window.appID)
                failures.append("\(window.appName) was left alone: \(error.localizedDescription)")
            }
        }
        for action in plan.actions {
            try Task.checkCancellation()
            // Do not reopen, move, or create documents in an app awaiting a decision.
            if let id = action.appID, preservedApps.contains(id) { continue }
            do { try await openApp(action) }
            catch is CancellationError { throw CancellationError() }
            catch {
                let name = workspace.apps.first { $0.id == action.appID }?.name ?? "App"
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return failures
    }
}
