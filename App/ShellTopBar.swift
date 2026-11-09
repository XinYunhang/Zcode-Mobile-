import SwiftUI

/// Native chrome floating over the web view: a standalone menu button on the
/// left and a grouped pill on the right, so the page's own header can be blanked
/// underneath without leaving a heavy full-width bar.
struct ShellTopBar: View {
    let online: Bool
    let onMenu: () -> Void
    let onScan: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            menuButton
            Spacer(minLength: 0)
            trailingPill
        }
    }

    private var menuButton: some View {
        Button(action: onMenu) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
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
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新配对")

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多")
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
    }
}
