import Foundation

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func placed(in screen: Rect) -> Rect {
        Rect(x: screen.x + x * screen.width, y: screen.y + y * screen.height,
             width: width * screen.width, height: height * screen.height)
    }
    public var isUnitRect: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 &&
        width >= 0.1 && height >= 0.1 && x + width <= 1.001 && y + height <= 1.001
    }
}

public struct Display: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var frame: Rect
    public var visibleFrame: Rect
    public init(id: String, name: String, frame: Rect, visibleFrame: Rect) {
        self.id = id; self.name = name; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

public struct AppInfo: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var supportsWebURLs: Bool?
    public init(id: String, name: String, supportsWebURLs: Bool = false) {
        self.id = id; self.name = name; self.supportsWebURLs = supportsWebURLs
    }
}

public struct WindowInfo: Codable, Identifiable, Sendable {
    public var id: String
    public var appID: String
    public var appName: String
    public var title: String
    public var frame: Rect
    public var minimized: Bool
    public init(id: String, appID: String, appName: String, title: String, frame: Rect, minimized: Bool) {
        self.id = id; self.appID = appID; self.appName = appName; self.title = title
        self.frame = frame; self.minimized = minimized
    }
}

public struct Workspace: Codable, Sendable {
    public var displays: [Display]
    public var apps: [AppInfo]
    public var windows: [WindowInfo]
    public var projectDirectory: String?
    public init(displays: [Display], apps: [AppInfo], windows: [WindowInfo], projectDirectory: String? = nil) {
        self.displays = displays; self.apps = apps; self.windows = windows; self.projectDirectory = projectDirectory
    }
}

public enum ActionKind: String, Codable, Sendable { case arrange, launch, minimize, close }
public struct LayoutAction: Codable, Identifiable, Sendable {
    public var kind: ActionKind
    public var windowID: String?
    public var appID: String?
    public var displayID: String?
    public var rect: Rect?
    public var urls: [String]?
    public var createNewDocument: Bool?
    public var projectPath: String?
    public var reason: String
    public var id: String { "\(kind.rawValue):\(windowID ?? appID ?? "")" }
    public init(kind: ActionKind, windowID: String? = nil, appID: String? = nil,
                displayID: String? = nil, rect: Rect? = nil, urls: [String]? = nil, createNewDocument: Bool? = nil, projectPath: String? = nil, reason: String) {
        self.kind = kind; self.windowID = windowID; self.appID = appID
        self.displayID = displayID; self.rect = rect; self.urls = urls; self.createNewDocument = createNewDocument; self.projectPath = projectPath; self.reason = reason
    }
}
public struct LayoutPlan: Codable, Sendable {
    public var summary: String
    public var actions: [LayoutAction]
    public var grids: [DisplayGrid]?
    public init(summary: String, actions: [LayoutAction], grids: [DisplayGrid]? = nil) {
        self.summary = summary; self.actions = actions; self.grids = grids
    }
    public func validated(for workspace: Workspace, allowClose: Bool) throws -> LayoutPlan {
        guard !actions.isEmpty, actions.count <= 40 else { throw PlanError.invalid("Expected 1–40 actions.") }
        var targets = Set<String>()
        for action in actions {
            if let path = action.projectPath {
                guard action.kind == .launch, path == workspace.projectDirectory, path.hasPrefix("/"),
                      action.urls == nil, action.createNewDocument != true,
                      !workspace.apps.contains(where: { $0.id == action.appID && $0.supportsWebURLs == true }) else {
                    throw PlanError.invalid("Only the current project directory can be opened in a project app.")
                }
            }
            if action.createNewDocument == true {
                guard action.kind == .launch, action.urls == nil,
                      !workspace.apps.contains(where: { $0.id == action.appID && $0.supportsWebURLs == true }) else {
                    throw PlanError.invalid("New documents must target a document app, not a browser.")
                }
            }
            if let pages = action.urls {
                guard action.kind == .launch, !pages.isEmpty, pages.count <= 8,
                      workspace.apps.contains(where: { $0.id == action.appID && $0.supportsWebURLs == true }) else {
                    throw PlanError.invalid("Web pages must target an installed browser (up to eight pages).")
                }
                for page in pages { _ = try WebPage.validatedURL(page) }
            }
            if action.kind == .launch {
                guard let id = action.appID, workspace.apps.contains(where: { $0.id == id }), action.windowID == nil else {
                    throw PlanError.invalid("The plan refers to an unknown app.")
                }
                // Never guess which existing window to reuse for a launch.
                guard !workspace.windows.contains(where: { $0.appID == id }) else {
                    throw PlanError.invalid("The plan should arrange the app’s existing window.")
                }
                guard targets.insert("app:" + id).inserted else { throw PlanError.invalid("Duplicate app action.") }
            } else {
                guard let id = action.windowID, workspace.windows.contains(where: { $0.id == id }) else {
                    throw PlanError.invalid("The plan refers to a window that was not captured.")
                }
                guard targets.insert("window:" + id).inserted else { throw PlanError.invalid("Conflicting window actions.") }
            }
            if action.kind == .close && !allowClose { throw PlanError.invalid("Closing windows is disabled.") }
            if action.kind == .arrange || action.kind == .launch {
                guard let id = action.displayID, workspace.displays.contains(where: { $0.id == id }),
                      let rect = action.rect, rect.isUnitRect else {
                    throw PlanError.invalid("The proposed position is outside an available display.")
                }
            }
        }
        return self
    }
}
public enum PlanError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
