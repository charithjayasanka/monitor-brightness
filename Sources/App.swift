import AppKit
import ServiceManagement

func screenUnderCursor() -> NSScreen? {
    let screens = NSScreen.screens
    let candidates = screens.compactMap { screen -> (id: UInt32, frame: NSRect)? in
        guard let id = screenID(screen) else { return nil }
        return (id, screen.frame)
    }
    guard let id = cursorDisplayID(at: NSEvent.mouseLocation, screens: candidates) else { return nil }
    return screens.first { screenID($0) == id }
}

func screenID(_ screen: NSScreen?) -> CGDirectDisplayID? {
    (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

final class Display {
    let handle: OpaquePointer
    let maximum: UInt16
    let current: UInt16
    let screenID: CGDirectDisplayID
    let verified: Bool
    init(_ handle: OpaquePointer, current: UInt16, maximum: UInt16, verified: Bool = true) {
        self.handle = handle; self.current = current; self.maximum = maximum
        self.verified = verified
        self.screenID = ddc_screen_id(handle)
    }
    deinit { ddc_release(handle) }
}

final class BrightnessRow: NSView {
    let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    let valueLabel = NSTextField(labelWithString: "")
    let feedback = NSTextField(labelWithString: "Hardware brightness · DDC/CI")
    let display: Display
    let queue: DispatchQueue
    var pending: DispatchWorkItem?
    var revision = 0
    var active = true

    init(display: Display, name: String, queue: DispatchQueue) {
        self.display = display; self.queue = queue
        super.init(frame: NSRect(x: 0, y: 0, width: 310, height: 92))
        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 18, y: 65, width: 220, height: 18)
        valueLabel.frame = NSRect(x: 246, y: 65, width: 46, height: 18)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        slider.frame = NSRect(x: 18, y: 30, width: 274, height: 26)
        slider.doubleValue = Double(display.current) / Double(display.maximum) * 100
        slider.target = self; slider.action = #selector(changed)
        slider.isContinuous = true
        slider.setAccessibilityLabel("\(name) brightness")
        feedback.frame = NSRect(x: 18, y: 7, width: 274, height: 18)
        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = .secondaryLabelColor
        [title, valueLabel, slider, feedback].forEach(addSubview)
        updateLabel()
        if !display.verified {
            valueLabel.stringValue = "—"
            feedback.stringValue = "Manual · unknown brightness · assumes 0–100"
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateLabel() { valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%" }
    func invalidate() { active = false; pending?.cancel() }
    @objc func changed() {
        guard screenID(screenUnderCursor()) == display.screenID else {
            pending?.cancel()
            feedback.stringValue = "Move the cursor to this display to adjust it"
            return
        }
        updateLabel()
        pending?.cancel()
        revision += 1
        let request = revision
        let value = UInt16((slider.doubleValue / 100 * Double(display.maximum)).rounded())
        feedback.stringValue = "Adjusting…"
        let work = DispatchWorkItem { [weak self, display] in
            let written = ddc_write(display.handle, value)
            // A successful I2C send alone does not prove the monitor applied it.
            usleep(80000)
            var actual: UInt16 = 0, maximum: UInt16 = 0
            let readBack = written && display.verified && ddc_read(display.handle, &actual, &maximum)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active, self.revision == request else { return }
                if readBack {
                    self.slider.doubleValue = Double(actual) / Double(maximum) * 100
                    self.updateLabel()
                    self.feedback.stringValue = actual == value ? "Hardware brightness · DDC/CI" : "Monitor reported a different brightness"
                } else {
                    self.feedback.stringValue = written ? "Sent · brightness unverified" : "Couldn’t write brightness. Refresh to retry."
                }
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let queue = DispatchQueue(label: "local.macosDisplay.ddc", qos: .userInitiated)
    var status: NSStatusItem!
    let menu = NSMenu()
    var rows: [BrightnessRow] = []
    var generation = 0
    var manualMode = false
    let brightnessKeys = BrightnessKeys()
    var keyDeltas: [UInt32: Double] = [:]
    var keyBusy = false
    var keyWork: DispatchWorkItem?
    var keyMessage = "Brightness keys follow the cursor"
    var keyStatusItem: NSMenuItem?
    var keysEnabled: Bool { !UserDefaults.standard.bool(forKey: "brightnessKeysDisabled") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Monitor Brightness")
        status.button?.toolTip = "Monitor Brightness"
        status.menu = menu
        menu.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        brightnessKeys.adjust = { [weak self] id, delta in self?.enqueueKey(id: id, delta: delta) }
        if keysEnabled { brightnessKeys.start(prompt: CommandLine.arguments.contains("--enable-brightness-keys")) }
        refresh()
    }
    func item(_ title: String, action: Selector? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
    func footer() {
        menu.addItem(.separator())
        menu.addItem(item("Refresh Displays", action: #selector(refresh)))
        let keys = item(brightnessKeys.running ? "Brightness Keys Follow Cursor" : "Enable Brightness Keys…", action: #selector(toggleKeys))
        keys.state = brightnessKeys.running ? .on : .off
        menu.addItem(keys)
        keyStatusItem = item(brightnessKeys.running ? keyMessage : "Accessibility permission required for key routing")
        menu.addItem(keyStatusItem!)
        let manual = item("Allow Unverified Brightness Control", action: #selector(toggleManual))
        manual.state = manualMode ? .on : .off
        menu.addItem(manual)
        let login = item("Launch at Login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Connection Help", action: #selector(help)))
        menu.addItem(.separator())
        let quit = item("Quit Monitor Brightness", action: #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }
    func menuWillOpen(_ menu: NSMenu) {
        if keysEnabled { brightnessKeys.start() }
        refresh()
    }

    @objc func toggleKeys() {
        if brightnessKeys.running {
            brightnessKeys.stop()
            UserDefaults.standard.set(true, forKey: "brightnessKeysDisabled")
            keyWork?.cancel(); keyDeltas.removeAll()
        } else {
            UserDefaults.standard.set(false, forKey: "brightnessKeysDisabled")
            brightnessKeys.start(prompt: true)
            if !brightnessKeys.running {
                alert("Enable brightness-key routing", "Allow Monitor Brightness in System Settings → Privacy & Security → Accessibility. Then reopen this menu. If macOS also requests Input Monitoring, allow it and relaunch the app.\n\nThis lets the app intercept brightness keys over external monitors while leaving built-in display controls to macOS.")
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }
        }
        refresh()
    }

    func enqueueKey(id: UInt32, delta: Double) {
        rows.forEach { $0.invalidate() }
        keyDeltas[id, default: 0] += delta
        guard !keyBusy, keyWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.keyWork = nil; self?.processKey() }
        keyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    func processKey() {
        guard !keyBusy, let (id, delta) = keyDeltas.first else { return }
        keyDeltas.removeValue(forKey: id)
        keyBusy = true
        let name = NSScreen.screens.first { screenID($0) == id }?.localizedName ?? "External display"
        queue.async { [weak self] in
            var handles = [OpaquePointer?](repeating: nil, count: 16)
            let count = ddc_discover(&handles, Int32(handles.count))
            let all = handles.prefix(max(0, Int(count))).compactMap { $0 }
            defer { all.forEach { ddc_release($0) } }
            let matches = all.filter { ddc_screen_id($0) == id }
            var message = "\(name): DDC brightness unavailable"
            if matches.count == 1, let handle = matches.first {
                var current: UInt16 = 0, maximum: UInt16 = 0
                if ddc_read(handle, &current, &maximum) {
                    let target = UInt16(min(Double(maximum), max(0, (Double(current) + delta * Double(maximum) / 100).rounded())))
                    if ddc_write(handle, target) {
                        var actual: UInt16 = 0, readMax: UInt16 = 0
                        if ddc_read(handle, &actual, &readMax) {
                            message = "\(name): \(Int((Double(actual) / Double(readMax) * 100).rounded()))%"
                        } else { message = "\(name): sent, not confirmed" }
                    } else { message = "\(name): brightness write failed" }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.keyBusy = false
                self.keyMessage = message
                self.keyStatusItem?.title = message
                self.status.button?.toolTip = message
                self.processKey()
            }
        }
    }

    @objc func refresh() {
        generation += 1
        let request = generation
        let allowManual = manualMode
        let targetScreen = screenUnderCursor()
        let targetID = screenID(targetScreen)
        let targetName = targetScreen?.localizedName ?? "Unknown display"
        rows.forEach { $0.invalidate() }; rows.removeAll()
        menu.removeAllItems()
        menu.addItem(item("\(targetName) · under cursor"))
        menu.addItem(item("Checking brightness…"))
        footer()
        guard let targetID, CGDisplayIsBuiltin(targetID) == 0 else {
            menu.removeAllItems()
            menu.addItem(item("\(targetName) · under cursor"))
            menu.addItem(item("Use macOS brightness controls for this display"))
            footer()
            return
        }
        queue.async { [weak self] in
            var handles = [OpaquePointer?](repeating: nil, count: 16)
            let count = ddc_discover(&handles, Int32(handles.count))
            var displays: [Display] = []
            var failed = 0
            if count > 0 {
                for handle in handles.prefix(Int(count)).compactMap({ $0 }) {
                    guard ddc_screen_id(handle) == targetID else { ddc_release(handle); continue }
                    var current: UInt16 = 0, maximum: UInt16 = 0
                    if ddc_read(handle, &current, &maximum) {
                        displays.append(Display(handle, current: current, maximum: maximum))
                    } else if allowManual {
                        displays.append(Display(handle, current: 50, maximum: 100, verified: false))
                    } else { failed += 1; ddc_release(handle) }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == request else { return }
                self.menu.removeAllItems()
                self.menu.addItem(self.item("\(targetName) · under cursor"))
                // Multiple DDC services for one screen are ambiguous; never fan out.
                for display in displays.count == 1 ? displays : [] {
                    let row = BrightnessRow(display: display, name: targetName, queue: self.queue)
                    self.rows.append(row)
                    let entry = NSMenuItem(); entry.view = row
                    self.menu.addItem(entry)
                }
                if displays.count > 1 {
                    self.menu.addItem(self.item("Cannot uniquely identify this display’s controls"))
                } else if displays.isEmpty {
                    self.menu.addItem(self.item(count < 0 ? "DDC service unavailable" : count == 0 ? "No external display detected" : "No DDC brightness control for this display"))
                } else if failed > 0 {
                    self.menu.addItem(self.item("\(failed) display connection(s) did not respond"))
                }
                self.footer()
            }
        }
    }
    @objc func toggleManual() {
        manualMode.toggle()
        refresh()
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            refresh()
        } catch { alert("Couldn’t change login setting", error.localizedDescription + "\nKeep the app in a permanent location, such as Applications, and try again.") }
    }
    @objc func help() {
        alert("Connecting your monitor", "Enable DDC/CI in your monitor’s on-screen settings, then choose Refresh Displays. Some monitors disable brightness control in HDR or preset picture modes.\n\nTry a direct USB-C, DisplayPort, or HDMI connection if a dock blocks DDC. This app requires Apple Silicon and a monitor that supports DDC brightness (VCP 0x10).\n\nIf another monitor-control app is running, quit it before retrying to avoid competing DDC requests.")
    }
    func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.runModal()
    }
    @objc func quit() { rows.forEach { $0.invalidate() }; NSApp.terminate(nil) }
}

@main
struct MonitorBrightnessApp {
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            var handles = [OpaquePointer?](repeating: nil, count: 16)
            let count = ddc_discover(&handles, Int32(handles.count))
            print("External DDC services: \(count)")
            for handle in handles.prefix(max(0, Int(count))).compactMap({ $0 }) {
                var current: UInt16 = 0, maximum: UInt16 = 0
                let success = ddc_read(handle, &current, &maximum)
                print("Service \(ddc_id(handle)), screen \(ddc_screen_id(handle)): \(success ? "brightness \(current)/\(maximum)" : "no valid brightness response")")
                ddc_release(handle)
            }
        } else {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }

    }
}
