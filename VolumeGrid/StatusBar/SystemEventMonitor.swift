import Cocoa

enum VolumeKey {
    case up, down, mute
}

@MainActor
final class SystemEventMonitor {
    // nonisolated(unsafe): mutated on MainActor (start/stop); read in deinit which may
    // run on an arbitrary thread.  This is safe because deinit only executes after the
    // last strong reference is released, so no concurrent start()/stop() call can be
    // writing these at the same time.
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    // Deduplicates the global + local NSEvent callbacks that both fire for the same
    // physical key press.  They share an identical event.timestamp, so filtering on
    // (data1, timestamp) is exact — unlike an interval window that also swallows fast
    // key-repeat events (which arrive every ~33 ms on key hold).
    private var lastEventData: Int?
    private var lastEventTimestamp: TimeInterval?

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

    func start(handler: @escaping @MainActor (VolumeKey) -> Void) {
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
            lastEventTimestamp = nil
        }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func process(event: NSEvent, handler: @escaping @MainActor (VolumeKey) -> Void) {
        guard event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF_0000) >> 16
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        guard keyState == 0xA else { return }

        // Deduplicate the global + local callbacks for the same physical event: they share
        // an identical event.timestamp.  Key-repeat events arrive ~33 ms apart and therefore
        // have a different timestamp, so they are correctly allowed through.
        if event.data1 == lastEventData, event.timestamp == lastEventTimestamp {
            return
        }
        lastEventData = event.data1
        lastEventTimestamp = event.timestamp

        switch keyCode & 0xFF {
        case 0: handler(.up)  // NX_KEYTYPE_SOUND_UP
        case 1: handler(.down)  // NX_KEYTYPE_SOUND_DOWN
        case 7: handler(.mute)  // NX_KEYTYPE_MUTE
        default: break
        }
    }
}
