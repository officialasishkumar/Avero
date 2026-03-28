import AveroCore
import Foundation

@MainActor
public final class CompositionExporter {
    public init() {}

    public func export(
        artifact: CaptureArtifact,
        options: StyledExportOptions,
        destinationURL: URL
    ) async throws {
        throw ExportError.unimplemented
    }
}

public enum ExportError: LocalizedError {
    case unimplemented

    public var errorDescription: String? {
        switch self {
        case .unimplemented:
            "The exporter has not been wired up yet."
        }
    }
}
