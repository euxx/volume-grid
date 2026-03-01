import Cocoa

@MainActor
final class SystemEventMonitor {
    // Only mutated on MainActor (start/stop); read in deinit after last reference released
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    private var lastEventData: Int?
    private var lastEventTime: Date?
    // Stage 1 debounce: global + local NSEvent monitors both fire for the same
    // key press. This interval deduplicates them so each press is handled once.
    // The 50 ms key-press debounce in VolumeMonitor (Stage 2) is shorter and
    // always fires after this filter has already removed duplicates.
    private let debounceInterval: TimeInterval = 0.1

    init() {}

    deinit {
        let global = globalMonitor
        let local = localMonitor
        let removeMonitors = {
            if let monitor = global { NSEvent.removeMonitor(monitor) }
            if let monitor = local { NSEvent.removeMonitor(monitor) }
        }
        if Thread.isMainThread {
            removeMonitors()
        } else {
            DispatchQueue.main.async { removeMonitors() }
        }
    }

    func start(handler: @escaping @MainActor () -> Void) {
        stop()

        // Global monitor fires on a background thread — dispatch to MainActor
        // to safely access lastEventData/lastEventTime.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            Task { @MainActor in
                self?.process(event: event, handler: handler)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            self?.process(event: event, handler: handler)
            return event
        }
    }

    func stop() {
        defer {
            globalMonitor = nil
            localMonitor = nil
            lastEventData = nil
            lastEventTime = nil
        }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func process(event: NSEvent, handler: @escaping @MainActor () -> Void) {
        guard event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF_0000) >> 16
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard keyState == 0xA else { return }

        let now = Date()
        if let last = lastEventData, last == event.data1, let lastTime = lastEventTime {
            let timeSinceLastEvent = now.timeIntervalSince(lastTime)
            if timeSinceLastEvent < debounceInterval {
                return
            }
        }
        lastEventData = event.data1
        lastEventTime = now

        switch keyCode & 0xFF {
        case 0, 1, 7:
            handler()
        default:
            break
        }
    }
}
