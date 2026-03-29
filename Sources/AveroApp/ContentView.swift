import AVFoundation
import AveroCore
import Foundation
import QuartzCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    private let accentPurple = Color(red: 0.55, green: 0.36, blue: 0.96)
    private let surfaceDark = Color(nsColor: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1))
    private let surfaceSidebar = Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    private let surfaceCard = Color(nsColor: NSColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1))
    private let canvasBg = Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    previewArea
                    Divider()
                    timelineArea
                        .frame(height: 72)
                }
                Divider()
                sidebar
                    .frame(width: 280)
            }
            Divider()
            statusBar
        }
        .background(surfaceDark)
        .preferredColorScheme(.dark)
        .task {
            await model.refreshDisplays()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("Avero")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Divider()
                .frame(height: 20)

            Picker("Display", selection: $model.selectedDisplayID) {
                if model.displays.isEmpty {
                    Text("No displays").tag(UInt32?.none)
                } else {
                    ForEach(model.displays) { display in
                        Text(display.name).tag(UInt32?.some(display.id))
                    }
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .disabled(model.isRecording)

            Button {
                Task { await model.refreshDisplays() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(model.isRecording)

            Spacer()

            if model.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
            }

            recordButton
            stopButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(surfaceSidebar)
    }

    private var recordButton: some View {
        Button {
            Task { await model.startRecording() }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isRecording || model.selectedDisplayID == nil ? .gray : .red)
                    .frame(width: 9, height: 9)
                Text("Record")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(model.isRecording || model.selectedDisplayID == nil)
    }

    private var stopButton: some View {
        Button {
            Task { await model.stopRecording() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8))
                Text("Stop")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(!model.isRecording)
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        ZStack {
            canvasBg

            if let player = model.previewPlayer {
                PlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 4)
                    .padding(48)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: model.isRecording ? "record.circle" : "play.rectangle")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(.white.opacity(0.15))
                    Text(model.isRecording ? "Recording in progress…" : "Record a clip to preview")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }

    // MARK: - Timeline

    private var timelineArea: some View {
        VStack(spacing: 0) {
            if let artifact = model.latestArtifact, model.recordingDuration > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(formatTime(0))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.08))
                                    .frame(height: 6)

                                ForEach(artifact.interactions) { event in
                                    let x = max(0, min(
                                        CGFloat(event.timestamp / model.recordingDuration) * geo.size.width,
                                        geo.size.width
                                    ))
                                    Circle()
                                        .fill(accentPurple)
                                        .frame(width: 10, height: 10)
                                        .shadow(color: accentPurple.opacity(0.5), radius: 4)
                                        .position(x: x, y: geo.size.height / 2)
                                }
                            }
                        }
                        .frame(height: 20)

                        Text(formatTime(model.recordingDuration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Text("\(artifact.interactions.count) zoom point\(artifact.interactions.count == 1 ? "" : "s") captured")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            } else {
                HStack {
                    Spacer()
                    Text(model.isRecording ? "Zoom points will appear here when you click" : "No recording yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                }
                .padding(.vertical, 14)
            }
        }
        .background(surfaceDark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                sidebarSection("Background") {
                    filePickerRow(
                        "Choose Image",
                        icon: "photo",
                        fileName: model.backgroundImageURL?.lastPathComponent,
                        chooseAction: model.chooseBackgroundImage,
                        clearAction: model.clearBackgroundImage
                    )
                }

                sidebarSection("Audio") {
                    filePickerRow(
                        "Choose Music",
                        icon: "music.note",
                        fileName: model.musicTrackURL?.lastPathComponent,
                        chooseAction: model.chooseMusicTrack,
                        clearAction: model.clearMusicTrack
                    )
                    sidebarSlider("Music Volume", value: $model.musicVolume, range: 0...1)
                    sidebarSlider("Source Audio", value: $model.sourceAudioVolume, range: 0...1)
                }

                sidebarSection("Zoom") {
                    sidebarSlider("Scale", value: $model.zoomScale, range: 1.1...2.6, format: "%.1fx")
                }

                sidebarSection("Style") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aspect Ratio")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))

                        Picker("", selection: $model.aspectRatio) {
                            ForEach(AspectRatio.allCases, id: \.self) { ratio in
                                Text(ratio.rawValue).tag(ratio)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    sidebarSlider("Corner Radius", value: $model.cornerRadius, range: 0...40, format: "%.0f")
                    sidebarSlider("Shadow", value: $model.shadowRadius, range: 0...60, format: "%.0f")
                    sidebarSlider("Padding", value: $model.contentInset, range: 0...200, format: "%.0f")
                }

                sidebarSection("Export") {
                    VStack(spacing: 10) {
                        Button {
                            Task { await model.exportLatestCapture() }
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12))
                                Text("Export MP4")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentPurple)
                        .disabled(model.latestArtifact == nil || model.isRecording || model.isExporting)

                        HStack(spacing: 8) {
                            Button("Reveal Capture") {
                                model.revealLatestCapture()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(model.latestArtifact == nil)

                            Button("Reveal Export") {
                                model.revealLatestExport()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(model.lastExportURL == nil)
                        }
                        .font(.system(size: 11))

                        if let lastExportURL = model.lastExportURL {
                            Text(lastExportURL.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .background(surfaceSidebar)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(surfaceSidebar)
    }

    // MARK: - Sidebar Helpers

    @ViewBuilder
    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.8)

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()
            .padding(.horizontal, 12)
    }

    private func sidebarSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    private func filePickerRow(
        _ buttonTitle: String,
        icon: String,
        fileName: String?,
        chooseAction: @escaping () -> Void,
        clearAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: chooseAction) {
                    Label(buttonTitle, systemImage: icon)
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if fileName != nil {
                    Button(action: clearAction) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let fileName {
                Text(fileName)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - AVPlayerLayer-based Preview (avoids AVKit crash in SPM executables)

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
