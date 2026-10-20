import Foundation
import CoreGraphics

struct ScrollAxes: OptionSet, Equatable {
    let rawValue: Int
    static let vertical = ScrollAxes(rawValue: 1)
    static let horizontal = ScrollAxes(rawValue: 2)
}

struct TargetDecision {
    var axes: ScrollAxes = []
    var pid: Int32 = 0
    var reason: String
    var eligible: Bool { !axes.isEmpty && pid > 0 }
    static func native(_ reason: String) -> TargetDecision { TargetDecision(reason: reason) }
}

// Keep this independent of AX and the event tap so event ownership can be tested.
struct MiddleGesture {
    enum Phase: Equatable { case idle, pending, armed, heldScroll, stickyScroll, nativePress }
    enum Delivery: Equatable { case pass, buffer, consume }
    enum Effect: Equatable { case lookup(Int), replay, clearBuffer, showAnchor, hideAnchor }
    struct Step {
        var delivery: Delivery = .pass
        var effects: [Effect] = []
    }
    private(set) var phase: Phase = .idle
    private(set) var token = 0
    private(set) var anchor = CGPoint.zero
    private(set) var pointer = CGPoint.zero
    private(set) var target = TargetDecision.native("Waiting for a middle click")
    private var started = 0.0
    private var released = false
    private var draggedWhileHeld = false
    private var eatUps: Set<Int> = []
    var scrolling: Bool { phase == .heldScroll || phase == .stickyScroll }
    var busy: Bool { phase != .idle && phase != .nativePress }

    mutating func down(_ button: Int, at point: CGPoint, time: Double, bypass: Bool = false) -> Step {
        pointer = point
        if scrolling {
            eatUps.insert(button)
            return stop(delivery: .consume)
        }
        if phase == .pending || phase == .armed {
            return nativeFallback()
        }
        guard button == 2, phase == .idle, !bypass, eatUps.isEmpty else { return Step() }
        token += 1
        phase = .pending
        anchor = point
        started = time
        released = false
        draggedWhileHeld = false
        return Step(delivery: .buffer, effects: [.lookup(token)])
    }

    mutating func up(_ button: Int, at point: CGPoint) -> Step {
        pointer = point
        if eatUps.remove(button) != nil { return Step(delivery: .consume) }
        guard button == 2 else { return Step() }
        switch phase {
        case .pending:
            released = true
            return Step(delivery: .buffer)
        case .armed:
            phase = .stickyScroll
            return Step(delivery: .consume, effects: [.clearBuffer, .showAnchor])
        case .heldScroll:
            return stop(delivery: .consume)
        case .nativePress:
            phase = .idle
            return Step()
        default: return Step()
        }
    }

    mutating func move(to point: CGPoint, middleDrag: Bool) -> Step {
        pointer = point
        let moved = hypot(point.x - anchor.x, point.y - anchor.y) > 10
        if phase == .pending {
            if middleDrag && !released && moved { draggedWhileHeld = true }
            return Step(delivery: middleDrag ? .buffer : .pass)
        }
        if phase == .armed && moved {
            phase = .heldScroll
            return Step(delivery: .consume, effects: [.clearBuffer, .showAnchor])
        }
        return Step(delivery: phase == .heldScroll && middleDrag ? .consume : .pass)
    }

    mutating func resolve(_ value: TargetDecision, token incoming: Int, time: Double) -> Step {
        guard phase == .pending, incoming == token else { return Step() }
        target = value
        guard value.eligible, time - started < 0.14 else { return nativeFallback() }
        if released {
            if draggedWhileHeld {
                phase = .idle
                return Step(effects: [.clearBuffer])
            }
            phase = .stickyScroll
            return Step(effects: [.clearBuffer, .showAnchor])
        }
        phase = .armed
        return move(to: pointer, middleDrag: true)
    }

    mutating func tick(_ time: Double) -> Step {
        if phase == .pending && time - started >= 0.14 { return nativeFallback() }
        return Step()
    }

    mutating func interrupt(escape: Bool = false) -> Step {
        if phase == .pending || phase == .armed { return nativeFallback() }
        if scrolling {
            if phase == .heldScroll { eatUps.insert(2) }
            return stop(delivery: escape ? .consume : .pass)
        }
        return Step()
    }

    // Focus changes and shutdown must never replay a click into a different app.
    mutating func cancel() -> Step {
        if (phase == .pending && !released) || phase == .armed || phase == .heldScroll {
            eatUps.insert(2)
        }
        phase = .idle
        token += 1
        return Step(effects: [.clearBuffer, .hideAnchor])
    }

    private mutating func nativeFallback() -> Step {
        phase = released ? .idle : .nativePress
        token += 1
        return Step(effects: [.replay])
    }

    private mutating func stop(delivery: Delivery) -> Step {
        // A click may stop scrolling before the originally captured wheel is released.
        if phase == .heldScroll { eatUps.insert(2) }
        phase = .idle
        return Step(delivery: delivery, effects: [.clearBuffer, .hideAnchor])
    }
}

enum TargetRules {
    static let passiveRoles: Set<String> = [
        "AXStaticText", "AXGroup", "AXLayoutArea", "AXLayoutItem", "AXImage",
        "AXWebArea", "AXScrollArea", "AXList", "AXTable", "AXOutline", "AXRow",
        "AXCell", "AXHeading", "AXParagraph", "AXDocument", "AXSection", "AXTextArea",
        "AXSplitGroup", "AXBrowser", "AXColumn"
    ]
    static let protectedRoles: Set<String> = [
        "AXLink", "AXButton", "AXRadioButton", "AXCheckBox", "AXPopUpButton",
        "AXMenuButton", "AXTab", "AXTabGroup", "AXTextField", "AXComboBox",
        "AXSearchField", "AXSlider", "AXScrollBar", "AXMenu", "AXMenuItem",
        "AXMenuBar", "AXToolbar", "AXIncrementor", "AXColorWell", "AXDisclosureTriangle"
    ]
    static func protected(role: String, subrole: String, editable: Bool, pressable: Bool, hasURL: Bool) -> Bool {
        protectedRoles.contains(role) || ["AXTab", "AXTabButton"].contains(subrole) ||
            editable || pressable || hasURL
    }
}

enum ScrollCurve {
    static func speed(displacement: Double, multiplier: Double) -> Double {
        let distance = max(0, abs(displacement) - 10)
        let magnitude = min(2200, pow(distance / 100, 1.4) * 450 * multiplier)
        return displacement < 0 ? -magnitude : magnitude
    }
}

enum ScrollEvidence {
    static func axes(role: String, bars: ScrollAxes, actions: [String]) -> ScrollAxes {
        var result = bars
        if actions.contains("AXScrollDownByPage") || actions.contains("AXScrollUpByPage") { result.insert(.vertical) }
        if actions.contains("AXScrollLeftByPage") || actions.contains("AXScrollRightByPage") { result.insert(.horizontal) }
        // Chromium's scroll-area wrapper may omit both scrollbar objects and
        // page-scroll actions. Native wheel dispatch at the anchor chooses the
        // actual inner scroller, including nested web panels.
        if result.isEmpty && role == "AXScrollArea" { result = [.vertical, .horizontal] }
        return result
    }
}
