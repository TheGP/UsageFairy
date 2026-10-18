import Cocoa
import ApplicationServices

let arguments = CommandLine.arguments
func argument(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}

struct UsageSample {
    let label: String
    let value: Double?
    let maximum: Double?
}

func validPercent(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let result = number.doubleValue
    return result.isFinite && result >= 0 && result <= 100 ? result : nil
}

func parseClaude(_ samples: [UsageSample]) -> (Double, String?)? {
    let reset = samples.first { $0.label.range(of: "^Resets (Mon|Tue|Wed|Thu|Fri|Sat|Sun)", options: .regularExpression) != nil }?.label
    for sample in samples {
        let label = sample.label.lowercased()
        if label.hasPrefix("weekly") && label.contains("all models"), let value = sample.value {
            let percent = sample.maximum == 1 ? value * 100 : value
            if percent >= 0 && percent <= 100 { return (percent, reset) }
        }
    }
    guard samples.contains(where: { $0.label == "Your usage" }) else { return nil }
    let expression = try! NSRegularExpression(pattern: "^(\\d+(?:\\.\\d+)?)% of your weekly limit used$")
    for sample in samples {
        let text = sample.label as NSString
        if let match = expression.firstMatch(in: sample.label, range: NSRange(location: 0, length: text.length)),
           let percent = Double(text.substring(with: match.range(at: 1))), percent <= 100 {
            return (percent, reset)
        }
    }
    return nil
}

func readClaude() {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first else { exit(1) }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.2)
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    var samples: [UsageSample] = []
    var index = 0
    let deadline = Date().addingTimeInterval(5)
    while index < queue.count && index < 3000 && Date() < deadline {
        let (element, depth) = queue[index]
        index += 1
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        if role == kAXTextAreaRole || role == kAXTextFieldRole { continue }
        let labels = [attribute(element, kAXDescriptionAttribute) as? String,
                      attribute(element, kAXTitleAttribute) as? String,
                      role == kAXStaticTextRole ? attribute(element, kAXValueAttribute) as? String : nil]
        let label = labels.compactMap { $0 }.first { !$0.isEmpty } ?? ""
        if label == "Your usage" || label.lowercased().hasPrefix("weekly") || label.hasPrefix("Resets ") || label.contains("% of your weekly limit used") {
            samples.append(UsageSample(label: label,
                value: (attribute(element, kAXValueAttribute) as? NSNumber)?.doubleValue,
                maximum: (attribute(element, kAXMaxValueAttribute) as? NSNumber)?.doubleValue))
        }
        if depth < 18, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            queue.append(contentsOf: children.prefix(max(0, 3000 - queue.count)).map { ($0, depth + 1) })
        }
    }
    guard let (used, reset) = parseClaude(samples) else { exit(1) }
    var result: [String: Any] = ["usedPercent": used, "sampledAt": Date().timeIntervalSince1970 * 1000]
    if let reset = reset { result["resetLabel"] = reset }
    if let data = try? JSONSerialization.data(withJSONObject: result), let text = String(data: data, encoding: .utf8) { print(text) }
}

if arguments.contains("--read-claude") { readClaude(); exit(0) }
if arguments.contains("--self-test") {
    precondition(validPercent(NSNumber(value: 42)) == 42)
    precondition(validPercent(NSNumber(value: true)) == nil)
    precondition(validPercent(NSNumber(value: Double.infinity)) == nil)
    precondition(validPercent(NSNumber(value: 999)) == nil)
    precondition(parseClaude([UsageSample(label: "Weekly limit, all models", value: 0.42, maximum: 1)])?.0 == 42)
    precondition(parseClaude([UsageSample(label: "Weekly all models", value: 42, maximum: 100)])?.0 == 42)
    precondition(parseClaude([UsageSample(label: "Session", value: 42, maximum: 100)]) == nil)
    precondition(parseClaude([UsageSample(label: "Your usage", value: nil, maximum: nil), UsageSample(label: "36% of your weekly limit used", value: nil, maximum: nil)])?.0 == 36)
    precondition(parseClaude([UsageSample(label: "999% of your weekly limit used", value: nil, maximum: nil)]) == nil)
    print("PASS: Claude weekly usage parsing, fractional ranges, session rejection, missing and invalid readings")
    exit(0)
}

