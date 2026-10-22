import AppKit
import ApplicationServices

struct BrightnessKey {
    let code: Int
    let down: Bool
    var direction: Double { code == 2 ? 1 : -1 }

    init?(hardwareCode: Int64, down: Bool) {
        guard hardwareCode == 144 || hardwareCode == 145 else { return nil }
        self.code = hardwareCode == 144 ? 2 : 3
        self.down = down
    }

    init?(subtype: Int16, data: Int) {
        let code = (data >> 16) & 0xffff
        let state = (data >> 8) & 0xff
        guard subtype == 8, (code == 2 || code == 3), (state == 0x0a || state == 0x0b) else { return nil }
        self.code = code
        down = state == 0x0a
    }
}

// A key gesture stays with the display where it began, including auto-repeat
// and release. Moving the pointer mid-hold must not brighten another display.
struct BrightnessKeyRouting {
    private var targets: [Int: UInt32] = [:]
    private var nativeKeys: Set<Int> = []
    mutating func route(_ key: BrightnessKey, externalTarget: UInt32?) -> (consume: Bool, target: UInt32?) {
        if !key.down {
            nativeKeys.remove(key.code)
            return (targets.removeValue(forKey: key.code) != nil, nil)
        }
        if let target = targets[key.code] { return (true, target) }
        if nativeKeys.contains(key.code) { return (false, nil) }
        if let target = externalTarget {
            targets[key.code] = target
            return (true, target)
        }
        nativeKeys.insert(key.code)
        return (false, nil)
    }
}

