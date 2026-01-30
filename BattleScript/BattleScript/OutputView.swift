import SwiftUI

struct OutputView: View {
    let output: String
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.black.opacity(0.6)
                .frame(height: 1)
            HStack {
                Text("Output")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

            Divider()

            ScrollView {
                Text(output.isEmpty ? (isRunning ? "Running..." : "Press Run to execute...") : output)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(output.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(8)
                }
            }
        }
    }
}
