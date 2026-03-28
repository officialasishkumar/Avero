import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Avero")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("macOS-first screen recording with automatic zoom, background image compositing, and soundtrack support.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Scope")
                        .font(.headline)
                    Text("1. Record a display")
                    Text("2. Track click points for auto zoom")
                    Text("3. Export onto a background image")
                    Text("4. Mix in a song during export")
                }

                Spacer()
            }
            .padding(20)
            .background(.quaternary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Detected Displays")
                    .font(.headline)

                if model.displays.isEmpty {
                    Text("No displays loaded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.displays) { display in
                        Text(display.name)
                    }
                }
            }

            Text(model.status)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
        .task {
            await model.refreshDisplays()
        }
    }
}
