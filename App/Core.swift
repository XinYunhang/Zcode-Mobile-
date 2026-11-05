import Foundation
import SwiftUI

// MARK: - Persistence

/// The remote link carries a session credential, so it is never compiled in.
/// It lives in UserDefaults and is only ever supplied by the user.
enum Store {
    private static let key = "zcode.remote.url"
    private static let lastKey = "zcode.remote.lastURL"

    static var url: URL? {
        UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:))
    }

    /// Kept after the active link is cleared, so the pairing screen can offer the
    /// previous address for editing instead of an empty field.
    static var lastURL: URL? {
        UserDefaults.standard.string(forKey: lastKey).flatMap(URL.init(string:))
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: key)
        UserDefaults.standard.set(url.absoluteString, forKey: lastKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Accepts a pasted link with or without a scheme, plus stray whitespace
    /// from the clipboard.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}

// MARK: - Session

final class Session: ObservableObject {
    @Published private(set) var url: URL? = Store.url

    func connect(_ url: URL) {
        Store.save(url)
        self.url = url
    }

    func forget() {
        Store.clear()
        url = nil
    }
}

// MARK: - Reachability probe

enum ProbeFailure {
    case badURL
    case dns
    case refused
    case timeout
    case tls
    case offline
    case other

    var message: String {
        switch self {
        case .badURL:
            return "链接格式不对，请重新复制 ZCode 给出的完整地址。"
        case .dns:
            return "找不到这个域名。检查手机网络，或确认链接是否完整。"
        case .refused:
            return "连接被拒绝。电脑上的 ZCode 可能没有在运行。"
        case .timeout:
            return "连接超时。检查网络，或确认电脑是否在线。"
        case .tls:
            return "TLS 握手失败，可能是网络中间人拦截。"
        case .offline:
            return "手机当前没有网络。"
        case .other:
            return "连接失败，请稍后重试。"
        }
    }
}

enum ProbeResult {
    case ok
    case failed(ProbeFailure)
}

enum ConnectionProbe {
    /// Any HTTP response — even a 4xx — proves the host is reachable, so this
    /// only fails on transport errors.
    static func run(_ url: URL, timeout: TimeInterval = 6) async -> ProbeResult {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            _ = try await URLSession.shared.data(for: request)
            return .ok
        } catch let error as URLError {
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed:
                return .failed(.dns)
            case .cannotConnectToHost:
                return .failed(.refused)
            case .timedOut:
                return .failed(.timeout)
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid:
                return .failed(.tls)
            case .notConnectedToInternet, .networkConnectionLost:
                return .failed(.offline)
            default:
                return .failed(.other)
            }
        } catch {
            return .failed(.other)
        }
    }
}
