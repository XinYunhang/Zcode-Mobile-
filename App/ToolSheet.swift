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

    /// Four rows at 46pt plus the drag indicator and a home-indicator inset.
    private let detentHeight: CGFloat = 248

    var body: some View {
        VStack(spacing: 0) {
            row(symbol: "paperclip", title: "附件", value: nil, action: onAttach)
            row(symbol: "square.grid.2x2", title: "插件", value: nil, action: onPlugins)
            row(symbol: "shield.lefthalf.filled", title: "访问权限", value: modeName, action: onPermission)
            row(symbol: "cpu", title: "模型", value: modelName, action: onModel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
        // Approximates the system material; a full sheet is too large an area
        // for actual glass to read well.
        .presentationBackground(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
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
                    .frame(width: 26, height: 26)

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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
