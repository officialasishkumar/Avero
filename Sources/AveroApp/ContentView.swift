import AveroCore
import Foundation
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            recorderCard
            latestCaptureCard
            statusBar
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.16),
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            await model.refreshDisplays()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Avero")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Record a display now. Automatic zoom events are captured from your clicks and fed into the export pipeline.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recorder")
                .font(.headline)
                .foregroundStyle(.white)

            Picker("Display", selection: $model.selectedDisplayID) {
                if model.displays.isEmpty {
                    Text("No displays available").tag(UInt32?.none)
                } else {
                    ForEach(model.displays) { display in
                        Text(display.name).tag(UInt32?.some(display.id))
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isRecording)

            HStack(spacing: 12) {
                Button("Refresh Displays") {
                    Task {
                        await model.refreshDisplays()
                    }
                }
                .buttonStyle(.bordered)

                Button(model.isRecording ? "Recording…" : "Start Recording") {
                    Task {
                        await model.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRecording || model.selectedDisplayID == nil)

                Button("Stop Recording") {
                    Task {
                        await model.stopRecording()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!model.isRecording)
            }
        }
        .padding(22)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var latestCaptureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Latest Capture")
                .font(.headline)
                .foregroundStyle(.white)
            latestCaptureDetails
        }
        .padding(22)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var statusBar: some View {
        Text(model.status)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white.opacity(0.88))
    }

    @ViewBuilder
    private var latestCaptureDetails: some View {
        if let latestArtifact = model.latestArtifact {
            latestCaptureSummary(for: latestArtifact)
        } else {
            Text("Record once to create a raw clip and click map.")
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private func latestCaptureSummary(for artifact: CaptureArtifact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(artifact.rawRecordingURL.path)
                .textSelection(.enabled)
                .foregroundStyle(.white.opacity(0.72))

            Text("Interactions: \(artifact.interactions.count)")
                .foregroundStyle(.white)

            if artifact.interactions.isEmpty {
                Text("No click events were captured in this recording.")
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                interactionList(for: artifact.interactions)
            }
        }
    }

    private func interactionList(for interactions: [InteractionEvent]) -> some View {
        let preview = Array(interactions.prefix(6))

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(preview.indices, id: \.self) { index in
                Text(interactionLine(index: index, interaction: preview[index]))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    private func interactionLine(index: Int, interaction: InteractionEvent) -> String {
        let timestamp = String(format: "%.2f", interaction.timestamp)
        let x = String(format: "%.2f", interaction.location.x)
        let y = String(format: "%.2f", interaction.location.y)
        return "\(index + 1). \(timestamp)s at (\(x), \(y))"
    }
}
