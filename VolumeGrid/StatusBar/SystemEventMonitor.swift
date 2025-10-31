import Cocoa

@MainActor
final class SystemEventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastEventData: Int?

    init() {}

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

    func stop() {
        defer {
            globalMonitor = nil
            localMonitor = nil
            lastEventData = nil
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

        if let last = lastEventData, last == event.data1 {
            return
        }
        lastEventData = event.data1

        switch keyCode & 0xFF {
        case 0, 1, 7:
            handler()
        default:
            break
        }
    }
}
