import AppKit

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
    checks += 1
}

let location = CGPoint(x: 123, y: 456)
let native = NSEvent.mouseEvent(with: .otherMouseDown, location: location, modifierFlags: [],
    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 789, context: nil,
    eventNumber: 5, clickCount: 1, pressure: 1)!.cgEvent!
native.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 789)
native.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 789)
let factory = ScrollEventFactory()
let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                    wheel1: -17, wheel2: 5, wheel3: 0)!
let result = factory.make(from: native, x: 5, y: -17, pid: 42, tag: 1234)!
check(result.type == .scrollWheel, "Converted event must be a wheel event")
check(native.type == .otherMouseDown, "Original native click must remain unchanged")
check(result.location == native.location, "Scroll must stay at the original content location")
check(NSEvent(cgEvent: result)?.windowNumber == 789, "AppKit destination window must survive conversion")
check(NSEvent(cgEvent: result)?.type == .scrollWheel, "AppKit must interpret the converted event as scrolling")
check(NSEvent(cgEvent: result)?.scrollingDeltaY == -17, "AppKit must see the vertical pixel delta")
check(result.getIntegerValueField(.eventTargetUnixProcessID) == 42, "Scroll must target the classified app")
check(result.getIntegerValueField(.eventSourceUserData) == 1234, "Scroll must carry recursion protection")
for field: CGEventField in [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                            .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
                            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
                            .scrollWheelEventIsContinuous] {
    check(result.getDoubleValueField(field) == wheel.getDoubleValueField(field), "Wheel delta differs for \(field)")
}
if let source = factory.source {
    check(source.localEventsSuppressionInterval == 0, "Generated scrolling must not suppress physical movement")
    check(source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval).contains(.permitLocalMouseEvents),
          "Local mouse events must remain enabled")
} else {
    print("SKIP: 2 event-source checks require a WindowServer session")
}
print("\(checks) scroll-event checks passed (construction only; no events posted)")
