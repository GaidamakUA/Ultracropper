import CoreGraphics
import XCTest
@testable import Ultracropper

@MainActor
final class PerspectiveGeometryTests: XCTestCase {
    func testCoordinatesValidationAndFilename() {
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        let quad = NormalizedQuad(
            topLeft: NormalizedPoint(x: 0.1, y: 0.2),
            topRight: NormalizedPoint(x: 0.9, y: 0.1),
            bottomRight: NormalizedPoint(x: 0.8, y: 0.9),
            bottomLeft: NormalizedPoint(x: 0.2, y: 0.8)
        )
        let imageQuad = PerspectiveGeometry.imageQuad(from: quad, extent: extent)

        XCTAssertEqual(imageQuad.topLeft, CGPoint(x: 20, y: 80))
        XCTAssertEqual(imageQuad.bottomRight, CGPoint(x: 160, y: 10))
        XCTAssertTrue(PerspectiveGeometry.isValid(quad))

        let crossed = NormalizedQuad(
            topLeft: NormalizedPoint(x: 0, y: 0),
            topRight: NormalizedPoint(x: 1, y: 1),
            bottomRight: NormalizedPoint(x: 1, y: 0),
            bottomLeft: NormalizedPoint(x: 0, y: 1)
        )
        XCTAssertFalse(PerspectiveGeometry.isValid(crossed))
        XCTAssertEqual(
            PerspectiveGeometry.outputFilename(for: URL(fileURLWithPath: "/tmp/scan.page.png")),
            "scan.page_fixed.jpg"
        )
    }
}
