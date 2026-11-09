import SwiftUI

/// The native composer. The page's own input lives inside the web view, which
/// can only approximate the system material, so the visible bar is drawn here
/// and the draft is handed to the page's editor on send.
struct ComposerBar: View {
    @Binding var draft: String
    let onPlus: () -> Void
    let onSend: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.08), in: Circle())
            .accessibilityLabel("附件")

            TextField("向 ZCode 发送任务…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.vertical, 9)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(sendTint, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .glassSurface(Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendTint: Color {
        canSend ? Color(red: 0.18, green: 0.48, blue: 0.96) : Color.white.opacity(0.18)
    }

    private func submit() {
        guard canSend else { return }
        onSend()
    }
}