let preferences = UserDefaults.standard
preferences.register(defaults: ["minimalPopup": true, "numberRemaining": false, "barRemaining": false])
let repository = argument("--repo") ?? Bundle.main.resourceURL!.path
let usageDataDirectory: String = {
    if argument("--repo") != nil { return repository + "/data" }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UsageFairy").path
}()

if arguments.contains("--check-bundle") {
    let resources = Bundle.main.resourceURL!
    precondition(repository == resources.path)
    precondition(!usageDataDirectory.hasPrefix(Bundle.main.bundlePath + "/"))
    let process = Process()
    process.executableURL = resources.appendingPathComponent("node")
    process.arguments = ["--check", resources.appendingPathComponent("TaskbarAllowancesData.js").path]
    try process.run(); process.waitUntilExit()
    precondition(process.terminationStatus == 0)
    print("PASS: standalone runtime and poller; writable storage outside the app")
    exit(0)
}

final class WidgetView: NSView {
    var readings: [String: Any] = [:] { didSet { needsDisplay = true } }
    var onMenu: ((NSEvent) -> Void)?
    var previewMode = false
    override var isFlipped: Bool { return true }
    let apps: [(String, String)] = [("codex", "Codex"), ("claude", "Claude"), ("zcode", "ZCode")]
    var visibleApps: [(String, String)] {
        if previewMode { return apps }
        let running = NSWorkspace.shared.runningApplications
        return apps.filter { app in
            if app.0 == "codex", let reading = readings[app.0] as? [String: Any], reading["remainingPercent"] is NSNumber { return true }
            return running.contains { $0.localizedName?.caseInsensitiveCompare(app.1) == .orderedSame || $0.bundleURL?.lastPathComponent == app.1 + ".app" }
        }
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }

