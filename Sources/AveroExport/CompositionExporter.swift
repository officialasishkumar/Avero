import AppKit
import AveroCore
@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore

@MainActor
public final class CompositionExporter {
    public init() {}

    public func export(
        artifact: CaptureArtifact,
        options: StyledExportOptions,
        destinationURL: URL
    ) async throws {
        let asset = AVURLAsset(url: artifact.rawRecordingURL)
        let duration = try await asset.load(.duration)
        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)

        guard
            let sourceVideoTrack = sourceVideoTracks.first
        else {
            throw ExportError.missingVideoTrack
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.failedToCreateCompositionTrack
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        var audioParameters: [AVMutableAudioMixInputParameters] = []
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)

        if let sourceAudioTrack = sourceAudioTracks.first,
           let compositionSourceAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionSourceAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )

            let sourceAudioParameters = AVMutableAudioMixInputParameters(track: compositionSourceAudioTrack)
            sourceAudioParameters.setVolume(options.sourceAudioVolume, at: .zero)
            audioParameters.append(sourceAudioParameters)
        }

        if let musicTrackURL = options.musicTrackURL {
            let musicAsset = AVURLAsset(url: musicTrackURL)
            let musicDuration = try await musicAsset.load(.duration)
            let musicTracks = try await musicAsset.loadTracks(withMediaType: .audio)

            guard let musicTrack = musicTracks.first else {
                throw ExportError.missingMusicTrack
            }

            guard let compositionMusicTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw ExportError.failedToCreateCompositionTrack
            }

            try Self.loopAudio(
                track: musicTrack,
                sourceDuration: musicDuration,
                into: compositionMusicTrack,
                totalDuration: duration
            )

            let musicParameters = AVMutableAudioMixInputParameters(track: compositionMusicTrack)
            let fadeDuration = min(duration, CMTime(seconds: 0.45, preferredTimescale: 600))
            musicParameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: options.musicVolume,
                timeRange: CMTimeRange(start: .zero, duration: fadeDuration)
            )

            if CMTimeCompare(duration, fadeDuration) > 0 {
                let fadeOutStart = CMTimeSubtract(duration, fadeDuration)
                musicParameters.setVolumeRamp(
                    fromStartVolume: options.musicVolume,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeOutStart, duration: fadeDuration)
                )
            }

            audioParameters.append(musicParameters)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters

        let videoComposition = try makeVideoComposition(
            for: composition,
            sourceSize: artifact.sourceSize,
            duration: duration,
            interactions: artifact.interactions,
            options: options,
            compositionVideoTrack: compositionVideoTrack
        )

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.failedToCreateExportSession
        }

        try? FileManager.default.removeItem(at: destinationURL)

        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix

        try await exportSession.export(to: destinationURL, as: .mp4)
    }

    private func makeVideoComposition(
        for composition: AVMutableComposition,
        sourceSize: CGSize,
        duration: CMTime,
        interactions: [InteractionEvent],
        options: StyledExportOptions,
        compositionVideoTrack: AVMutableCompositionTrack
    ) throws -> AVMutableVideoComposition {
        let planner = AutoZoomPlanner(
            duration: duration.seconds,
            sourceSize: sourceSize,
            interactions: interactions,
            configuration: options.zoomConfiguration
        )

        let canvasRect = CGRect(origin: .zero, size: options.outputSize)
        let contentFrame = Self.aspectFitRect(
            for: sourceSize,
            in: canvasRect.insetBy(dx: options.contentInset, dy: options.contentInset)
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = options.outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        let firstTransform = Self.transform(
            for: planner.keyframes.first?.snapshot ?? .default,
            sourceSize: sourceSize,
            contentFrame: contentFrame
        )
        layerInstruction.setTransform(firstTransform, at: .zero)

        for (current, next) in zip(planner.keyframes, planner.keyframes.dropFirst()) {
            let start = CMTime(seconds: current.time, preferredTimescale: 600)
            let end = CMTime(seconds: next.time, preferredTimescale: 600)

            guard CMTimeCompare(end, start) > 0 else {
                continue
            }

            layerInstruction.setTransformRamp(
                fromStart: Self.transform(for: current.snapshot, sourceSize: sourceSize, contentFrame: contentFrame),
                toEnd: Self.transform(for: next.snapshot, sourceSize: sourceSize, contentFrame: contentFrame),
                timeRange: CMTimeRange(start: start, duration: CMTimeSubtract(end, start))
            )
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = makeAnimationTool(
            canvasRect: canvasRect,
            backgroundImageURL: options.backgroundImageURL
        )
        return videoComposition
    }

    private func makeAnimationTool(canvasRect: CGRect, backgroundImageURL: URL?) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = canvasRect
        parentLayer.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).cgColor

        let backgroundLayer = CALayer()
        backgroundLayer.frame = canvasRect
        backgroundLayer.contentsGravity = .resizeAspectFill

        if let backgroundImageURL,
           let image = NSImage(contentsOf: backgroundImageURL),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundLayer.contents = cgImage
        } else {
            let gradient = CAGradientLayer()
            gradient.frame = canvasRect
            gradient.colors = [
                NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.34, alpha: 1).cgColor,
                NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1).cgColor,
            ]
            gradient.startPoint = CGPoint(x: 0, y: 1)
            gradient.endPoint = CGPoint(x: 1, y: 0)
            parentLayer.addSublayer(gradient)
        }

        if backgroundLayer.contents != nil {
            parentLayer.addSublayer(backgroundLayer)
        }

        let videoLayer = CALayer()
        videoLayer.frame = canvasRect
        parentLayer.addSublayer(videoLayer)

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func transform(for snapshot: ZoomSnapshot, sourceSize: CGSize, contentFrame: CGRect) -> CGAffineTransform {
        let baseScale = min(
            contentFrame.width / max(sourceSize.width, 1),
            contentFrame.height / max(sourceSize.height, 1)
        )
        let scale = baseScale * snapshot.zoomScale
        let center = CGPoint(
            x: snapshot.center.x * sourceSize.width,
            y: snapshot.center.y * sourceSize.height
        )

        let tx = contentFrame.midX - (center.x * scale)
        let ty = contentFrame.midY - (center.y * scale)

        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
    }

    private static func aspectFitRect(for sourceSize: CGSize, in bounds: CGRect) -> CGRect {
        let aspect = min(
            bounds.width / max(sourceSize.width, 1),
            bounds.height / max(sourceSize.height, 1)
        )
        let size = CGSize(width: sourceSize.width * aspect, height: sourceSize.height * aspect)

        return CGRect(
            x: bounds.midX - (size.width / 2),
            y: bounds.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private static func loopAudio(
        track: AVAssetTrack,
        sourceDuration: CMTime,
        into compositionTrack: AVMutableCompositionTrack,
        totalDuration: CMTime
    ) throws {
        guard CMTimeCompare(sourceDuration, .zero) > 0 else {
            return
        }

        var cursor = CMTime.zero

        while CMTimeCompare(cursor, totalDuration) < 0 {
            let remaining = CMTimeSubtract(totalDuration, cursor)
            let insertionDuration = CMTimeMinimum(remaining, sourceDuration)
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertionDuration),
                of: track,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, insertionDuration)
        }
    }
}

public enum ExportError: LocalizedError {
    case missingVideoTrack
    case missingMusicTrack
    case failedToCreateCompositionTrack
    case failedToCreateExportSession

    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            "The raw capture does not contain a video track."
        case .missingMusicTrack:
            "The selected song does not contain an audio track."
        case .failedToCreateCompositionTrack:
            "Avero could not create the media composition tracks for export."
        case .failedToCreateExportSession:
            "Avero could not create the export session."
        }
    }
}
