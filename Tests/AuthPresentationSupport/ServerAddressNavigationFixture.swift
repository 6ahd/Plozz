import CoreModels
import CoreNetworking
import CoreUI
import FeatureAuth
import FeatureAuthCore
import SwiftUI

struct ServerAddressNavigationFixture: View {
    @State private var router = ManagedProviderSetupRouter()
    private let accounts: [Account]
    private let store: AccountStore

    init() {
        let server = MediaServer(id: "fixture", name: "Example media server",
                                baseURL: URL(string: "https://media.example.test")!, provider: .jellyfin)
        let names = ProcessInfo.processInfo.arguments.contains("--multiple-address-signins") ? ["Alice", "Bob"] : ["Alice"]
        accounts = names.map { Account(id: $0, server: server, userID: $0, userName: $0, deviceID: "fixture") }
        store = AccountStore(secureStore: InMemorySecureStore())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Example media server").font(.title)
                SettingsSectionGroup("Connection addresses") {
                    ServerAddressSettingsLink(accounts: accounts)
                }
            }
            .padding(32)
        }
        .environment(\.managedProviderSetupRouter, router)
        .sheet(item: $router.addressAccount) { account in
            ServerAddressesView(account: account, store: store, isAuthorized: { true }, onChanged: {})
        }
        .environment(\.themePalette, .dark)
        .preferredColorScheme(.dark)
    }
}
