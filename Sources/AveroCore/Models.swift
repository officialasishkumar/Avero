import CoreGraphics
import Foundation

public struct NormalizedPoint: Codable, Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let center = NormalizedPoint(x: 0.5, y: 0.5)

    public func clamped() -> NormalizedPoint {
        NormalizedPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

public struct InteractionEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var timestamp: TimeInterval
    public var location: NormalizedPoint

    public init(id: UUID = UUID(), timestamp: TimeInterval, location: NormalizedPoint) {
        self.id = id
        self.timestamp = timestamp
        self.location = location.clamped()
    }
}

public struct DisplayDescriptor: Identifiable, Hashable, Sendable {
    public var id: UInt32
    public var name: String
    public var frame: CGRect
    public var pointSize: CGSize
    public var pixelSize: CGSize

    public init(id: UInt32, name: String, frame: CGRect, pointSize: CGSize, pixelSize: CGSize) {
        self.id = id
        self.name = name
        self.frame = frame
        self.pointSize = pointSize
        self.pixelSize = pixelSize
    }
}

public struct CaptureArtifact: Hashable, Sendable {
    public var rawRecordingURL: URL
    public var sourceSize: CGSize
    public var interactions: [InteractionEvent]

    public init(rawRecordingURL: URL, sourceSize: CGSize, interactions: [InteractionEvent]) {
        self.rawRecordingURL = rawRecordingURL
        self.sourceSize = sourceSize
        self.interactions = interactions.sorted { $0.timestamp < $1.timestamp }
    }
}

public struct AutoZoomConfiguration: Hashable, Sendable {
    public var zoomScale: CGFloat
    public var preRoll: TimeInterval
    public var holdDuration: TimeInterval
    public var releaseDuration: TimeInterval

    public init(
        zoomScale: CGFloat = 1.8,
        preRoll: TimeInterval = 0.18,
        holdDuration: TimeInterval = 0.9,
        releaseDuration: TimeInterval = 0.35
    ) {
        self.zoomScale = zoomScale
        self.preRoll = preRoll
        self.holdDuration = holdDuration
        self.releaseDuration = releaseDuration
    }
}

public struct ZoomSnapshot: Hashable, Sendable {
    public var center: NormalizedPoint
    public var zoomScale: CGFloat

    public init(center: NormalizedPoint, zoomScale: CGFloat) {
        self.center = center.clamped()
        self.zoomScale = max(zoomScale, 1)
    }

    public static let `default` = ZoomSnapshot(center: .center, zoomScale: 1)
}

public struct StyledExportOptions: Hashable, Sendable {
    public var outputSize: CGSize
    public var contentInset: CGFloat
    public var backgroundImageURL: URL?
    public var musicTrackURL: URL?
    public var sourceAudioVolume: Float
    public var musicVolume: Float
    public var zoomConfiguration: AutoZoomConfiguration

    public init(
        outputSize: CGSize = CGSize(width: 1920, height: 1080),
        contentInset: CGFloat = 96,
        backgroundImageURL: URL? = nil,
        musicTrackURL: URL? = nil,
        sourceAudioVolume: Float = 1,
        musicVolume: Float = 0.28,
        zoomConfiguration: AutoZoomConfiguration = .init()
    ) {
        self.outputSize = outputSize
        self.contentInset = contentInset
        self.backgroundImageURL = backgroundImageURL
        self.musicTrackURL = musicTrackURL
        self.sourceAudioVolume = sourceAudioVolume
        self.musicVolume = musicVolume
        self.zoomConfiguration = zoomConfiguration
    }
}
