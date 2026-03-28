import AveroCore
import Foundation

@MainActor
public final class ScreenRecorder {
    public init() {}

    public func availableDisplays() async throws -> [DisplayDescriptor] {
        []
    }

    public func startRecording(displayID: UInt32) async throws {}

    public func stopRecording() async throws -> CaptureArtifact {
        throw RecorderError.unimplemented
    }
}

public enum RecorderError: LocalizedError {
    case unimplemented

    public var errorDescription: String? {
        switch self {
        case .unimplemented:
            "The recorder has not been wired up yet."
        }
    }
}
