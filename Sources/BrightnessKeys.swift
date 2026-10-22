import AppKit
import ApplicationServices

final class BrightnessKeys {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var routing = BrightnessKeyRouting()
    var adjust: ((UInt32, Double) -> Void)?
    var running: Bool { tap != nil }

    func start(prompt: Bool = false) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        let mask = (CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let handler = Unmanaged<BrightnessKeys>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                handler.routing = BrightnessKeyRouting()
                if let tap = handler.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let nsEvent = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
            let decoded: BrightnessKey?
            if type == .keyDown || type == .keyUp {
                decoded = BrightnessKey(hardwareCode: event.getIntegerValueField(.keyboardEventKeycode), down: type == .keyDown)
            } else if nsEvent.type == .systemDefined {
                decoded = BrightnessKey(subtype: nsEvent.subtype.rawValue, data: nsEvent.data1)
            } else { decoded = nil }
            guard let key = decoded else {
                return Unmanaged.passUnretained(event)
            }
            let id = screenID(screenUnderCursor())
            let external = id.flatMap { CGDisplayIsBuiltin($0) == 0 ? $0 : nil }
            let route = handler.routing.route(key, externalTarget: external)
            if let target = route.target {
                let fine = nsEvent.modifierFlags.contains([.option, .shift])
                handler.adjust?(target, key.direction * (fine ? 1.5625 : 6.25))
            }
            // Even an unsupported external connection must not leak brightness
            // events to macOS and accidentally change the built-in display.
            return route.consume ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil; routing = BrightnessKeyRouting()
    }
    deinit { stop() }
}
