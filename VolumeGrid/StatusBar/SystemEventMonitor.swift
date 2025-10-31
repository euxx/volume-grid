import Cocoa

/// Dedicated handler for listening to system-defined events (e.g. global volume keys).
final class SystemEventMonitor: @unchecked Sendable {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastSignature: (timestamp: TimeInterval, data: Int)?

    nonisolated init() {}

    @MainActor
    func start(handler: @escaping @MainActor () -> Void) {
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            self?.process(event: event, handler: handler)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            self?.process(event: event, handler: handler)
            return event
        }
    }

    @MainActor
    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        lastSignature = nil
    }

    @MainActor
    private func process(event: NSEvent, handler: @escaping @MainActor () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.process(event: event, handler: handler)
            }
            return
        }

        guard event.subtype.rawValue == 8 else { return }
        let keyCode = (event.data1 & 0xFFFF_0000) >> 16
        let keyFlags = event.data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isKeyDown = keyState == 0xA
        guard isKeyDown else { return }

        let signature = (timestamp: event.timestamp, data: event.data1)
        if let last = lastSignature,
            abs(last.timestamp - signature.timestamp) < 0.0001,
            last.data == signature.data
        {
            return
        }
        lastSignature = signature

        switch keyCode & 0xFF {
        case 0, 1, 7:
            handler()
        default:
            break
        }
    }
}
