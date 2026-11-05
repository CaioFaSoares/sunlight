import Foundation
import QuartzCore

/// A partial frame is a delta, not a replacement for a full frame. Keep the newest full checkpoint
/// until the worker takes it, even if camera ticks replace the latest delta while the Dock is busy.
/// Bounded to two frames; synchronization belongs to RealWindowDriver's lock.
struct LiveFrameMailbox {
    struct Frame {
        let frame: Data
        let shadow: Data?
        let full: Bool
        let at: CFTimeInterval
    }

    private var checkpoint: Frame?
    private var latest: Frame?

    mutating func submit(_ frame: Frame) {
        if frame.full { checkpoint = frame }
        latest = frame
    }

    mutating func take() -> [Frame] {
        defer { clear() }
        guard let latest else { return [] }
        if !latest.full, let checkpoint { return [checkpoint, latest] }
        return [latest]
    }

    mutating func clear() {
        checkpoint = nil
        latest = nil
    }
}
