import AppKit
import ApplicationServices

final class AccessibilityTarget {
    private let queue = DispatchQueue(label: "local.smartmiddle.hit-test", qos: .userInitiated)
    private var inFlight = false
    private var prepared: Set<pid_t> = []

    func prepare(pid: pid_t, bundleID: String) {
        queue.async {
            guard pid > 0, self.prepared.insert(pid).inserted else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.05)
            var role: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &role)
            // Chromium defers building the web AX tree until an assistive client
            // asks for it. Request once per process, outside the click callback.
            let chromium = ["company.thebrowser.Browser", "com.google.Chrome", "com.google.Chrome.canary",
                            "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
            if chromium.contains(bundleID) {
                _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
    }

    // All AX IPC runs here, never inside the input callback. Slow apps fail open.
    func inspect(point: CGPoint, foregroundPID: pid_t, completion: @escaping (TargetDecision) -> Void) {
        guard !inFlight else {
            completion(.native("Previous app is still answering Accessibility"))
            return
        }
        inFlight = true
        queue.async {
            let result = self.classify(point: point, foregroundPID: foregroundPID)
            DispatchQueue.main.async {
                self.inFlight = false
                completion(result)
            }
        }
    }

    private func classify(point: CGPoint, foregroundPID: pid_t) -> TargetDecision {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.10
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.015)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return .native("App did not expose a target") }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid == foregroundPID else {
            return .native("Background window or system interface")
        }
        var current: AXUIElement? = hit
        var axes: ScrollAxes = []
        var reachedWindow = false
        var firstRole = ""
        var inspected = 0
        var roles: [String] = []
        while let element = current, inspected < 40 {
            inspected += 1
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                return .native("Accessibility lookup took too long")
            }
            AXUIElementSetMessagingTimeout(element, 0.015)
            // Batch these into one IPC call; do not retrieve labels, text, or URLs.
            let names = ["AXRole", "AXSubrole", "AXEditable", "AXParent",
                         "AXVerticalScrollBar", "AXHorizontalScrollBar"] as CFArray
            var result: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, names, [], &result) == .success,
                  let values = result as? [Any], values.count == 6,
                  let role = values[0] as? String else {
                return .native("Incomplete Accessibility information")
            }
            let subrole = values[1] as? String ?? ""
            roles.append(role)
            if firstRole.isEmpty { firstRole = role }
            if role == "AXWindow" || role == "AXApplication" {
                reachedWindow = true
                break
            }
            guard TargetRules.passiveRoles.contains(role) else {
                return .native("Native middle click: \(role) [\(roles.joined(separator: " → "))]")
            }
            let editable = (values[2] as? Bool == true) ||
                (role == "AXTextArea" && isValueSettable(element))
            var actions: CFArray?
            guard AXUIElementCopyActionNames(element, &actions) == .success else {
                return .native("App did not expose target actions")
            }
            let actionNames = actions as? [String] ?? []
            let pressable = actionNames.contains { ["AXPress", "AXPick", "AXConfirm"].contains($0) }
            if TargetRules.protected(role: role, subrole: subrole, editable: editable,
                                     pressable: pressable, hasURL: false) {
                return .native("Native middle click: \(role)")
            }
            var bars: ScrollAxes = []
            if usableScrollbar(values[4]) { bars.insert(.vertical) }
            if usableScrollbar(values[5]) { bars.insert(.horizontal) }
            axes.formUnion(ScrollEvidence.axes(role: role, bars: bars, actions: actionNames))
            if isElement(values[3]) { current = (values[3] as! AXUIElement) }
            else { current = nil }
        }
        guard reachedWindow, !axes.isEmpty else { return .native("No confirmed scrolling: \(roles.joined(separator: " → "))") }
        return TargetDecision(axes: axes, pid: pid, reason: "Scrollable content (\(firstRole)); links and controls keep native clicks")
    }

    private func isElement(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID()
    }

    private func usableScrollbar(_ value: Any) -> Bool {
        guard isElement(value) else { return false }
        let scrollbar = value as! AXUIElement
        var enabled: CFTypeRef?
        return AXUIElementCopyAttributeValue(scrollbar, kAXEnabledAttribute as CFString, &enabled) == .success &&
            enabled as? Bool == true
    }

    private func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        // An unknown editor is safer left alone than treated as plain document text.
        return error != .success || settable.boolValue
    }
}
