import Foundation

@main
struct KeyRoutingTests {
    static func main() {
        func key(_ code: Int, _ down: Bool, repeatKey: Bool = false) -> BrightnessKey {
            BrightnessKey(subtype: 8, data: code << 16 | (down ? 0x0a : 0x0b) << 8 | (repeatKey ? 1 : 0))!
        }
        assert(BrightnessKey(subtype: 8, data: 0 << 16 | 0x0a00) == nil) // Volume is untouched.
        assert(BrightnessKey(subtype: 7, data: 2 << 16 | 0x0a00) == nil)
        assert(BrightnessKey(subtype: 8, data: 2 << 16 | 0x0c00) == nil)
        var router = BrightnessKeyRouting()
        assert(router.route(key(2, true), externalTarget: 3).target == 3)
        assert(router.route(key(2, true, repeatKey: true), externalTarget: nil).target == 3)
        let externalUp = router.route(key(2, false), externalTarget: nil)
        assert(externalUp.consume && externalUp.target == nil)
        assert(!router.route(key(3, true), externalTarget: nil).consume)
        assert(!router.route(key(3, true, repeatKey: true), externalTarget: 3).consume)
        assert(!router.route(key(3, false), externalTarget: 3).consume)
        assert(router.route(key(3, true), externalTarget: 7).target == 7)
        assert(router.route(key(3, false), externalTarget: 3).consume)
        assert(router.route(key(3, true), externalTarget: 3).target == 3)
        assert(key(2, true).direction == 1 && key(3, true).direction == -1)
        assert(BrightnessKey(hardwareCode: 144, down: true)?.direction == 1)
        assert(BrightnessKey(hardwareCode: 145, down: false)?.down == false)
        assert(BrightnessKey(hardwareCode: 122, down: true) == nil) // Plain F1 remains a function key.
        print("Brightness-key routing passed: native/external isolation, repeats, releases, target changes, unrelated keys")
    }
}
