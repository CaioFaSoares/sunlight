import AppKit
import XCTest
@testable import Canvas

final class WindowDiscoveryTests: XCTestCase {
    private func info(title: String? = nil, layer: Int = 0, alpha: Double = 1,
                      bounds: CGRect = CGRect(x: 40, y: 80, width: 900, height: 600)) -> WindowInfo {
        WindowInfo(id: 42, pid: 1234, layer: layer, bounds: bounds, title: title, alpha: alpha)
    }

    private func eligible(_ window: WindowInfo, bundleID: String? = "com.google.Chrome") -> Bool {
        WindowDiscovery.isApplicationWindow(window, ownPID: 9999, bundleID: bundleID, ownBundleID: "test.sunlight")
    }

    func testRedactedEmptyAndNormalTitlesHaveIdenticalEligibility() {
        XCTAssertTrue(eligible(info()))
        XCTAssertTrue(eligible(info(title: "")))
        XCTAssertTrue(eligible(info(title: "Synthetic window")))
        XCTAssertTrue(eligible(info(), bundleID: nil), "an app still launching has no bundle ID yet")
    }

    func testWindowsOnSecondaryDisplayWithNegativeOriginAreEligible() {
        XCTAssertTrue(eligible(info(bounds: CGRect(x: -1920, y: -1080, width: 900, height: 600))))
    }

    func testInvisibleOverlaysAndInvalidGeometryStayExcluded() {
        XCTAssertFalse(eligible(info(alpha: 0)))
        XCTAssertFalse(eligible(info(alpha: .nan)))
        XCTAssertFalse(eligible(info(layer: 3)))
        XCTAssertFalse(eligible(info(bounds: CGRect(x: 0, y: 0, width: 100, height: 50))))
        XCTAssertFalse(eligible(info(bounds: CGRect(x: CGFloat.infinity, y: 0, width: 900, height: 600))))
        XCTAssertFalse(eligible(info(), bundleID: "com.apple.dock"))
        XCTAssertFalse(eligible(info(), bundleID: "test.sunlight"))
    }

    func testRetryBackoffNeverPermanentlySuppressesMissingHandles() {
        var retry = WindowDiscovery.HandleRetry()
        XCTAssertTrue(retry.isDue(at: 0))
        var now: TimeInterval = 10
        for expected in [0.5, 1, 2, 4, 8, 16, 30, 30, 30] {
            retry.missed(at: now)
            XCTAssertEqual(retry.nextAttempt, now + expected)
            XCTAssertFalse(retry.isDue(at: retry.nextAttempt - 0.01))
            XCTAssertTrue(retry.isDue(at: retry.nextAttempt))
            now = retry.nextAttempt
        }
    }

    @MainActor
    func testMetadataProxyTracksWindowWithoutCapturePermissionOrHandle() {
        let source = info()
        let proxy = WindowProxy(info: source, camera: Camera(), scale: 1)
        XCTAssertEqual(proxy.windowID, source.id)
        XCTAssertEqual(proxy.pid, source.pid)
        XCTAssertEqual(proxy.lastRealFrame, source.bounds)
        XCTAssertNil(proxy.window)
        XCTAssertFalse(proxy.hasFrame)
        // No SCWindow means these calls cannot start a stream or use a private ID capture fallback.
        proxy.refresh()
        proxy.startCapture(level: WindowCapture.Level(factor: 1, fps: 30))
        XCTAssertFalse(proxy.isStreaming)
        proxy.stop()
    }
}

final class AXWindowMatchingTests: XCTestCase {
    private let frame = CGRect(x: 100, y: 100, width: 900, height: 600)

    func testExactIDWinsOverOverlappingGeometry() {
        XCTAssertEqual(AXWindow.matchingIndex(windowID: 42, approximateFrame: frame,
                                             ids: [41, 42], frames: [frame, frame]), 1)
    }

    func testKnownDifferentIDIsNeverFrameMatched() {
        XCTAssertNil(AXWindow.matchingIndex(windowID: 42, approximateFrame: frame,
                                            ids: [41], frames: [frame]))
    }

    func testOnlyOneUnknownIDCanUseFrameFallback() {
        XCTAssertEqual(AXWindow.matchingIndex(windowID: 42, approximateFrame: frame,
                                             ids: [41, nil], frames: [frame, frame]), 1)
        XCTAssertNil(AXWindow.matchingIndex(windowID: 42, approximateFrame: frame,
                                            ids: [nil, nil], frames: [frame, frame]))
    }

    func testMissingFramesBadInputAndZeroTargetAreRejected() {
        XCTAssertNil(AXWindow.matchingIndex(windowID: 42, approximateFrame: frame, ids: [nil], frames: [nil]))
        XCTAssertNil(AXWindow.matchingIndex(windowID: 42, approximateFrame: frame, ids: [nil], frames: []))
        XCTAssertNil(AXWindow.matchingIndex(windowID: 0, approximateFrame: frame, ids: [nil], frames: [frame]))
    }
}

final class WindowListParsingTests: XCTestCase {
    private func entry() -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: 42),
         kCGWindowOwnerPID as String: NSNumber(value: 1234),
         kCGWindowLayer as String: NSNumber(value: 0),
         kCGWindowBounds as String: ["X": -100.0, "Y": 80.0, "Width": 900.0, "Height": 600.0]]
    }

    func testRedactedTitleDoesNotPreventDiscovery() {
        let result = WindowList.info(entry())
        XCTAssertEqual(result?.id, 42)
        XCTAssertNil(result?.title)
        XCTAssertEqual(result?.bounds, CGRect(x: -100, y: 80, width: 900, height: 600))
        XCTAssertEqual(result?.alpha, 1)
    }

    func testEmptyTitleDoesNotPreventDiscovery() {
        var value = entry()
        value[kCGWindowName as String] = ""
        XCTAssertEqual(WindowList.info(value)?.title, "")
    }

    func testMalformedBoundsAreSkippedInsteadOfCrashing() {
        let invalidBounds: [Any] = ["redacted", 0, ["X": 0], NSNull()]
        for invalid in invalidBounds {
            var value = entry()
            value[kCGWindowBounds as String] = invalid
            XCTAssertNil(WindowList.info(value))
        }
    }

    func testMissingOwnerAndInvalidWindowIDAreSkipped() {
        var value = entry()
        value.removeValue(forKey: kCGWindowOwnerPID as String)
        XCTAssertNil(WindowList.info(value))
        value = entry()
        value[kCGWindowNumber as String] = NSNumber(value: 0)
        XCTAssertNil(WindowList.info(value))
    }
}
