import Foundation

public enum WindowTiles {
    /// Fill the app's assigned region, including an incomplete last row.
    public static func rectangles(count: Int, in region: Rect) -> [Rect] {
        guard count > 0 else { return [] }
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = (count + columns - 1) / columns
        return (0..<count).map { index in
            let row = index / columns
            let cells = min(columns, count - row * columns)
            return Rect(x: Double(index % columns) / Double(cells),
                        y: Double(row) / Double(rows), width: 1 / Double(cells), height: 1 / Double(rows)).placed(in: region)
        }
    }
}
