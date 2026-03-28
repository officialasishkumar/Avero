import CoreGraphics
import Foundation

public struct ZoomKeyframe: Hashable, Sendable {
    public var time: TimeInterval
    public var snapshot: ZoomSnapshot

    public init(time: TimeInterval, snapshot: ZoomSnapshot) {
        self.time = max(time, 0)
        self.snapshot = snapshot
    }
}

public struct AutoZoomPlanner: Sendable {
    public let duration: TimeInterval
    public let sourceSize: CGSize
    public let configuration: AutoZoomConfiguration
    public let keyframes: [ZoomKeyframe]

    public init(
        duration: TimeInterval,
        sourceSize: CGSize,
        interactions: [InteractionEvent],
        configuration: AutoZoomConfiguration
    ) {
        self.duration = max(duration, 0)
        self.sourceSize = sourceSize
        self.configuration = configuration
        self.keyframes = AutoZoomPlanner.buildKeyframes(
            duration: duration,
            interactions: interactions,
            configuration: configuration
        )
    }

    public func snapshot(at time: TimeInterval) -> ZoomSnapshot {
        guard let first = keyframes.first else {
            return .default
        }

        if time <= first.time {
            return first.snapshot
        }

        for index in 0..<(keyframes.count - 1) {
            let current = keyframes[index]
            let next = keyframes[index + 1]

            if time >= current.time && time <= next.time {
                let span = max(next.time - current.time, .ulpOfOne)
                let progress = min(max((time - current.time) / span, 0), 1)
                return interpolate(from: current.snapshot, to: next.snapshot, progress: progress)
            }
        }

        return keyframes.last?.snapshot ?? .default
    }

    public func cropRect(at time: TimeInterval) -> CGRect {
        let snapshot = snapshot(at: time)
        let cropWidth = max(sourceSize.width / snapshot.zoomScale, 1)
        let cropHeight = max(sourceSize.height / snapshot.zoomScale, 1)
        let center = CGPoint(
            x: snapshot.center.x * sourceSize.width,
            y: snapshot.center.y * sourceSize.height
        )

        let rawRect = CGRect(
            x: center.x - (cropWidth / 2),
            y: center.y - (cropHeight / 2),
            width: cropWidth,
            height: cropHeight
        )

        return rawRect.clampedPreservingSize(to: CGRect(origin: .zero, size: sourceSize))
    }

    private static func buildKeyframes(
        duration: TimeInterval,
        interactions: [InteractionEvent],
        configuration: AutoZoomConfiguration
    ) -> [ZoomKeyframe] {
        let sorted = interactions.sorted { $0.timestamp < $1.timestamp }
        var keyframes = [ZoomKeyframe(time: 0, snapshot: .default)]
        var lastSnapshot = ZoomSnapshot.default

        for (index, interaction) in sorted.enumerated() {
            let focus = ZoomSnapshot(center: interaction.location, zoomScale: configuration.zoomScale)
            let rampInStart = max(interaction.timestamp - configuration.preRoll, 0)
            let nextRampInStart = sorted[safe: index + 1].map { max($0.timestamp - configuration.preRoll, 0) }

            append(&keyframes, time: rampInStart, snapshot: lastSnapshot)
            append(&keyframes, time: interaction.timestamp, snapshot: focus)

            let holdEnd = min(
                interaction.timestamp + configuration.holdDuration,
                nextRampInStart ?? duration
            )

            append(&keyframes, time: holdEnd, snapshot: focus)

            if let nextRampInStart, holdEnd + configuration.releaseDuration > nextRampInStart {
                lastSnapshot = focus
                continue
            }

            let releaseEnd = min(holdEnd + configuration.releaseDuration, duration)
            append(&keyframes, time: releaseEnd, snapshot: .default)
            lastSnapshot = .default
        }

        append(&keyframes, time: duration, snapshot: lastSnapshot)
        append(&keyframes, time: duration, snapshot: .default)

        return normalize(keyframes)
    }

    private static func append(_ keyframes: inout [ZoomKeyframe], time: TimeInterval, snapshot: ZoomSnapshot) {
        keyframes.append(ZoomKeyframe(time: time, snapshot: snapshot))
    }

    private static func normalize(_ keyframes: [ZoomKeyframe]) -> [ZoomKeyframe] {
        var result: [ZoomKeyframe] = []

        for keyframe in keyframes.sorted(by: { $0.time < $1.time }) {
            if let last = result.last, abs(last.time - keyframe.time) < 0.0001 {
                result[result.count - 1] = keyframe
                continue
            }

            if result.last?.snapshot == keyframe.snapshot,
               let lastTime = result.last?.time,
               abs(lastTime - keyframe.time) < 0.0001 {
                continue
            }

            result.append(keyframe)
        }

        return result
    }

    private func interpolate(from start: ZoomSnapshot, to end: ZoomSnapshot, progress: CGFloat) -> ZoomSnapshot {
        ZoomSnapshot(
            center: NormalizedPoint(
                x: lerp(start.center.x, end.center.x, progress),
                y: lerp(start.center.y, end.center.y, progress)
            ),
            zoomScale: lerp(start.zoomScale, end.zoomScale, progress)
        )
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

private extension CGRect {
    func clampedPreservingSize(to bounds: CGRect) -> CGRect {
        guard width <= bounds.width, height <= bounds.height else {
            return bounds
        }

        let clampedX = min(max(minX, bounds.minX), bounds.maxX - width)
        let clampedY = min(max(minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: clampedX, y: clampedY, width: width, height: height)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
