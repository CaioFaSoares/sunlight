import CoreGraphics
import XCTest
@testable import Canvas

final class LiftedWindowsTests: XCTestCase {
    func testOnlyAcceptedLiftsAreRemembered() {
        var lifted = LiftedWindows()
        lifted.record(41, sent: true)
        lifted.record(42, sent: false)
        XCTAssertEqual(lifted.ids, [41])
    }

    func testLoweringDropsAcceptedWindowsAndKeepsFailedOnesForTheNextReturn() {
        var lifted = LiftedWindows()
        lifted.record(41, sent: true)
        lifted.record(42, sent: true)
        lifted.record(43, sent: true)
        var asked: [CGWindowID] = []
        let lowered = lifted.lower { id in
            asked.append(id)
            return id != 42
        }
        XCTAssertEqual(lowered, 2)
        XCTAssertEqual(Set(asked), [41, 42, 43])
        XCTAssertEqual(lifted.ids, [42])
        // The failed window is tried again on the next return, not forgotten.
        XCTAssertEqual(lifted.lower { _ in true }, 1)
        XCTAssertTrue(lifted.ids.isEmpty)
    }

    func testForgetRemovesAWindowThatClosedBeforeItCouldBeLowered() {
        var lifted = LiftedWindows()
        lifted.record(41, sent: true)
        lifted.forget(41)
        XCTAssertTrue(lifted.ids.isEmpty)
        XCTAssertEqual(lifted.lower { _ in XCTFail("nothing to lower"); return true }, 0)
    }
}
