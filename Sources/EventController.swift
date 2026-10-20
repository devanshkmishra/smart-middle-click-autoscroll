import AppKit
import ApplicationServices

final class EventController {
    static let eventTag: Int64 = 0x534D4944444C45
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private let classifier = AccessibilityTarget()
    private let indicator = AnchorPanel()
    private let scrollFactory = ScrollEventFactory()
    private var anchorEvent: CGEvent?
    private var buffered: [CGEvent] = []
    private var gesture = MiddleGesture()
    private var lookupPID: pid_t = 0
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var activeSince = 0.0
    private var callbackProxy: CGEventTapProxy?
    private var remainder = CGPoint.zero
    private var lastActivityUpdate = 0.0
    private(set) var status = "Accessibility permission needed"
    private(set) var lastDecision = "Waiting for a middle click"
    private(set) var middleClicks = 0
    private(set) var scrollEventsSent = 0
    var activity: String {
        let distance = Int(hypot(gesture.pointer.x - gesture.anchor.x, gesture.pointer.y - gesture.anchor.y))
        return "\(middleClicks) middle clicks · \(scrollEventsSent) scroll events sent · pointer \(distance) pt from anchor"
    }
    var onChange: (() -> Void)?
    var enabled = true {
        didSet { if !enabled { apply(gesture.cancel()) }; onChange?() }
    }
    var speed = 1.0
    var horizontal = true
    var excludedApps: Set<String> = []
    var running: Bool { tap != nil }

