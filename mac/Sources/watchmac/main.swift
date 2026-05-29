import AppKit

// Optional CLI overrides (a double-clicked .app just uses the defaults).
func parseConfig(_ args: [String]) -> StreamController.Config {
    var c = StreamController.Config()
    // Watch-shaped defaults: Apple Watch Ultra display ≈ 410×502 (aspect 0.817).
    // Bigger virtual display keeps the same aspect so the watch app has zero
    // letterboxing, while macOS 26.5 still treats it as a "real" display in
    // System Settings (tiny virtual displays get hidden from the UI).
    c.width = 1000
    c.height = 1224
    c.fps = 30
    c.quality = 0.6
    c.port = 8890
    c.name = "Watch Display"
    c.originX = 12000
    c.originY = 0

    var i = 1
    func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
    while i < args.count {
        switch args[i] {
        case "--width":   if let v = next(), let n = UInt32(v) { c.width = n }
        case "--height":  if let v = next(), let n = UInt32(v) { c.height = n }
        case "--fps":     if let v = next(), let n = Int(v) { c.fps = n }
        case "--quality": if let v = next(), let n = Double(v) { c.quality = n }
        case "--port":    if let v = next(), let n = UInt16(v) { c.port = n }
        case "--refresh": if let v = next(), let n = Double(v) { c.refresh = n }
        case "--name":    if let v = next() { c.name = v }
        case "--hidpi":   c.hidpi = true
        case "--source":  if let v = next() { c.useMainDisplay = (v == "main") }
        default: break
        }
        i += 1
    }
    return c
}

let controller = StreamController(config: parseConfig(CommandLine.arguments))

let app = NSApplication.shared
let delegate = AppDelegate(controller: controller)
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no window
app.run()
