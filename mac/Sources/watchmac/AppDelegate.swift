import AppKit

/// Menu bar (status item) front end. Everything — start, stop, addresses,
/// quit — is driven from here; there is no Dock icon and no window.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let controller: StreamController
    private let tunnel = Tunnel()
    private var statusItem: NSStatusItem!
    private var clientCount = 0
    private var publicURL: String?
    private var shortURL: String?
    private var tunnelStatus: String?

    init(controller: StreamController) {
        self.controller = controller
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(running: false)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        controller.onStateChange = { [weak self] running in self?.updateIcon(running: running) }
        controller.onClientCount = { [weak self] count in self?.clientCount = count }
        controller.onError       = { [weak self] message in self?.showError(message) }

        tunnel.onURL      = { [weak self] url in self?.publicURL = url; self?.tunnelStatus = nil }
        tunnel.onShortURL = { [weak self] url in self?.shortURL = url }
        tunnel.onStatus   = { [weak self] status in self?.tunnelStatus = status }

        controller.start()                                      // start streaming
        tunnel.start(localPort: controller.config.port)         // optional public URL
    }

    // MARK: - Status icon

    private func updateIcon(running: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "applewatch", accessibilityDescription: "watchmac")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = running ? .systemGreen : nil
    }

    // MARK: - Menu (rebuilt on open so it always shows live state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = controller.isRunning

        let header = NSMenuItem(
            title: "⌚️  watchmac  (\(controller.config.width)×\(controller.config.height))",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let status = NSMenuItem(
            title: running ? "   🟢 켜짐 · 보는 중 \(clientCount)명" : "   ⚪️ 꺼짐",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if running {
            menu.addItem(item("   ■ 중지", #selector(stopTapped)))

            if let local = controller.localURLs.first {
                menu.addItem(item("   같은 WiFi 기기용 주소 복사   \(local)",
                                  #selector(copyLocalTapped), object: local))
            }

            menu.addItem(.separator())

            let pubHeader = NSMenuItem(title: "🌐  공개 주소 (셀룰러/외부망)",
                                       action: nil, keyEquivalent: "")
            pubHeader.isEnabled = false
            menu.addItem(pubHeader)
            if let addr = shortURL ?? publicURL {
                let typed = addr.replacingOccurrences(of: "https://", with: "")
                let mi = item("   👉  \(typed)", #selector(copyPublicTapped), object: addr)
                mi.attributedTitle = NSAttributedString(
                    string: "   👉  \(typed)",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)])
                menu.addItem(mi)
            } else if let status = tunnelStatus {
                let s = NSMenuItem(title: "   ⚠️ \(status)", action: nil, keyEquivalent: "")
                s.isEnabled = false
                menu.addItem(s)
            } else {
                let s = NSMenuItem(title: "   ⏳ 주소 준비 중…", action: nil, keyEquivalent: "")
                s.isEnabled = false
                menu.addItem(s)
            }

            menu.addItem(item("   맥에서 미리보기", #selector(openPreviewTapped)))
        } else {
            menu.addItem(item("   ▶ 시작", #selector(startTapped)))
        }

        menu.addItem(.separator())
        menu.addItem(item("종료", #selector(quitTapped)))
    }

    private func item(_ title: String, _ action: Selector, object: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.representedObject = object
        return mi
    }

    // MARK: - Actions

    @objc private func startTapped() { controller.start() }
    @objc private func stopTapped()  { controller.stop() }

    @objc private func copyPublicTapped(_ sender: NSMenuItem) { copy(sender.representedObject as? String) }
    @objc private func copyLocalTapped(_ sender: NSMenuItem)  { copy(sender.representedObject as? String) }

    private func copy(_ string: String?) {
        guard let string else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    @objc private func openPreviewTapped() {
        if let u = URL(string: "http://localhost:\(controller.config.port)") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func quitTapped() {
        tunnel.stop()
        controller.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Error alert

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "watchmac"
        alert.informativeText = message
        alert.addButton(withTitle: "화면 기록 설정 열기")
        alert.addButton(withTitle: "닫기")
        if alert.runModal() == .alertFirstButtonReturn {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(u)
            }
        }
    }
}
