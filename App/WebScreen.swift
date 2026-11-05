import SwiftUI

struct WebScreen: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model: WebModel

    init(url: URL) {
        _model = StateObject(wrappedValue: WebModel(url: url))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZCodeWebView(webView: model.webView)
                .ignoresSafeArea()

            if model.loading {
                ProgressView()
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.trailing, 16)
                    .padding(.bottom, 60)
            }

            if !model.unreachable {
                Menu {
                    Button("重新加载") { model.reload() }
                    Button("清除缓存并重载") { model.clearCacheAndReload() }
                    Divider()
                    Button("更换连接地址", role: .destructive) { session.forget() }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                        .opacity(0.55)
                }
                .padding(12)
            }

            if model.unreachable {
                UnreachableCover(
                    onRetry: { model.checkReachability() },
                    onReload: { model.reload() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.checkReachability()
            }
        }
    }
}

private struct UnreachableCover: View {
    let onRetry: () -> Void
    let onReload: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
            Text("连不上电脑")
                .font(.headline)
            Text("确认电脑上的 ZCode 正在运行，并且网络通畅。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("重试", action: onRetry)
                    .buttonStyle(.borderedProminent)
                Button("重新加载", action: onReload)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(32)
    }
}
