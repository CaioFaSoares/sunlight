import CoreGraphics

/// The windows this canvas lifted above itself to let an app show while the canvas is away. They have
/// to come back to the normal level before the listing can take them in; a lift whose request failed
/// isn't recorded, and a lower that fails stays for the next return.
struct LiftedWindows {
    private(set) var ids: Set<CGWindowID> = []

    mutating func record(_ id: CGWindowID, sent: Bool) {
        if sent { ids.insert(id) }
    }

    mutating func forget(_ id: CGWindowID) {
        ids.remove(id)
    }

    /// Lowers every known window, dropping the ones the add-on accepted. Returns how many were lowered.
    mutating func lower(using request: (CGWindowID) -> Bool) -> Int {
        var lowered = 0
        for id in Array(ids) where request(id) {
            ids.remove(id)
            lowered += 1
        }
        return lowered
    }
}
