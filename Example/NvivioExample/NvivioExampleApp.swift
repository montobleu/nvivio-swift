import Nvivio
import SwiftUI

@main
struct NvivioExampleApp: App {
    @State private var tab = "home"

    init() {
        Nvivio.debug = true
        // The local ingest Worker (apps/ingest); leave out `endpoint` for nviv.io.
        Nvivio.start(site: "NV-9NR1XFQ", endpoint: URL(string: "http://localhost:8797/a")!)
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                HomeView().tabItem { Label("Home", systemImage: "house") }.tag("home")
                ProductsView().tabItem { Label("Products", systemImage: "bag") }.tag("products")
                SettingsView().tabItem { Label("Settings", systemImage: "gear") }.tag("settings")
            }
            // nvivioexample://products?utm_source=newsletter opens Products with its campaign.
            .onOpenURL { url in
                Nvivio.open(url)
                if let host = url.host, ["home", "products", "settings"].contains(host) { tab = host }
            }
        }
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            Text("Welcome to the Nvivio example.")
                .navigationTitle("Home")
        }
        .nvivioScreen("Home")
    }
}

struct ProductsView: View {
    @State private var bought = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Button("Buy Pro") {
                    Nvivio.event("Purchase", ["plan": "pro"])
                    bought += 1
                }
                .buttonStyle(.borderedProminent)
                Text("Purchases: \(bought)")
            }
            .navigationTitle("Products")
        }
        .nvivioScreen("Products")
    }
}

struct SettingsView: View {
    /// A real app keeps this choice in its own settings and sets `isEnabled` at launch:
    /// the SDK remembers nothing.
    @State private var analytics = Nvivio.isEnabled

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Share anonymous usage statistics", isOn: $analytics)
                    .onChange(of: analytics) { _, on in Nvivio.isEnabled = on }
            }
            .navigationTitle("Settings")
        }
        .nvivioScreen("Settings")
    }
}
