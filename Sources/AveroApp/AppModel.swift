import AveroCapture
import AveroCore
import AveroExport
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [DisplayDescriptor] = []
    @Published var selectedDisplayID: UInt32?
    @Published var status = "Bootstrapping capture and export pipeline."

    let recorder = ScreenRecorder()
    let exporter = CompositionExporter()

    func refreshDisplays() async {
        do {
            let displays = try await recorder.availableDisplays()
            self.displays = displays
            self.selectedDisplayID = self.selectedDisplayID ?? displays.first?.id
            status = displays.isEmpty
                ? "No shareable displays were found yet."
                : "Avero is ready for the capture and export layers."
        } catch {
            status = error.localizedDescription
        }
    }
}
