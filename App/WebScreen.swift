import SwiftUI

struct WebScreen: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model: WebModel

    @State private var showingPairing = false
    @State private var showingMore = false

    init(url: URL) {
        _model = StateObject(wrappedValue: WebModel(url: url))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZCodeWebView(webView: model.webView)
                .ignoresSafeArea()

            // Only over the conversation: the task list has its own header that
            // this bar would otherwise cover.
            if model.isChat {
                ShellTopBar(
                    online: !model.unreachable,
                    onMenu: { Task { await model.exitToTaskList() } },
                    onScan: { showingPairing = true },
                    onMore: { showingMore = true }
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .transition(.opacity)
            }

            if model.loading {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
            }

            if model.unreachable {
                UnreachableCover(
                    onRetry: { model.checkReachability() },
                    onReload: { model.reload() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isChat)
        .sheet(isPresented: $showingPairing) {
            PairingView()
                .environmentObject(session)
        }
        .confirmationDialog("会话", isPresented: $showingMore, titleVisibility: .hidden) {
            Button("退出任务会话") { Task { await model.exitToTaskList() } }
            Button("重新加载") { model.reload() }
            Button("清除缓存并重载") { model.clearCacheAndReload() }
            Button("更换连接地址") { session.forget() }
            Button("取消", role: .cancel) {}
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
