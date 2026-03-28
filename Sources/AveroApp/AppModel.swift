import AveroCapture
import AveroCore
import AveroExport
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [DisplayDescriptor] = []
    @Published var selectedDisplayID: UInt32?
    @Published var status = "Ready."
    @Published var isRecording = false
    @Published var latestArtifact: CaptureArtifact?

    let recorder = ScreenRecorder()
    let exporter = CompositionExporter()

    func refreshDisplays() async {
        do {
            let displays = try await recorder.availableDisplays()
            self.displays = displays
            self.selectedDisplayID = self.selectedDisplayID ?? displays.first?.id
            status = displays.isEmpty
                ? "No shareable displays were found."
                : "Select a display and start recording."
        } catch {
            status = error.localizedDescription
        }
    }

    func startRecording() async {
        guard let selectedDisplayID else {
            status = "Select a display first."
            return
        }

        do {
            status = "Starting recording…"
            try await recorder.startRecording(displayID: selectedDisplayID)
            isRecording = true
            status = "Recording. Click anywhere on the selected display to create auto-zoom focus points."
        } catch {
            isRecording = false
            status = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording else {
            return
        }

        do {
            status = "Stopping recording…"
            let artifact = try await recorder.stopRecording()
            latestArtifact = artifact
            isRecording = false
            status = "Recorded \(artifact.interactions.count) interaction point(s). Export tools are next."
        } catch {
            isRecording = false
            status = error.localizedDescription
        }
    }
}
