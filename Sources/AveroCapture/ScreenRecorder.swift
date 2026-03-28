import AppKit
import AveroCore
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
public final class ScreenRecorder: NSObject, SCRecordingOutputDelegate {
    private let interactionMonitor = InteractionMonitor()
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var activeDisplay: DisplayDescriptor?
    private var outputURL: URL?
    private var didStartRecording = false
    private var didFinishRecording = false
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var finishContinuation: CheckedContinuation<Void, any Error>?

    public override init() {
        super.init()
    }

    public func availableDisplays() async throws -> [DisplayDescriptor] {
        let shareableContent = try await SCShareableContent.current
        let screenNames = NSScreen.screens.reduce(into: [UInt32: String]()) { partialResult, screen in
            guard
                let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else {
                return
            }

            partialResult[value.uint32Value] = screen.localizedName
        }

        return shareableContent.displays.map { display in
            let id = display.displayID
            let pointSize = CGSize(width: display.width, height: display.height)
            let pixelSize = CGSize(
                width: CGFloat(CGDisplayPixelsWide(id)),
                height: CGFloat(CGDisplayPixelsHigh(id))
            )

            return DisplayDescriptor(
                id: id,
                name: screenNames[id] ?? "Display \(id)",
                frame: display.frame,
                pointSize: pointSize,
                pixelSize: pixelSize
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func startRecording(displayID: UInt32) async throws {
        guard stream == nil else {
            throw RecorderError.alreadyRecording
        }

        let shareableContent = try await SCShareableContent.current
        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayNotFound
        }

        guard let displayDescriptor = try await availableDisplays().first(where: { $0.id == displayID }) else {
            throw RecorderError.displayNotFound
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = Int(displayDescriptor.pixelSize.width.rounded())
        configuration.height = Int(displayDescriptor.pixelSize.height.rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.queueDepth = 5
        configuration.streamName = "Avero Capture"

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = Self.makeRecordingURL()
        outputConfiguration.videoCodecType = .h264
        outputConfiguration.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)

        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.activeDisplay = displayDescriptor
        self.outputURL = outputConfiguration.outputURL
        self.didStartRecording = false
        self.didFinishRecording = false

        do {
            try await stream.startCapture()
            try await waitForRecordingStart()
        } catch {
            cleanup()
            throw error
        }
    }

    public func stopRecording() async throws -> CaptureArtifact {
        guard let stream, let activeDisplay, let outputURL else {
            throw RecorderError.notRecording
        }

        interactionMonitor.stop()

        do {
            try await stream.stopCapture()
            try await waitForRecordingFinish()
        } catch {
            cleanup()
            throw error
        }

        let artifact = CaptureArtifact(
            rawRecordingURL: outputURL,
            sourceSize: activeDisplay.pixelSize,
            interactions: interactionMonitor.consumeEvents()
        )

        cleanup()
        return artifact
    }

    nonisolated public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.handleRecordingDidStart()
        }
    }

    nonisolated public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.handleRecordingDidFinish()
        }
    }

    nonisolated public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.handleRecordingFailure(error)
        }
    }

    private func handleRecordingDidStart() {
        didStartRecording = true

        if let activeDisplay {
            interactionMonitor.start(display: activeDisplay)
        }

        startContinuation?.resume(returning: ())
        startContinuation = nil
    }

    private func handleRecordingDidFinish() {
        didFinishRecording = true
        finishContinuation?.resume(returning: ())
        finishContinuation = nil
    }

    private func handleRecordingFailure(_ error: any Error) {
        if let startContinuation {
            startContinuation.resume(throwing: error)
            self.startContinuation = nil
            return
        }

        if let finishContinuation {
            finishContinuation.resume(throwing: error)
            self.finishContinuation = nil
        }
    }

    private func waitForRecordingStart() async throws {
        if didStartRecording {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func waitForRecordingFinish() async throws {
        if didFinishRecording {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    private func cleanup() {
        stream = nil
        recordingOutput = nil
        activeDisplay = nil
        outputURL = nil
        didStartRecording = false
        didFinishRecording = false
        startContinuation = nil
        finishContinuation = nil
    }

    private static func makeRecordingURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Avero", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("capture-\(formatter.string(from: .now)).mp4")
    }
}

public enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case displayNotFound

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already in progress."
        case .notRecording:
            "There is no active recording to stop."
        case .displayNotFound:
            "The selected display could not be found."
        }
    }
}
