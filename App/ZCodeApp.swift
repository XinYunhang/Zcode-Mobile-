import SwiftUI

@main
struct ZCodeShellApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        if let url = session.url {
            WebScreen(url: url)
        } else {
            PairingView()
        }
    }
}
