import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var session: Session

    @State private var text = Store.lastURL?.absoluteString ?? ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴 ZCode 给出的链接", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text("在电脑上打开 ZCode 的手机连接入口，复制完整链接粘贴到这里。链接里含有访问凭证，不要分享给别人。")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy {
                                ProgressView().padding(.trailing, 6)
                            }
                            Text(busy ? "正在连接…" : "连接")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("连接电脑")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }

        guard let url = Store.normalize(text) else {
            error = ProbeFailure.badURL.message
            return
        }

        switch await ConnectionProbe.run(url) {
        case .ok:
            session.connect(url)
        case .failed(let failure):
            error = failure.message
        }
    }
}
