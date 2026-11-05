import XCTest
@testable import Canvas

final class LiveFrameMailboxTests: XCTestCase {
    private func frame(_ value: UInt8, full: Bool) -> LiveFrameMailbox.Frame {
        .init(frame: Data([value]), shadow: nil, full: full, at: Double(value))
    }

    func testFullFrameIsNotLostBehindCameraDeltas() {
        var mailbox = LiveFrameMailbox()
        mailbox.submit(frame(1, full: true))
        for n in UInt8(2)...100 { mailbox.submit(frame(n, full: false)) }
        let batch = mailbox.take()
        XCTAssertEqual(batch.map(\.frame), [Data([1]), Data([100])])
        XCTAssertEqual(batch.map(\.full), [true, false])
        XCTAssertTrue(mailbox.take().isEmpty)
    }

    func testNewestFullFrameSupersedesOldCheckpointAndDeltas() {
        var mailbox = LiveFrameMailbox()
        mailbox.submit(frame(1, full: true))
        mailbox.submit(frame(2, full: false))
        mailbox.submit(frame(3, full: true))
        XCTAssertEqual(mailbox.take().map(\.frame), [Data([3])])
    }

    func testLeavingThenReturningWindowPreservesMembershipChange() {
        var mailbox = LiveFrameMailbox()
        // Full frames change which windows the Dock leases, and park/wake state; deltas do neither.
        mailbox.submit(frame(1, full: true))
        _ = mailbox.take()
        mailbox.submit(frame(2, full: true))
        mailbox.submit(frame(3, full: false))
        mailbox.submit(frame(4, full: true))
        mailbox.submit(frame(5, full: false))
        XCTAssertEqual(mailbox.take().map(\.frame), [Data([4]), Data([5])])
    }

    func testRestoreDiscardsBothCheckpointAndDelta() {
        var mailbox = LiveFrameMailbox()
        mailbox.submit(frame(1, full: true))
        mailbox.submit(frame(2, full: false))
        mailbox.clear()
        XCTAssertTrue(mailbox.take().isEmpty)
        mailbox.submit(frame(3, full: true))
        XCTAssertEqual(mailbox.take().map(\.frame), [Data([3])])
    }

    func testDeltasAloneRemainLatestOnly() {
        var mailbox = LiveFrameMailbox()
        mailbox.submit(frame(1, full: false))
        mailbox.submit(frame(2, full: false))
        XCTAssertEqual(mailbox.take().map(\.frame), [Data([2])])
    }
}
