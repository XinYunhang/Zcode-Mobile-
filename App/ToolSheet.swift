import SwiftUI

/// The native replacement for the page's attachment menu. Plugin browsing is
/// still handed back to the web panel, so this carries only the rows we can own
/// end to end.
struct ToolSheet: View {
    let modelName: String
    let modeName: String
    let onAttach: () -> Void
    let onPlugins: () -> Void
    let onPermission: () -> Void
    let onModel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(symbol: "paperclip", title: "附件", value: nil, action: onAttach)
            divider
            row(symbol: "square.grid.2x2", title: "插件", value: nil, action: onPlugins)
            divider
            row(symbol: "shield.lefthalf.filled", title: "访问权限", value: modeName, action: onPermission)
            divider
            row(symbol: "cpu", title: "模型", value: modelName, action: onModel)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 40)
    }

    private func row(
        symbol: String,
        title: String,
        value: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                if let value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
