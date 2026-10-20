import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = EventController()
    private var statusItem: NSStatusItem!
    private var setupWindow: NSWindow?
    private var setupStatus: NSTextField?
    private var diagnosticsWindow: NSWindow?
    private var setupDecision: NSTextField?
    private var permissionButton: NSButton?
    private var loginButton: NSButton?
    private var dockButton: NSButton?
    private var loginStatus: NSTextField?
    private var loginSettingsButton: NSButton?
    private var setupActivity: NSTextField?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTrusted = AXIsProcessTrusted()
    private let defaults = UserDefaults.standard
    private let defaultExclusions: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "org.alacritty", "dev.warp.Warp-Stable",
        "org.blenderfoundation.blender", "com.autodesk.fusion360", "com.figma.Desktop"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: icon)
        }
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let show = NSMenuItem(title: "Settings…", action: #selector(showSetup), keyEquivalent: ",")
        show.target = self
        appMenu.addItem(show)
        let restoreIcon = NSMenuItem(title: "Show Menu Bar Icon", action: #selector(showMenuBarIcon), keyEquivalent: "")
        restoreIcon.target = self
        appMenu.addItem(restoreIcon)
        let diagnostics = NSMenuItem(title: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "d")
        diagnostics.target = self
        appMenu.addItem(diagnostics)
        let help = NSMenuItem(title: "Help", action: #selector(openGuide), keyEquivalent: "")
        help.target = self
        appMenu.addItem(help)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
        defaults.register(defaults: ["enabled": true, "speed": 1.0, "horizontal": true, "showDockIcon": true,
                                     "excludedApps": Array(defaultExclusions)])
        NSApp.setActivationPolicy(defaults.bool(forKey: "showDockIcon") ? .regular : .accessory)
        controller.enabled = defaults.bool(forKey: "enabled")
        controller.speed = defaults.double(forKey: "speed")
        controller.horizontal = defaults.bool(forKey: "horizontal")
        controller.excludedApps = Set(defaults.stringArray(forKey: "excludedApps") ?? [])
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "SmartMiddleClickAutoscroll"
        statusItem.isVisible = true
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        statusItem.button?.setAccessibilityLabel(AppInfo.name)
        controller.onChange = { [weak self] in self?.refreshStatus() }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.controller.cancel()
                self?.controller.prepareForegroundApp()
            })
        }
        controller.start()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.lastTrusted {
                self.lastTrusted = trusted
                if trusted { self.controller.start() }
                else { self.controller.shutdown() }
                self.refreshStatus()
            }
        }
        refreshStatus()
        if !AXIsProcessTrusted() || !defaults.bool(forKey: "didShowSetup") || CommandLine.arguments.contains("--show") {
            showSetup()
            defaults.set(true, forKey: "didShowSetup")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMenuBarIcon()
        showSetup()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshLoginStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
        permissionTimer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        @discardableResult func item(_ title: String, _ action: Selector? = nil) -> NSMenuItem {
            let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
            value.target = self
            menu.addItem(value)
            return value
        }
        item("\(AppInfo.name) \(AppInfo.version)").isEnabled = false
        item(controller.enabled ? controller.status : "Paused").isEnabled = false
        menu.addItem(.separator())
        let enabled = item("Enable autoscroll", #selector(toggleEnabled))
        enabled.state = controller.enabled ? .on : .off
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let id = app.bundleIdentifier {
            let exclude = item("Keep native middle click in \(app.localizedName ?? id)", #selector(toggleApp(_:)))
            exclude.representedObject = id
            exclude.state = controller.excludedApps.contains(id) ? .on : .off
        }
        let speedItem = item("Scroll speed")
        let speedMenu = NSMenu()
        for (title, speed) in [("Slow · 50%", 0.5), ("Normal · 100%", 1.0), ("Fast · 150%", 1.5), ("Faster · 200%", 2.0)] {
            let value = NSMenuItem(title: title, action: #selector(setSpeed(_:)), keyEquivalent: "")
            value.target = self
            value.representedObject = speed
            value.state = controller.speed == speed ? .on : .off
            speedMenu.addItem(value)
        }
        speedItem.submenu = speedMenu
        let horizontal = item("Allow horizontal autoscroll", #selector(toggleHorizontal))
        horizontal.state = controller.horizontal ? .on : .off
        let login = item("Start at login", #selector(toggleLogin))
        login.state = loginRequested ? .on : .off
        let dock = item("Show in Dock", #selector(toggleDock))
        dock.state = defaults.bool(forKey: "showDockIcon") ? .on : .off
        let exclusionItem = item("Apps keeping native middle click")
        let exclusions = NSMenu()
        for id in controller.excludedApps.sorted() {
            let title = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
            let value = NSMenuItem(title: title, action: #selector(toggleApp(_:)), keyEquivalent: "")
            value.target = self
            value.state = .on
            value.representedObject = id
            exclusions.addItem(value)
        }
        if exclusions.items.isEmpty {
            let empty = NSMenuItem(title: "No exclusions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            exclusions.addItem(empty)
        }
        exclusionItem.submenu = exclusions
        menu.addItem(.separator())
        item("Settings…", #selector(showSetup)).keyEquivalent = ","
        item("Help", #selector(openGuide))
        item("Diagnostics…", #selector(showDiagnostics))
        menu.addItem(.separator())
        let quit = item("Quit \(AppInfo.name)", #selector(quit))
        quit.keyEquivalent = "q"
    }

    private func refreshStatus() {
        let symbol = !controller.enabled ? "pause.circle" : controller.running ? "arrow.up.and.down.circle" : "exclamationmark.circle"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppInfo.name)
        statusItem?.button?.image?.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.imageScaling = .scaleProportionallyDown
        statusItem?.button?.title = statusItem?.button?.image == nil ? "↕" : ""
        statusItem?.button?.toolTip = "\(AppInfo.name) — \(controller.enabled ? controller.status : "Paused")"
        setupStatus?.stringValue = controller.enabled ? controller.status : "Paused — enable from the menu bar"
        setupDecision?.stringValue = "Last click: \(controller.lastDecision)"
        setupActivity?.stringValue = controller.activity
        permissionButton?.title = AXIsProcessTrusted() ? "Accessibility Settings…" : "Allow Accessibility…"
    }

    private var loginRequested: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    private func refreshLoginStatus() {
        loginButton?.state = loginRequested ? .on : .off
        let needsApproval = SMAppService.mainApp.status == .requiresApproval
        loginStatus?.stringValue = needsApproval ? "Allow startup in System Settings → General → Login Items." : ""
        loginStatus?.isHidden = !needsApproval
        loginSettingsButton?.isHidden = !needsApproval
        if let window = setupWindow, let stack = window.contentView?.subviews.first as? NSStackView {
            window.contentView?.layoutSubtreeIfNeeded()
            window.setContentSize(NSSize(width: window.frame.width, height: stack.fittingSize.height + 56))
        }
    }

    @objc private func toggleLogin() {
        do {
            if loginRequested { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update startup preference"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshLoginStatus()
    }

    @objc private func openLoginSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func toggleDock() {
        let visible = !defaults.bool(forKey: "showDockIcon")
        defaults.set(visible, forKey: "showDockIcon")
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        dockButton?.state = visible ? .on : .off
    }

    @objc private func showMenuBarIcon() {
        statusItem?.isVisible = true
    }

    @objc private func showOptions(_ sender: NSButton) {
        let menu = NSMenu()
        menu.delegate = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func toggleEnabled() {
        controller.enabled.toggle()
        defaults.set(controller.enabled, forKey: "enabled")
    }
    @objc private func toggleHorizontal() {
        controller.horizontal.toggle()
        defaults.set(controller.horizontal, forKey: "horizontal")
    }
    @objc private func setSpeed(_ sender: NSMenuItem) {
        controller.speed = sender.representedObject as? Double ?? 1
        defaults.set(controller.speed, forKey: "speed")
    }
    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if controller.excludedApps.contains(id) { controller.excludedApps.remove(id) }
        else { controller.excludedApps.insert(id) }
        defaults.set(Array(controller.excludedApps), forKey: "excludedApps")
        controller.cancel()
    }
    @objc private func retry() {
        controller.shutdown()
        controller.start()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openGuide() {
        if let guide = Bundle.main.url(forResource: "Help", withExtension: "html") {
            NSWorkspace.shared.open(guide)
        }
    }

    @objc private func showDiagnostics() {
        if let diagnosticsWindow {
            NSApp.activate(ignoringOtherApps: true)
            diagnosticsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let (window, stack) = makeWindow(title: "Diagnostics", width: 560)
        setupDecision = addLabel("Last click: \(controller.lastDecision)", to: stack)
        setupActivity = addLabel(controller.activity, to: stack)
        let retry = NSButton(title: "Retry input listener", target: self, action: #selector(retry))
        retry.bezelStyle = .rounded
        stack.addArrangedSubview(retry)
        diagnosticsWindow = window
        present(window, stack: stack)
    }

    @objc private func showSetup() {
        if let setupWindow {
            NSApp.activate(ignoringOtherApps: true)
            setupWindow.makeKeyAndOrderFront(nil)
            return
        }
        let (window, stack) = makeWindow(title: AppInfo.name, width: 560)
        _ = addLabel("Middle-click to autoscroll.", to: stack, size: 24, weight: .semibold)
        _ = addLabel("Middle-click scrollable content, then move the pointer to control speed. Click again or press Esc to stop.", to: stack)
        _ = addLabel("Links, tabs, and controls keep their usual middle-click actions.", to: stack)
        setupStatus = addLabel(controller.status, to: stack, weight: .medium)
        let login = NSButton(checkboxWithTitle: "Start at login", target: self, action: #selector(toggleLogin))
        loginButton = login
        stack.addArrangedSubview(login)
        loginStatus = addLabel("", to: stack)
        let loginSettings = NSButton(title: "Login Items…", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded
        loginSettingsButton = loginSettings
        stack.addArrangedSubview(loginSettings)
        let dock = NSButton(checkboxWithTitle: "Show in Dock", target: self, action: #selector(toggleDock))
        dock.state = defaults.bool(forKey: "showDockIcon") ? .on : .off
        dockButton = dock
        stack.addArrangedSubview(dock)
        let row = NSStackView()
        row.spacing = 12
        let permission = NSButton(title: AXIsProcessTrusted() ? "Accessibility Settings…" : "Allow Accessibility…",
                                  target: self, action: #selector(openAccessibility))
        permission.bezelStyle = .rounded
        permissionButton = permission
        row.addArrangedSubview(permission)
        let options = NSButton(title: "Options…", target: self, action: #selector(showOptions(_:)))
        options.bezelStyle = .rounded
        row.addArrangedSubview(options)
        let help = NSButton(title: "Help", target: self, action: #selector(openGuide))
        help.bezelStyle = .rounded
        row.addArrangedSubview(help)
        stack.addArrangedSubview(row)
        _ = addLabel("Speed and app exclusions: use Options or the ↕ menu-bar icon.", to: stack)
        setupWindow = window
        refreshLoginStatus()
        refreshStatus()
        present(window, stack: stack)
    }

    private func makeWindow(title: String, width: CGFloat) -> (NSWindow, NSStackView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 360),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])
        return (window, stack)
    }

    private func addLabel(_ text: String, to stack: NSStackView, size: CGFloat = 13,
                          weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return label
    }

    private func present(_ window: NSWindow, stack: NSStackView) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: window.frame.width, height: stack.fittingSize.height + 56))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

if CommandLine.arguments.contains("--diagnose") {
    print("\(AppInfo.name) \(AppInfo.version)")
    print("Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not allowed")")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: 100)
    var tapCount: UInt32 = 0
    if CGGetEventTapList(100, &taps, &tapCount) == .success {
        for tap in taps.prefix(Int(tapCount)) {
            let name = NSRunningApplication(processIdentifier: tap.tappingProcess)?.localizedName ?? "pid \(tap.tappingProcess)"
            print("Event tap: \(name), location \(tap.tapPoint.rawValue), enabled \(tap.enabled)")
        }
    }
    exit(0)
}

let app = NSApplication.shared
if let id = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id)
    .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    existing.activate(options: [])
    exit(0)
}
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
