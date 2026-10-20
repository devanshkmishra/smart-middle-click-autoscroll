import Foundation

var count = 0
func check(_ title: String, _ condition: @autoclosure () -> Bool) {
    count += 1
    guard condition() else { fputs("FAIL: \(title)\n", stderr); exit(1) }
    print("PASS: \(title)")
}
let origin = CGPoint(x: 200, y: 200)
let moved = CGPoint(x: 200, y: 250)
let eligible = TargetDecision(axes: [.vertical, .horizontal], pid: 123, reason: "Document")
let native = TargetDecision.native("Link")

do {
    var g = MiddleGesture()
    check("Potential autoscroll owns the entire down/up pair", g.down(2, at: origin, time: 0).delivery == .buffer)
    let token = g.token
    check("A fast release waits for classification", g.up(2, at: origin).delivery == .buffer)
    let result = g.resolve(eligible, token: token, time: 0.02)
    check("Tap starts sticky autoscroll only after confirmed content", g.phase == .stickyScroll && result.effects.contains(.showAnchor))
    check("Exit click is consumed", g.down(0, at: moved, time: 0.03).delivery == .consume && !g.scrolling)
    check("Exit click release is also consumed", g.up(0, at: moved).delivery == .consume)
    check("Next ordinary click passes", g.down(0, at: moved, time: 0.04).delivery == .pass && g.up(0, at: moved).delivery == .pass)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    let token = g.token
    _ = g.up(2, at: origin)
    let result = g.resolve(native, token: token, time: 0.01)
    check("Link click replays the original pair", result.effects == [.replay] && !g.scrolling && g.phase == .idle)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    let result = g.resolve(native, token: g.token, time: 0.01)
    check("Native hold restores down immediately", result.effects == [.replay] && g.phase == .nativePress)
    check("Native drag and release pass through", g.move(to: moved, middleDrag: true).delivery == .pass && g.up(2, at: moved).delivery == .pass)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    let token = g.token
    check("Slow app fails open after 140 ms", g.tick(0.15).effects == [.replay])
    _ = g.resolve(eligible, token: token, time: 0.16)
    check("Late AX reply cannot steal a native click", !g.scrolling && g.up(2, at: origin).delivery == .pass)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    _ = g.resolve(eligible, token: g.token, time: 0.01)
    check("Stationary hold does not scroll", g.phase == .armed && !g.scrolling)
    let move = g.move(to: moved, middleDrag: true)
    check("Holding and moving starts held autoscroll", g.phase == .heldScroll && move.effects.contains(.showAnchor))
    check("Releasing a drag stops rather than latches", g.up(2, at: moved).delivery == .consume && !g.scrolling)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    _ = g.resolve(eligible, token: g.token, time: 0.01)
    let chord = g.down(3, at: origin, time: 0.02)
    check("Side-button chord restores middle down before passing side button", chord.delivery == .pass && chord.effects == [.replay])
    check("Chord middle release remains native", g.up(2, at: origin).delivery == .pass && !g.scrolling)
}
do {
    var g = MiddleGesture()
    check("Modified and already-chorded middle clicks bypass capture", g.down(2, at: origin, time: 0, bypass: true).delivery == .pass && g.phase == .idle)
    check("Other buttons do not start classification", g.down(4, at: origin, time: 0).effects.isEmpty)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    _ = g.resolve(eligible, token: g.token, time: 0.01)
    _ = g.move(to: moved, middleDrag: true)
    check("Esc cancels scrolling", g.interrupt(escape: true).delivery == .consume && !g.scrolling)
    check("Esc during hold still consumes matching wheel release", g.up(2, at: moved).delivery == .consume)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    let token = g.token
    let cancel = g.cancel()
    _ = g.resolve(eligible, token: token, time: 0.01)
    check("Focus loss never replays a click into the new app", !cancel.effects.contains(.replay) && g.phase == .idle)
    check("Focus loss drains owned release", g.up(2, at: origin).delivery == .consume)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    _ = g.move(to: moved, middleDrag: true)
    _ = g.up(2, at: moved)
    _ = g.resolve(eligible, token: g.token, time: 0.1)
    check("Short held drag released during lookup never latches", !g.scrolling)
}
do {
    var g = MiddleGesture()
    _ = g.down(2, at: origin, time: 0)
    check("Keyboard/modifier input restores a pending native click", g.interrupt().effects == [.replay])
    _ = g.up(2, at: origin)
    _ = g.down(2, at: origin, time: 1)
    _ = g.up(2, at: origin)
    _ = g.resolve(eligible, token: g.token, time: 1.01)
    check("Wheel/key cancellation preserves cancelling input", g.interrupt().delivery == .pass && !g.scrolling)
}
for role in ["AXLink", "AXButton", "AXTab", "AXTextField", "AXScrollBar", "AXToolbar", "AXComboBox"] {
    check("Protect \(role)", TargetRules.protected(role: role, subrole: "", editable: false, pressable: false, hasURL: false))
}
check("Preserve custom clickable groups", TargetRules.protected(role: "AXGroup", subrole: "", editable: false, pressable: true, hasURL: false))
check("Preserve editable document surfaces", TargetRules.protected(role: "AXTextArea", subrole: "", editable: true, pressable: false, hasURL: false))
check("Preserve browser tab subroles", TargetRules.protected(role: "AXGroup", subrole: "AXTabButton", editable: false, pressable: false, hasURL: false))
check("Table rows are not confused with tabs", !TargetRules.protected(role: "AXRow", subrole: "AXTableRow", editable: false, pressable: false, hasURL: false))
check("No scroll inside dead zone", ScrollCurve.speed(displacement: 8, multiplier: 1) == 0)
check("Direction and speed are symmetric", ScrollCurve.speed(displacement: 90, multiplier: 1) == -ScrollCurve.speed(displacement: -90, multiplier: 1))
check("Further pointer movement increases speed", ScrollCurve.speed(displacement: 150, multiplier: 1) > ScrollCurve.speed(displacement: 50, multiplier: 1))
check("Speed is capped", ScrollCurve.speed(displacement: 100000, multiplier: 2) == 2200)
check("Scroll speed is time based", abs(ScrollCurve.speed(displacement: 100, multiplier: 1) / 60 * 60 - ScrollCurve.speed(displacement: 100, multiplier: 1)) < 0.0001)
check("Arc scroll area works without scrollbar objects or scroll actions", ScrollEvidence.axes(role: "AXScrollArea", bars: [], actions: []) == [.vertical, .horizontal])
check("Ordinary web groups alone do not start autoscroll", ScrollEvidence.axes(role: "AXGroup", bars: [], actions: []).isEmpty)
check("Native scrollbar axes remain precise", ScrollEvidence.axes(role: "AXScrollArea", bars: .vertical, actions: []) == .vertical)
check("Explicit horizontal scroll actions are recognized", ScrollEvidence.axes(role: "AXGroup", bars: [], actions: ["AXScrollRightByPage"]) == .horizontal)
print("\(count) checks passed.")