    func text(_ value: String, _ rect: NSRect, size: CGFloat = 11, color: NSColor = .white, centered: Bool = true) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .left
        (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    func bar(_ rect: NSRect, percent: Double?, label: String, color: NSColor, segments: Int) {
        NSGraphicsContext.saveGraphicsState()
        let shape = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.26, alpha: 0.97).setFill()
        shape.fill()
        shape.addClip()
        if let percent = percent {
            color.setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(min(100, max(0, percent))) / 100, height: rect.height).fill()
        }
        NSColor.black.withAlphaComponent(0.22).setStroke()
        for tick in 1..<segments {
            let x = rect.minX + rect.width * CGFloat(tick) / CGFloat(segments)
            let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: rect.minY + 2)); line.line(to: NSPoint(x: x, y: rect.maxY - 2)); line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.18).setStroke(); shape.stroke()
        text(label, NSRect(x: rect.minX + 2, y: rect.minY + 4, width: rect.width - 4, height: rect.height - 4))
    }

    override func draw(_ dirtyRect: NSRect) {
        let minimal = preferences.bool(forKey: "minimalPopup")
        if !minimal {
            NSColor(calibratedWhite: 0.12, alpha: 0.98).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
            text("UsageFairy", NSRect(x: 15, y: 10, width: 200, height: 20), size: 13, centered: false)
            text("Allowance", NSRect(x: 80, y: 31, width: 136, height: 18), color: .lightGray)
            text("Week elapsed · reset", NSRect(x: 230, y: 31, width: 190, height: 18), color: .lightGray)
        }
        let top: CGFloat = minimal ? 8 : 54
        let remainingNumbers = preferences.bool(forKey: "numberRemaining")
        let visible = visibleApps
        if visible.isEmpty { text("Open Codex, Claude or ZCode", NSRect(x: 15, y: top + 4, width: 405, height: 20), color: .lightGray) }
        for (index, app) in visible.enumerated() {
            let y = top + CGFloat(index) * 30
            let reading = readings[app.0] as? [String: Any] ?? [:]
            let percent = validPercent(reading["remainingPercent"])
            let stale = reading["stale"] as? Bool ?? false
            let appPath = "/Applications/\(app.1).app"
            if FileManager.default.fileExists(atPath: appPath) {
                let icon = NSWorkspace.shared.icon(forFile: appPath)
                icon.draw(in: NSRect(x: 30, y: y + 1, width: 22, height: 22), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                text(String(app.1.prefix(1)), NSRect(x: 30, y: y + 2, width: 22, height: 22), size: 16)
            }
            if stale { NSColor.systemOrange.setFill(); NSBezierPath(ovalIn: NSRect(x: 56, y: y + 9, width: 5, height: 5)).fill() }
            let number = percent.map { remainingNumbers ? $0 : 100 - $0 }
            let fill = percent.map { preferences.bool(forKey: "barRemaining") ? $0 : 100 - $0 }
            let label = number.map { "\(Int($0.rounded()))% \(remainingNumbers ? "left" : "used")" } ?? "--"
            bar(NSRect(x: 80, y: y, width: 136, height: 23), percent: fill, label: label, color: NSColor(calibratedRed: 0.14, green: 0.48, blue: 0.61, alpha: 1), segments: 10)
            var week: Double?
            var weekLabel = "--"
            let current = Date().timeIntervalSince1970 * 1000
            if let reset = (reading["resetsAt"] as? NSNumber)?.doubleValue, reset.isFinite, reset > current, reset <= current + 8 * 24 * 3600 * 1000 {
                week = min(100, max(0, (1 - (reset / 1000 - Date().timeIntervalSince1970) / (7 * 24 * 3600)) * 100))
                let formatter = DateFormatter(); formatter.dateFormat = "d MMM, HH:mm"
                weekLabel = "\(Int(week!.rounded()))% · \(formatter.string(from: Date(timeIntervalSince1970: reset / 1000)))"
            }
            bar(NSRect(x: 230, y: y, width: 190, height: 23), percent: week, label: weekLabel, color: NSColor(calibratedRed: 0.40, green: 0.36, blue: 0.56, alpha: 1), segments: 7)
        }
        if !minimal {
            let unavailable = visible.compactMap { app -> String? in
                let reading = readings[app.0] as? [String: Any] ?? [:]
                return reading["remainingPercent"] is NSNumber ? nil : app.1
            }
            let message = unavailable.isEmpty ? "Orange dot = cached reading" : "Unavailable: " + unavailable.joined(separator: ", ")
            let footerY = CGFloat(61 + max(1, visible.count) * 30)
            text(message, NSRect(x: 15, y: footerY, width: 315, height: 18), size: 10, color: .lightGray, centered: false)
            text("30s refresh", NSRect(x: 338, y: footerY, width: 82, height: 18), size: 10, color: .lightGray)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var status: NSStatusItem!
    var panel: NSPanel!
    var view: WidgetView!
    var poller: Process?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: 26)
        status.button?.title = "%"
        status.button?.toolTip = "UsageFairy — click to show or hide, right-click for settings"
        status.button?.target = self; status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 435, height: 106), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "UsageFairy"; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.delegate = self
        view = WidgetView(frame: panel.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.onMenu = { [weak self] event in guard let self = self else { return }; NSMenu.popUpContextMenu(self.menu(), with: event, for: self.view) }
        panel.contentView = view
        resize()
        restorePosition()
        panel.orderFrontRegardless()
        startPoller()
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reload() }
    }

    func startPoller() {
        let node = argument("--node") ?? Bundle.main.resourceURL!.appendingPathComponent("node").path
        let process = Process(); process.executableURL = URL(fileURLWithPath: node)
        process.arguments = [repository + "/TaskbarAllowancesData.js", "--loop", String(ProcessInfo.processInfo.processIdentifier)]
        var environment = ProcessInfo.processInfo.environment
        environment["USAGEFAIRY_MAC_HELPER"] = Bundle.main.executablePath
        environment["USAGEFAIRY_DATA_DIR"] = usageDataDirectory
        environment["PATH"] = URL(fileURLWithPath: node).deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); poller = process } catch { status.button?.toolTip = "Node.js could not start; relaunch through macos/launch.sh" }
    }

    func reload() {
        let file = URL(fileURLWithPath: usageDataDirectory + "/allowances.json")
        if let data = try? Data(contentsOf: file), var parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for app in view.apps {
                if var reading = parsed[app.0] as? [String: Any], let sampled = (reading["sampledAt"] as? NSNumber)?.doubleValue,
                   Date().timeIntervalSince1970 * 1000 - sampled > 45 * 60 * 1000 {
                    reading["remainingPercent"] = NSNull(); reading["resetsAt"] = NSNull()
                    reading["error"] = "Reading expired"; parsed[app.0] = reading
                }
            }
            view.readings = parsed
        }
        var lines: [String] = []
        for app in view.apps {
            let reading = view.readings[app.0] as? [String: Any] ?? [:]
            if let error = reading["error"] as? String { lines.append(app.1 + ": " + error) }
        }
        view.toolTip = lines.isEmpty ? "Drag to move. Right-click for settings." : lines.joined(separator: "\n")
        resize()
    }

    func resize() {
        let rows = max(1, view.visibleApps.count)
        let height = CGFloat((preferences.bool(forKey: "minimalPopup") ? 16 : 92) + rows * 30)
        if panel.contentView?.frame.height != height { panel.setContentSize(NSSize(width: 435, height: height)) }
        view.needsDisplay = true
    }

    func restorePosition() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var point = NSPoint(x: screen.maxX - 447, y: screen.minY + 12)
        if let saved = preferences.string(forKey: "position") {
            let candidate = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(NSRect(origin: candidate, size: panel.frame.size)) }) { point = candidate }
        }
        panel.setFrameOrigin(point)
    }

    func windowDidMove(_ notification: Notification) { preferences.set(NSStringFromPoint(panel.frame.origin), forKey: "position") }
    @objc func statusClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp { NSMenu.popUpContextMenu(menu(), with: event, for: status.button!); return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
    func item(_ title: String, _ action: Selector, setting: String? = nil) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: ""); result.target = self
        if let setting = setting { result.state = preferences.bool(forKey: setting) ? .on : .off }
        return result
    }
    func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Show / hide widget", #selector(toggleWidget)))
        menu.addItem(item("Minimal popup", #selector(toggleMinimal), setting: "minimalPopup"))
        menu.addItem(item("Numbers: remaining", #selector(toggleNumbers), setting: "numberRemaining"))
        menu.addItem(item("Bar fill: remaining", #selector(toggleBars), setting: "barRemaining"))
        menu.addItem(.separator())
        menu.addItem(item("Enable Claude usage reading…", #selector(enableClaude)))
        menu.addItem(item("Quit UsageFairy", #selector(quit)))
        return menu
    }
    @objc func toggleMinimal() { preferences.set(!preferences.bool(forKey: "minimalPopup"), forKey: "minimalPopup"); resize() }
    @objc func toggleWidget() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    @objc func toggleNumbers() { preferences.set(!preferences.bool(forKey: "numberRemaining"), forKey: "numberRemaining"); view.needsDisplay = true }
    @objc func toggleBars() { preferences.set(!preferences.bool(forKey: "barRemaining"), forKey: "barRemaining"); view.needsDisplay = true }
    @objc func enableClaude() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); if poller?.isRunning == true { poller?.terminate() } }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let preview = argument("--render-preview") {
    let view = WidgetView(frame: NSRect(x: 0, y: 0, width: 435, height: 106))
    view.previewMode = true
    let reset = Date().addingTimeInterval(5 * 24 * 3600).timeIntervalSince1970 * 1000
    view.readings = ["codex": ["remainingPercent": 64, "resetsAt": reset], "claude": ["remainingPercent": 82, "resetsAt": reset, "stale": true], "zcode": ["remainingPercent": 42, "resetsAt": reset]]
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: preview))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
