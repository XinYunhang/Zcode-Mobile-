import SwiftUI
import UIKit

/// The native composer.
///
/// Shape follows the reference apps: a fixed 26pt corner that does not grow with
/// the content, controls pinned to the bottom so they ride the corner, and a
/// height that steps by exactly one line each time the draft wraps.
struct ComposerBar: View {
    @Binding var draft: String
    let attachments: [WebModel.PendingAttachment]
    let onPlus: () -> Void
    let onSend: () -> Void

    @FocusState private var focused: Bool
    @State private var previewing: WebModel.PendingAttachment?
    @State private var fieldHeight: CGFloat = 0

    private let corner: CGFloat = 26
    private let button: CGFloat = 30

    var body: some View {
        VStack(spacing: 6) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { item in
                            Button {
                                focused = false
                                previewing = item
                            } label: {
                                thumbnail(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 56)
            }

            bar
        }
        .sheet(item: $previewing) { item in
            AttachmentPreview(item: item)
        }
    }

    private var bar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: button, height: button)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.08), in: Circle())
            .accessibilityLabel("附件")

            TextField("向 ZCode 发送任务…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.vertical, 5)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: FieldHeightKey.self, value: proxy.size.height)
                    }
                )

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: button, height: button)
                    .background(sendTint, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassSurface(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .onPreferenceChange(FieldHeightKey.self) { fieldHeight = $0 }
        // One step per wrapped line reads as growth rather than a jump.
        .animation(.easeInOut(duration: 0.18), value: fieldHeight)
        .environment(\.colorScheme, .dark)
    }

    private func thumbnail(_ item: WebModel.PendingAttachment) -> some View {
        Group {
            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.10)
                    VStack(spacing: 3) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(item.name)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .padding(.horizontal, 3)
                    }
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    private var sendTint: Color {
        canSend ? Color(red: 0.18, green: 0.48, blue: 0.96) : Color.white.opacity(0.18)
    }

    private func submit() {
        guard canSend else { return }
        onSend()
    }
}

private struct FieldHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Full-screen look at one picked file. Images fill the screen; everything else
/// falls back to a file card.
private struct AttachmentPreview: View {
    let item: WebModel.PendingAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(item.name)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
                Spacer()
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
