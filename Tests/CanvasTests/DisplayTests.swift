import XCTest
import CoreGraphics
@testable import Canvas

final class DisplayTests: XCTestCase {
    private func display(_ frame: CGRect, visible: CGRect? = nil) -> Display {
        Display(id: 1, uuid: "u", name: "d", frame: frame, visible: visible ?? frame, cocoaFrame: frame, scale: 2)
    }

    func testQuartzFlipsAroundThePrimaryHeight() {
        // A 1920×1080 display above a 1512×982 primary, its left edge 200 pt in.
        let above = Display.quartz(CGRect(x: 200, y: 982, width: 1920, height: 1080), primaryHeight: 982)
        XCTAssertEqual(above, CGRect(x: 200, y: -1080, width: 1920, height: 1080))
        let primary = Display.quartz(CGRect(x: 0, y: 0, width: 1512, height: 982), primaryHeight: 982)
        XCTAssertEqual(primary, CGRect(x: 0, y: 0, width: 1512, height: 982))
    }

    func testVisibleInViewAndTopInset() {
        let d = display(CGRect(x: 1512, y: -200, width: 2560, height: 1440),
                        visible: CGRect(x: 1512, y: -175, width: 2560, height: 1415))
        XCTAssertEqual(d.visibleInView, CGRect(x: 0, y: 25, width: 2560, height: 1415))
        XCTAssertEqual(d.topInset, 25)
    }

    func testIndexPicksTheCentreThenTheOverlapThenTheNearest() {
        let displays = [display(CGRect(x: 0, y: 0, width: 1000, height: 800)),
                        display(CGRect(x: 1000, y: 0, width: 1000, height: 800))]
        XCTAssertEqual(Display.index(for: CGRect(x: 900, y: 100, width: 400, height: 300), in: displays), 1)
        XCTAssertEqual(Display.index(for: CGRect(x: 700, y: 100, width: 400, height: 300), in: displays), 0)
        // Centre below both, mostly over the second.
        XCTAssertEqual(Display.index(for: CGRect(x: 1100, y: 700, width: 400, height: 300), in: displays), 1)
        // Nowhere near either: the nearest.
        XCTAssertEqual(Display.index(for: CGPoint(x: 2500, y: 400), in: displays), 1)
        XCTAssertNil(Display.index(for: CGPoint.zero, in: []))
    }

    func testGlobalCameraMapsTheViewToGlobalPoints() {
        let o = CGPoint(x: 1512, y: -200)
        let view = Camera(origin: CGPoint(x: 300, y: 50), zoom: 0.5)
        let global = view.global(viewOrigin: o)
        let world = CGPoint(x: 900, y: 650)
        let inView = view.toScreen(world)
        let inGlobal = global.toScreen(world)
        XCTAssertEqual(inGlobal.x, inView.x + o.x, accuracy: 1e-9)
        XCTAssertEqual(inGlobal.y, inView.y + o.y, accuracy: 1e-9)
        XCTAssertEqual(global.toWorld(inGlobal).x, world.x, accuracy: 1e-9)
    }

    /// A released window is put wholly on its canvas's display (fork #10): one drawn over another
    /// screen comes back beside the edge it went off, its title bar under the menu bar.
    func testConfinedPutsAWindowBackOnItsDisplay() {
        let display = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let inside = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(CanvasController.confined(inside, in: display, top: 25), inside.origin)
        // Entirely past the right edge, on the other display: its right edge comes to this one.
        let over = CGRect(x: 2570, y: 316, width: 2274, height: 908)
        XCTAssertEqual(CanvasController.confined(over, in: display, top: 25), CGPoint(x: 286, y: 316))
        // Wider than the display: its top-left sits at the display's.
        let wide = CGRect(x: 3000, y: 200, width: 3000, height: 900)
        XCTAssertEqual(CanvasController.confined(wide, in: display, top: 25), CGPoint(x: 0, y: 200))
        // Above the top edge: under the menu bar.
        let high = CGRect(x: 100, y: -300, width: 400, height: 300)
        XCTAssertEqual(CanvasController.confined(high, in: display, top: 25), CGPoint(x: 100, y: 25))
        // Below the bottom edge.
        let low = CGRect(x: 100, y: 1500, width: 400, height: 300)
        XCTAssertEqual(CanvasController.confined(low, in: display, top: 25), CGPoint(x: 100, y: 1140))
    }

    func testHomeCameraShowsTheDisplayAtOneToOne() {
        let o = CGPoint(x: -1920, y: 0)
        let home = Camera.home(viewOrigin: o)
        // A window at global (-1800, 100) sits at view (120, 100), and its world rect is where it is.
        XCTAssertEqual(home.toScreen(CGPoint(x: -1800, y: 100)), CGPoint(x: 120, y: 100))
        XCTAssertEqual(home.global(viewOrigin: o).toScreen(CGPoint(x: -1800, y: 100)), CGPoint(x: -1800, y: 100))
    }
}
