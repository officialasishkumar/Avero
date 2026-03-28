import AppKit
import AveroCore
import Foundation

@MainActor
final class InteractionMonitor {
    private var mouseDownMonitor: Any?
    private var rightMouseDownMonitor: Any?
    private var recordingStartUptime: TimeInterval?
    private var activeDisplay: DisplayDescriptor?
    private var interactions: [InteractionEvent] = []

    func start(display: DisplayDescriptor) {
        stop()

        activeDisplay = display
        recordingStartUptime = ProcessInfo.processInfo.systemUptime
        interactions = []

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.captureClick()
        }

        rightMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            self?.captureClick()
        }
    }

    func stop() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }

        if let rightMouseDownMonitor {
            NSEvent.removeMonitor(rightMouseDownMonitor)
            self.rightMouseDownMonitor = nil
        }

        recordingStartUptime = nil
        activeDisplay = nil
    }

    func consumeEvents() -> [InteractionEvent] {
        let events = interactions.sorted { $0.timestamp < $1.timestamp }
        interactions = []
        return events
    }

    private func captureClick() {
        guard
            let activeDisplay,
            let recordingStartUptime
        else {
            return
        }

        let location = NSEvent.mouseLocation
        guard activeDisplay.frame.contains(location) else {
            return
        }

        let relativeX = (location.x - activeDisplay.frame.minX) / max(activeDisplay.frame.width, 1)
        let relativeY = (location.y - activeDisplay.frame.minY) / max(activeDisplay.frame.height, 1)
        let timestamp = ProcessInfo.processInfo.systemUptime - recordingStartUptime

        interactions.append(
            InteractionEvent(
                timestamp: timestamp,
                location: NormalizedPoint(x: relativeX, y: relativeY)
            )
        )
    }
}
