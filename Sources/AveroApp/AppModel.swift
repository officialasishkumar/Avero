import AppKit
import AveroCapture
import AveroCore
import AveroExport
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var displays: [DisplayDescriptor] = []
    @Published var selectedDisplayID: UInt32?
    @Published var status = "Ready."
    @Published var isRecording = false
    @Published var latestArtifact: CaptureArtifact?
    @Published var backgroundImageURL: URL?
    @Published var musicTrackURL: URL?
    @Published var lastExportURL: URL?
    @Published var zoomScale: Double = 1.8
    @Published var musicVolume: Double = 0.28
    @Published var sourceAudioVolume: Double = 1.0

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
            status = "Recorded \(artifact.interactions.count) interaction point(s). Pick a background and song, then export."
        } catch {
            isRecording = false
            status = error.localizedDescription
        }
    }

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else {
            return
        }

        backgroundImageURL = panel.url
        status = "Background image selected."
    }

    func chooseMusicTrack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else {
            return
        }

        musicTrackURL = panel.url
        status = "Song selected."
    }

    func clearBackgroundImage() {
        backgroundImageURL = nil
        status = "Using the built-in gradient background."
    }

    func clearMusicTrack() {
        musicTrackURL = nil
        status = "Background song cleared."
    }

    func exportLatestCapture() async {
        guard let latestArtifact else {
            status = "Record a clip before exporting."
            return
        }

        guard let destinationURL = selectExportURL() else {
            status = "Export cancelled."
            return
        }

        let options = StyledExportOptions(
            backgroundImageURL: backgroundImageURL,
            musicTrackURL: musicTrackURL,
            sourceAudioVolume: Float(sourceAudioVolume),
            musicVolume: Float(musicVolume),
            zoomConfiguration: AutoZoomConfiguration(zoomScale: zoomScale)
        )

        do {
            status = "Exporting final MP4…"
            try await exporter.export(
                artifact: latestArtifact,
                options: options,
                destinationURL: destinationURL
            )
            lastExportURL = destinationURL
            status = "Export complete."
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        } catch {
            status = error.localizedDescription
        }
    }

    func revealLatestCapture() {
        guard let latestArtifact else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([latestArtifact.rawRecordingURL])
    }

    func revealLatestExport() {
        guard let lastExportURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([lastExportURL])
    }

    private func selectExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "avero-export.mp4"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4") ?? .movie]

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }
}
