import SwiftUI

/// Native chrome floating over the web view: a standalone menu button on the
/// left and a grouped pill on the right, so the page's own header can be blanked
/// underneath without leaving a heavy full-width bar.
struct ShellTopBar: View {
    let online: Bool
    let onMenu: () -> Void
    let onScan: () -> Void
    let onExit: () -> Void
    let onReload: () -> Void
    let onClearCache: () -> Void
    let onChangeLink: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            menuButton
            Spacer(minLength: 0)
            trailingPill
        }
        // The page is dark regardless of the system appearance, so the chrome
        // must render dark too: otherwise the material goes light and the icons
        // would need to be black.
        .environment(\.colorScheme, .dark)
    }

    private var menuButton: some View {
        Button(action: onMenu) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle())
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(online ? Color(red: 0.18, green: 0.75, blue: 0.45)
                             : Color(red: 0.96, green: 0.65, blue: 0.16))
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1.5))
                .padding(6)
        }
        .accessibilityLabel("任务列表")
    }

    private var trailingPill: some View {
        HStack(spacing: 0) {
            Button(action: onScan) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新配对")

            Menu {
                Button("退出任务会话", systemImage: "chevron.backward", action: onExit)
                Divider()
                Button("重新加载", systemImage: "arrow.clockwise", action: onReload)
                Button("清除缓存并重载", systemImage: "trash", action: onClearCache)
                Button("更换连接地址", systemImage: "link", action: onChangeLink)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多")
        }
        .glassSurface(Capsule())
    }
}

extension View {
    /// iOS 26 renders the system Liquid Glass material; older systems fall back
    /// to a blur. The glass branch also carries its own edge treatment, so no
    /// manual border is added on top.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        }
    }
}
