import AppKit

@main
struct ScreenTargetTests {
    static func main() {
        let screens: [(id: UInt32, frame: NSRect)] = [
            (1, NSRect(x: 0, y: 0, width: 1440, height: 900)),
            (3, NSRect(x: -2560, y: 0, width: 2560, height: 1440)),
            (7, NSRect(x: 0, y: 900, width: 1920, height: 1080))
        ]
        assert(cursorDisplayID(at: NSPoint(x: 500, y: 500), screens: screens) == 1)
        assert(cursorDisplayID(at: NSPoint(x: -500, y: 500), screens: screens) == 3)
        assert(cursorDisplayID(at: NSPoint(x: 500, y: 1200), screens: screens) == 7)
        assert(cursorDisplayID(at: NSPoint(x: 4000, y: 500), screens: screens) == nil)
        assert(cursorDisplayID(at: .zero, screens: []) == nil)
        assert(cursorDisplayID(at: NSPoint(x: 500, y: 500), screens: screens + [screens[0]]) == nil)
        assert(cursorDisplayID(at: NSPoint(x: 0, y: 500), screens: screens) == 1)
        print("Cursor targeting passed: left/above layouts, boundaries, absent and ambiguous screens")
    }
}
