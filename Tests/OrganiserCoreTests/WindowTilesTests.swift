import XCTest
@testable import OrganiserCore

final class WindowTilesTests: XCTestCase {
    func testFourBrowserWindowsOccupyFourQuadrantsOfAssignedRegion() {
        let result = WindowTiles.rectangles(count: 4, in: Rect(x: -1200, y: 30, width: 1200, height: 800))
        XCTAssertEqual(result, [Rect(x: -1200, y: 30, width: 600, height: 400),
                                Rect(x: -600, y: 30, width: 600, height: 400),
                                Rect(x: -1200, y: 430, width: 600, height: 400),
                                Rect(x: -600, y: 430, width: 600, height: 400)])
    }
    func testOddWindowCountsFillRegionWithoutOverlapping() {
        let region = Rect(x: 0, y: 0, width: 1000, height: 800)
        for count in [1, 3, 5, 7] {
            let tiles = WindowTiles.rectangles(count: count, in: region)
            XCTAssertEqual(tiles.count, count)
            XCTAssertEqual(tiles.reduce(0) { $0 + $1.width * $1.height }, 800000, accuracy: 0.001)
            for i in tiles.indices {
                for j in tiles.indices where j > i {
                    let a = tiles[i], b = tiles[j]
                    let overlap = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x)) *
                        max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
                    XCTAssertEqual(overlap, 0, accuracy: 0.001)
                }
            }
        }
    }
}
