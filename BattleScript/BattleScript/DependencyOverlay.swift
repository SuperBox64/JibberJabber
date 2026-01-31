import SwiftUI

struct DependencyOverlay: View {
    let status: DependencyStatus?
    @Binding var isVisible: Bool
    @State private var showRow1 = false
    @State private var showRow2 = false
    @State private var showRow3 = false
    @State private var dismissing = false

    private let items: [(keyPath: KeyPath<DependencyStatus, Bool>, name: String, hint: String)] = [
        (\.xcodeTools, "Xcode Command Line Tools", "xcode-select --install"),
        (\.go, "Go", "brew install go"),
        (\.quickjs, "QuickJS", "brew install quickjs"),
    ]

    var body: some View {
        if isVisible, let status {
            ZStack(alignment: .top) {
                Color(nsColor: .shadowColor).opacity(0.4)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("System Check")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.bottom, 4)

                    row(ok: status.xcodeTools, name: items[0].name, hint: items[0].hint, show: showRow1)
                    row(ok: status.go, name: items[1].name, hint: items[1].hint, show: showRow2)
                    row(ok: status.quickjs, name: items[2].name, hint: items[2].hint, show: showRow3)

                    if !status.allGood {
                        Button("Dismiss") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        .shadow(radius: 20)
                )
                .frame(width: 320)
                .padding(.top, 80)
                .scaleEffect(dismissing ? 0.8 : 1.0)
                .opacity(dismissing ? 0 : 1)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.3).delay(0.2)) { showRow1 = true }
                withAnimation(.easeOut(duration: 0.3).delay(0.4)) { showRow2 = true }
                withAnimation(.easeOut(duration: 0.3).delay(0.6)) { showRow3 = true }

                if status.allGood {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(ok: Bool, name: String, hint: String, show: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                if !ok {
                    Text(hint)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .opacity(show ? 1 : 0)
        .offset(y: show ? 0 : 8)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.3)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isVisible = false
        }
    }
}
