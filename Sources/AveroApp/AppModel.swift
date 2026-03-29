import AppKit
import AVFoundation
import AVKit
import AveroCapture
import AveroCore
import AveroExport
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    // Capture
    @Published var displays: [DisplayDescriptor] = []
    @Published var selectedDisplayID: UInt32?
    @Published var isRecording = false
    @Published var latestArtifact: CaptureArtifact?

    // Preview
    @Published var previewPlayer: AVPlayer?
    @Published var recordingDuration: TimeInterval = 0

    // Background
    @Published var backgroundImageURL: URL?

    // Audio
    @Published var musicTrackURL: URL?
    @Published var musicVolume: Double = 0.28
    @Published var sourceAudioVolume: Double = 1.0

    // Zoom
    @Published var zoomScale: Double = 1.8

    // Style
    @Published var aspectRatio: AspectRatio = .widescreen
    @Published var cornerRadius: Double = 12
    @Published var shadowRadius: Double = 24
    @Published var shadowOpacity: Double = 0.5
    @Published var contentInset: Double = 96

    // Export
    @Published var lastExportURL: URL?
    @Published var isExporting = false

    // Status
    @Published var status = "Ready."

    let recorder = ScreenRecorder()
    let exporter = CompositionExporter()

    // MARK: - Display Management

    func refreshDisplays() async {
        do {
            let displays = try await recorder.availableDisplays()
            self.displays = displays
            self.selectedDisplayID = self.selectedDisplayID ?? displays.first?.id
            status = displays.isEmpty
                ? "No displays found. Grant screen recording permission in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch."
                : "Select a display and start recording."
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: - Recording

    func startRecording() async {
        guard let selectedDisplayID else {
            status = "Select a display first."
            return
        }

        do {
            status = "Starting recording…"
            try await recorder.startRecording(displayID: selectedDisplayID)
            isRecording = true
            status = "Recording. Click anywhere on the selected display to create zoom focus points."
        } catch {
            isRecording = false
            status = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        do {
            status = "Stopping recording…"
            let artifact = try await recorder.stopRecording()
            latestArtifact = artifact
            isRecording = false
            status = "Captured \(artifact.interactions.count) zoom point\(artifact.interactions.count == 1 ? "" : "s"). Adjust settings and export."
            await loadPreview()
        } catch {
            isRecording = false
            status = error.localizedDescription
        }
    }

    // MARK: - Preview

    private func loadPreview() async {
        guard let artifact = latestArtifact else { return }

        let asset = AVURLAsset(url: artifact.rawRecordingURL)
        do {
            let duration = try await asset.load(.duration)
            recordingDuration = duration.seconds
        } catch {
            recordingDuration = 0
        }

        previewPlayer = AVPlayer(url: artifact.rawRecordingURL)
    }

    // MARK: - File Selection

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        backgroundImageURL = panel.url
        status = "Background image selected."
    }

    func chooseMusicTrack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        musicTrackURL = panel.url
        status = "Music track selected."
    }

    func clearBackgroundImage() {
        backgroundImageURL = nil
        status = "Using default gradient background."
    }

    func clearMusicTrack() {
        musicTrackURL = nil
        status = "Music track cleared."
    }

    // MARK: - Export

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
            outputSize: aspectRatio.outputSize,
            contentInset: CGFloat(contentInset),
            cornerRadius: CGFloat(cornerRadius),
            shadowRadius: CGFloat(shadowRadius),
            shadowOpacity: Float(shadowOpacity),
            backgroundImageURL: backgroundImageURL,
            musicTrackURL: musicTrackURL,
            sourceAudioVolume: Float(sourceAudioVolume),
            musicVolume: Float(musicVolume),
            zoomConfiguration: AutoZoomConfiguration(zoomScale: zoomScale)
        )

        do {
            isExporting = true
            status = "Exporting final MP4…"
            try await exporter.export(
                artifact: latestArtifact,
                options: options,
                destinationURL: destinationURL
            )
            lastExportURL = destinationURL
            isExporting = false
            status = "Export complete."
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        } catch {
            isExporting = false
            status = error.localizedDescription
        }
    }

    // MARK: - Reveal

    func revealLatestCapture() {
        guard let latestArtifact else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestArtifact.rawRecordingURL])
    }

    func revealLatestExport() {
        guard let lastExportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastExportURL])
    }

    // MARK: - Helpers

    private func selectExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "avero-export.mp4"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4") ?? .movie]

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
