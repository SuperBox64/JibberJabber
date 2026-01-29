import SwiftUI

struct EditorTabView: View {
    @Binding var selectedTab: String
    let targets: [String]
    @Binding var sourceCode: String
    let transpiledOutputs: [String: String]
    let onRun: () -> Void

    private let tabColors: [String: Color] = [
        "jj": .purple,
        "py": .blue,
        "js": .yellow,
        "c": .gray,
        "cpp": .teal,
        "swift": .orange,
        "objc": .mint,
        "objcpp": .yellow,
        "go": .cyan,
        "asm": .green,
        "applescript": .indigo,
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(targets, id: \.self) { target in
                    Button(action: { selectedTab = target }) {
                        Text(target.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(selectedTab == target ? .bold : .regular)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(selectedTab == target ? (tabColors[target] ?? .gray).opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == target ? (tabColors[target] ?? .primary) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onRun) {
                    Label("Run", systemImage: "play.fill")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content area
            if selectedTab == "jj" {
                TextEditor(text: $sourceCode)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                ScrollView {
                    Text(transpiledOutputs[selectedTab] ?? "// No output")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(tabColors[selectedTab] ?? .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}
