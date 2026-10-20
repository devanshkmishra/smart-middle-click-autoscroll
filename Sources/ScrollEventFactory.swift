import AppKit

final class ScrollEventFactory {
    let source: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        let filter: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source?.setLocalEventsFilterDuringSuppressionState(filter, state: .eventSuppressionStateSuppressionInterval)
        source?.setLocalEventsFilterDuringSuppressionState(filter, state: .eventSuppressionStateRemoteMouseDrag)
        return source
    }()

    func make(from click: CGEvent, x: Int32, y: Int32, pid: pid_t, tag: Int64) -> CGEvent? {
        guard let wheel = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: y, wheel2: x, wheel3: 0),
              let event = click.copy() else { return nil }
        // Preserve the original window and window-local position, including
        // AppKit routing data not exposed as public CGEventField constants.
        event.type = .scrollWheel
        event.setSource(source)
        event.timestamp = wheel.timestamp
        event.flags = wheel.flags
        let fields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2, .scrollWheelEventDeltaAxis3,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3,
            .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase
        ]
        for field in fields {
            event.setIntegerValueField(field, value: wheel.getIntegerValueField(field))
        }
        for field: CGEventField in [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
                                    .scrollWheelEventFixedPtDeltaAxis3] {
            event.setDoubleValueField(field, value: wheel.getDoubleValueField(field))
        }
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.eventSourceUserData, value: tag)
        return event
    }
}
