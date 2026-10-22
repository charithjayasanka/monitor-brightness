import AppKit

func cursorDisplayID(at point: NSPoint, screens: [(id: UInt32, frame: NSRect)]) -> UInt32? {
    let matches = screens.filter { NSMouseInRect(point, $0.frame, false) }
    // Overlapping or mirrored bounds must not select an arbitrary monitor.
    return matches.count == 1 ? matches[0].id : nil
}
