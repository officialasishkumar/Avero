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
        self.keyframes = Self.buildKeyframes(
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
                return Self.lerpSnapshot(from: current.snapshot, to: next.snapshot, progress: progress)
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

    // MARK: - Spring Physics Easing

    /// Under-damped spring easing for zoom-in: slight overshoot gives a snappy, alive feel.
    /// With zeta=0.65, the zoom momentarily overshoots by ~5% then settles — this is the
    /// "snap" that makes Screen Studio's zoom feel cinematic rather than mechanical.
    private static func springEaseIn(_ t: CGFloat) -> CGFloat {
        let omega: CGFloat = 8.0    // natural frequency — higher = faster animation
        let zeta: CGFloat = 0.65    // damping ratio — <1 means underdamped (overshoot)
        let omegaD = omega * sqrt(1 - zeta * zeta)
        return 1 - exp(-zeta * omega * t) * (
            cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t)
        )
    }

    /// Critically-damped spring easing for zoom-out: smooth deceleration with no overshoot,
    /// so the camera settles back to the default view naturally.
    private static func springEaseOut(_ t: CGFloat) -> CGFloat {
        let omega: CGFloat = 8.0
        return 1 - (1 + omega * t) * exp(-omega * t)
    }

    // MARK: - Click Debouncing

    /// Groups rapid clicks in the same area into single zoom events.
    /// Prevents jittery zoom behavior from double-clicks, rapid UI navigation, etc.
    private static func deduplicateInteractions(
        _ interactions: [InteractionEvent],
        debounceWindow: TimeInterval = 0.35,
        proximityThreshold: CGFloat = 0.08
    ) -> [InteractionEvent] {
        let sorted = interactions.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return [] }

        var result: [InteractionEvent] = []
        var cluster: [InteractionEvent] = [sorted[0]]

        for event in sorted.dropFirst() {
            guard let last = cluster.last else {
                cluster = [event]
                continue
            }

            let dt = event.timestamp - last.timestamp
            let dist = hypot(event.location.x - last.location.x, event.location.y - last.location.y)

            if dt < debounceWindow && dist < proximityThreshold {
                cluster.append(event)
            } else {
                result.append(centroidOf(cluster))
                cluster = [event]
            }
        }

        if !cluster.isEmpty {
            result.append(centroidOf(cluster))
        }

        return result
    }

    /// Merges a cluster of nearby clicks into a single event at their centroid.
    private static func centroidOf(_ events: [InteractionEvent]) -> InteractionEvent {
        let avgX = events.map(\.location.x).reduce(0, +) / CGFloat(events.count)
        let avgY = events.map(\.location.y).reduce(0, +) / CGFloat(events.count)
        return InteractionEvent(
            timestamp: events[0].timestamp,
            location: NormalizedPoint(x: avgX, y: avgY)
        )
    }

    // MARK: - Keyframe Generation

    private static func buildKeyframes(
        duration: TimeInterval,
        interactions: [InteractionEvent],
        configuration: AutoZoomConfiguration
    ) -> [ZoomKeyframe] {
        let sorted = deduplicateInteractions(interactions)
        var keyframes = [ZoomKeyframe(time: 0, snapshot: .default)]
        var lastSnapshot = ZoomSnapshot.default

        for (index, interaction) in sorted.enumerated() {
            let focus = ZoomSnapshot(center: interaction.location, zoomScale: configuration.zoomScale)
            let rampInStart = max(interaction.timestamp - configuration.preRoll, 0)
            let nextRampInStart = sorted[safe: index + 1].map { max($0.timestamp - configuration.preRoll, 0) }

            // Anchor the end of the previous state
            append(&keyframes, time: rampInStart, snapshot: lastSnapshot)

            // Spring-eased ramp from lastSnapshot → focus
            addSpringKeyframes(
                &keyframes,
                from: lastSnapshot,
                to: focus,
                startTime: rampInStart,
                endTime: interaction.timestamp,
                easing: springEaseIn
            )

            // Hold at focus
            let holdEnd = min(
                interaction.timestamp + configuration.holdDuration,
                nextRampInStart ?? duration
            )
            append(&keyframes, time: holdEnd, snapshot: focus)

            // Chain zoom if the next interaction is too close
            if let nextRampInStart, holdEnd + configuration.releaseDuration > nextRampInStart {
                lastSnapshot = focus
                continue
            }

            // Spring-eased release from focus → default
            let releaseEnd = min(holdEnd + configuration.releaseDuration, duration)
            addSpringKeyframes(
                &keyframes,
                from: focus,
                to: .default,
                startTime: holdEnd,
                endTime: releaseEnd,
                easing: springEaseOut
            )
            lastSnapshot = .default
        }

        append(&keyframes, time: duration, snapshot: lastSnapshot)
        append(&keyframes, time: duration, snapshot: .default)

        return normalize(keyframes)
    }

    /// Samples the spring curve at 30 fps and emits dense intermediate keyframes.
    /// AVFoundation linearly interpolates between each pair, but with many closely-spaced
    /// keyframes sampled from a spring curve, the overall motion appears spring-like.
    private static func addSpringKeyframes(
        _ keyframes: inout [ZoomKeyframe],
        from start: ZoomSnapshot,
        to end: ZoomSnapshot,
        startTime: TimeInterval,
        endTime: TimeInterval,
        easing: (CGFloat) -> CGFloat
    ) {
        let transitionDuration = endTime - startTime
        guard transitionDuration > 0.01 else {
            append(&keyframes, time: endTime, snapshot: end)
            return
        }

        let sampleInterval: TimeInterval = 1.0 / 30.0
        var t = sampleInterval

        while t < transitionDuration {
            let normalizedT = CGFloat(t / transitionDuration)
            let easedT = easing(normalizedT)
            let snapshot = lerpSnapshot(from: start, to: end, progress: easedT)
            append(&keyframes, time: startTime + t, snapshot: snapshot)
            t += sampleInterval
        }

        append(&keyframes, time: endTime, snapshot: end)
    }

    // MARK: - Interpolation

    private static func lerpSnapshot(from start: ZoomSnapshot, to end: ZoomSnapshot, progress: CGFloat) -> ZoomSnapshot {
        ZoomSnapshot(
            center: NormalizedPoint(
                x: start.center.x + (end.center.x - start.center.x) * progress,
                y: start.center.y + (end.center.y - start.center.y) * progress
            ),
            zoomScale: start.zoomScale + (end.zoomScale - start.zoomScale) * progress
        )
    }

    // MARK: - Helpers

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
