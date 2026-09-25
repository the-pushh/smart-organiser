import Foundation

/// The agent chooses rows, proportions and app assignments. Geometry is computed
/// locally so rounding or model arithmetic cannot leave holes or overlap cells.
public struct DisplayGrid: Codable, Sendable {
    public struct Cell: Codable, Sendable {
        public var appID: String
        public var weight: Double
        public init(appID: String, weight: Double) { self.appID = appID; self.weight = weight }
    }
    public struct Row: Codable, Sendable {
        public var weight: Double
        public var cells: [Cell]
        public init(weight: Double, cells: [Cell]) { self.weight = weight; self.cells = cells }
    }
    public var displayID: String
    public var rows: [Row]
    public init(displayID: String, rows: [Row]) { self.displayID = displayID; self.rows = rows }
}

public extension LayoutPlan {
    func resolvingGrid(for workspace: Workspace) throws -> LayoutPlan {
        guard !actions.isEmpty, actions.count <= 12 else { throw PlanError.invalid("Expected 1–12 apps.") }
        for action in actions where workspace.apps.contains(where: { $0.id == action.appID && $0.supportsWebURLs == true }) {
            guard let urls = action.urls, !urls.isEmpty else {
                throw PlanError.invalid("The browser plan needs a relevant web page. Try arranging again.")
            }
        }
        guard let grids, !grids.isEmpty, grids.count <= workspace.displays.count else {
            throw PlanError.invalid("The plan needs a grid for each display it uses.")
        }
        var placements: [String: (String, Rect)] = [:]
        var screens = Set<String>()
        func validWeights(_ weights: [Double]) -> Bool {
            !weights.isEmpty && weights.count <= 12 && weights.allSatisfy { $0.isFinite && $0 > 0 }
                && weights.reduce(0, +).isFinite
        }
        for grid in grids {
            guard workspace.displays.contains(where: { $0.id == grid.displayID }),
                  screens.insert(grid.displayID).inserted, validWeights(grid.rows.map(\.weight)) else {
                throw PlanError.invalid("The layout contains an invalid display grid.")
            }
            let totalHeight = grid.rows.map(\.weight).reduce(0, +)
            var y = 0.0
            for row in grid.rows {
                guard validWeights(row.cells.map(\.weight)) else { throw PlanError.invalid("Invalid grid proportions.") }
                let height = row.weight / totalHeight
                let totalWidth = row.cells.map(\.weight).reduce(0, +)
                var x = 0.0
                for cell in row.cells {
                    let width = cell.weight / totalWidth
                    let rect = Rect(x: x, y: y, width: width, height: height)
                    guard rect.isUnitRect, placements[cell.appID] == nil else {
                        throw PlanError.invalid("Grid cells are too small or repeat an app.")
                    }
                    placements[cell.appID] = (grid.displayID, rect)
                    x += width
                }
                y += height
            }
        }
        guard placements.count == actions.count else { throw PlanError.invalid("Every selected app needs exactly one grid cell.") }
        var resolved = self
        resolved.actions = try actions.map { action in
            guard let id = action.appID, let (screen, rect) = placements[id] else {
                throw PlanError.invalid("A selected app is missing from the grid.")
            }
            var placed = action
            placed.displayID = screen
            placed.rect = rect
            return placed
        }
        // Keep a single resolved geometry source for execution and revalidation.
        resolved.grids = nil
        return try resolved.validatedForReset(for: workspace)
    }
}
