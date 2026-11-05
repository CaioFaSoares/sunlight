import AppKit

/// Discovery is metadata, not permission to capture. In particular, an absent/empty title and a
/// missing ScreenCaptureKit handle do not mean a window has closed (including private browsers).
enum WindowDiscovery {
    static func isApplicationWindow(_ info: WindowInfo, ownPID: pid_t,
                                    bundleID: String?, ownBundleID: String?) -> Bool {
        info.id != 0 && info.pid > 0 && info.pid != ownPID && info.layer == 0
            && info.alpha.isFinite && info.alpha > 0
            && info.bounds.origin.x.isFinite && info.bounds.origin.y.isFinite
            && info.bounds.width.isFinite && info.bounds.height.isFinite
            && info.bounds.width >= 120 && info.bounds.height >= 80
            && (ownBundleID == nil || bundleID != ownBundleID) && !SystemUI.owns(bundleID)
    }

    /// Back off an unavailable SCK handle, but never turn a transient omission into a tombstone.
    /// The normal window-list reconciliation retries due handles; closing the window discards this.
    struct HandleRetry {
        private(set) var failures = 0
        private(set) var nextAttempt: TimeInterval = -.infinity

        mutating func missed(at now: TimeInterval) {
            failures = min(failures + 1, 7)
            nextAttempt = now + min(30, 0.5 * pow(2, Double(failures - 1)))
        }

        func isDue(at now: TimeInterval) -> Bool { now >= nextAttempt }
    }
}