    func prepareForegroundApp() {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        classifier.prepare(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "")
    }

    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            status = "Accessibility permission needed"
            onChange?()
            return
        }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                    .mouseMoved, .scrollWheel, .keyDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                               options: .defaultTap, eventsOfInterest: mask, callback: { proxy, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventController>.fromOpaque(context).takeUnretainedValue()
            controller.callbackProxy = proxy
            defer { controller.callbackProxy = nil }
            return controller.handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            status = "Event tap unavailable — check Accessibility, then Retry"
            onChange?()
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        status = "Ready"
        prepareForegroundApp()
        onChange?()
    }

    func cancel() { apply(gesture.cancel()) }

    func shutdown() {
        cancel()
        timer?.invalidate()
        timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            status = "Event tap recovered; click again"
            onChange?()
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.eventTag,
              event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(ProcessInfo.processInfo.processIdentifier) else {
            return Unmanaged.passUnretained(event)
        }
        let point = event.location
        let now = ProcessInfo.processInfo.systemUptime
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        var step = MiddleGesture.Step()
        switch type {
        case .otherMouseDown, .leftMouseDown, .rightMouseDown:
            let physicalButton = type == .leftMouseDown ? 0 : type == .rightMouseDown ? 1 : button
            if physicalButton == 2 { middleClicks += 1 }
            let app = NSWorkspace.shared.frontmostApplication
            let flags: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
            let chord = (0..<8).contains { $0 != 2 && CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) }
            let bypass = !enabled || app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ||
                excludedApps.contains(app?.bundleIdentifier ?? "") || !event.flags.intersection(flags).isEmpty || chord
            if physicalButton == 2 && bypass {
                lastDecision = !enabled ? "Paused" : excludedApps.contains(app?.bundleIdentifier ?? "") ? "Excluded app" :
                    chord ? "Another mouse button is held" : !event.flags.intersection(flags).isEmpty ? "Keyboard modifier is held" : "App settings window"
                onChange?()
            }
            if physicalButton == 2, gesture.phase == .idle, !bypass {
                lookupPID = app?.processIdentifier ?? 0
                anchorEvent = event.copy()
            }
            step = gesture.down(physicalButton, at: point, time: now, bypass: bypass)
        case .otherMouseUp, .leftMouseUp, .rightMouseUp:
            let physicalButton = type == .leftMouseUp ? 0 : type == .rightMouseUp ? 1 : button
            step = gesture.up(physicalButton, at: point)
        case .mouseMoved, .otherMouseDragged:
            step = gesture.move(to: point, middleDrag: type == .otherMouseDragged && button == 2)
        case .scrollWheel:
            step = gesture.interrupt()
        case .keyDown:
            step = gesture.interrupt(escape: event.getIntegerValueField(.keyboardEventKeycode) == 53)
        case .flagsChanged:
            if !event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty {
                step = gesture.interrupt()
            }
        default: break
        }
        if step.delivery == .buffer {
            if let copy = event.copy() { buffered.append(copy) }
            if buffered.count > 128 { apply(gesture.interrupt()) }
        }
        apply(step)
        return step.delivery == .pass ? Unmanaged.passUnretained(event) : nil
    }

    private func apply(_ step: MiddleGesture.Step) {
        for effect in step.effects {
            switch effect {
            case .lookup(let token):
                let point = gesture.anchor
                let pid = lookupPID
                classifier.inspect(point: point, foregroundPID: pid) { [weak self] result in
                    guard let self, self.gesture.phase == .pending, self.gesture.token == token else { return }
                    self.lastDecision = result.reason
                    let next = self.gesture.resolve(result, token: token, time: ProcessInfo.processInfo.systemUptime)
                    self.apply(next)
                    self.onChange?()
                }
            case .replay:
                // Re-enter after session-level remappers such as Mac Mouse Fix.
                // Tagging our own events prevents recursive interception.
                let events = buffered
                buffered.removeAll()
                for event in events {
                    event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
                    if let proxy = callbackProxy { event.tapPostEvent(proxy) }
                    else { event.post(tap: .cgAnnotatedSessionEventTap) }
                }
            case .clearBuffer:
                buffered.removeAll()
            case .showAnchor:
                activeSince = ProcessInfo.processInfo.systemUptime
                lastTick = activeSince
                remainder = .zero
                indicator.show(at: gesture.anchor)
                status = "Autoscrolling — click or press Esc to stop"
                onChange?()
            case .hideAnchor:
                indicator.orderOut(nil)
                anchorEvent = nil
                remainder = .zero
                status = running ? "Ready" : "Accessibility permission needed"
                onChange?()
            }
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.05, max(0, now - lastTick))
        lastTick = now
        if gesture.phase == .pending && now > 0 {
            let step = gesture.tick(now)
            if step.effects.contains(.replay) { lastDecision = "Accessibility timed out; native click preserved" }
            apply(step)
        }
        guard gesture.scrolling else { return }
        guard enabled, AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == gesture.target.pid,
              now - activeSince < 300 else { cancel(); return }
        // Remappers can consume motion events while their button is held.
        if let point = CGEvent(source: nil)?.location {
            _ = gesture.move(to: point, middleDrag: gesture.phase == .heldScroll)
        }
        if now - lastActivityUpdate >= 1 {
            lastActivityUpdate = now
            onChange?()
        }
        let axes = gesture.target.axes
        if axes.contains(.vertical) {
            remainder.y += -ScrollCurve.speed(displacement: gesture.pointer.y - gesture.anchor.y, multiplier: speed) * elapsed
        }
        if horizontal && axes.contains(.horizontal) {
            remainder.x += -ScrollCurve.speed(displacement: gesture.pointer.x - gesture.anchor.x, multiplier: speed) * elapsed
        }
        let x = Int32(remainder.x.rounded(.towardZero))
        let y = Int32(remainder.y.rounded(.towardZero))
        guard x != 0 || y != 0 else { return }
        remainder.x -= Double(x)
        remainder.y -= Double(y)
        guard let anchorEvent,
              let event = scrollFactory.make(from: anchorEvent, x: x, y: y,
                                             pid: gesture.target.pid, tag: Self.eventTag) else { return }
        // Global posting at the anchor can repeatedly reset the real cursor.
        // Direct delivery retains the click's target without moving the cursor.
        event.postToPid(gesture.target.pid)
        scrollEventsSent += 1
    }
}
