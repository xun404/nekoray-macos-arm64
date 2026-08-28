import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailView
                .toolbar { WindowToolbar() }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredColorScheme)
        .alert("NekoBox", isPresented: Binding(
            get: { state.notice != nil },
            set: { isPresented in if !isPresented { state.clearNotice() } }
        )) {
            Button("OK", role: .cancel) { state.clearNotice() }
        } message: {
            Text(state.notice ?? "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedSidebarItem {
        case .overview: OverviewView()
        case .proxies: ProxiesView()
        case .connections: ConnectionsView()
        case .logs: LogsView()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.selectedSidebarItem) {
            Section("NekoBox") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            Section("Proxy Groups") {
                ForEach(state.groups) { group in
                    Button {
                        state.selectedGroupID = group.id
                        state.selectedSidebarItem = .proxies
                    } label: {
                        Label(group.name, systemImage: group.isArchived ? "archivebox" : "folder")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NekoBox")
    }
}

private struct WindowToolbar: ToolbarContent {
    @EnvironmentObject private var state: AppState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.startSelectedProfile()
            } label: {
                Label("Connect", systemImage: "power")
            }
            .disabled(state.isRunning)

            Button {
                state.stopCore()
            } label: {
                Label("Disconnect", systemImage: "power.circle")
            }
            .disabled(!state.isRunning)

            Button {
                state.reloadLegacyData()
            } label: {
                Label("Reload Profiles", systemImage: "arrow.clockwise")
            }
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Overview")
                    .font(.largeTitle.weight(.semibold))

                GroupBox("Connection") {
                    LabeledContent("Status") {
                        Label(state.isRunning ? "Connected" : "Disconnected", systemImage: state.isRunning ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(state.isRunning ? .green : .secondary)
                    }
                    LabeledContent("Selected Proxy") {
                        Text(state.selectedProfile?.displayedName ?? "None")
                    }
                    LabeledContent("Core") {
                        Text(state.coreAvailability.description)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Network Mode") {
                    Toggle("System Proxy", isOn: $state.systemProxyEnabled)
                    Toggle("VPN Mode", isOn: $state.vpnEnabled)
                }

                GroupBox("Local Inbound") {
                    LabeledContent("SOCKS / HTTP") {
                        Text("127.0.0.1:2080")
                            .textSelection(.enabled)
                    }
                    Text("Inbound settings will move into the native Settings window with the Core migration.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
        }
        .navigationTitle("Overview")
    }
}

private struct ProxiesView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""

    var body: some View {
        Table(state.profiles(matching: query), selection: $state.selectedProfileID) {
            TableColumn("Name") { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayedName)
                    Text(profile.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Type") { profile in
                Text(profile.type.uppercased())
                    .foregroundStyle(.secondary)
            }
            TableColumn("Latency") { profile in
                Text(profile.latencyDescription)
                    .foregroundStyle(latencyColor(for: profile))
                    .monospacedDigit()
            }
            TableColumn("Traffic") { profile in
                Text(profile.trafficDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .searchable(text: $query, prompt: "Search proxies")
        .navigationTitle(state.selectedGroup?.name ?? "Proxies")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    state.requestProfileEditor()
                } label: {
                    Label("New Proxy", systemImage: "plus")
                }
                Button {
                    state.requestLatencyTest()
                } label: {
                    Label("Test Latency", systemImage: "gauge.with.dots.needle.67percent")
                }
            }
        }
        .overlay {
            if state.profiles(matching: query).isEmpty {
                EmptyStateView(
                    title: "No Proxies",
                    systemImage: "server.rack",
                    message: "Import legacy profiles or create one after the native profile editor is available."
                )
            }
        }
    }

    private func latencyColor(for profile: ProxyProfile) -> Color {
        if profile.latencyMilliseconds < 0 { return .red }
        if profile.latencyMilliseconds == 0 { return .secondary }
        return profile.latencyMilliseconds < 200 ? .green : .orange
    }
}

private struct ConnectionsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Table(state.connections) {
            TableColumn("Inbound") { Text($0.inbound) }
            TableColumn("Destination") { Text($0.destination) }
            TableColumn("Rule") { Text($0.rule) }
            TableColumn("Started") {
                Text($0.createdAt, format: .dateTime.hour().minute().second())
                    .monospacedDigit()
            }
        }
        .navigationTitle("Connections")
        .overlay {
            if state.connections.isEmpty {
                EmptyStateView(
                    title: "No Active Connections",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: "Connection data appears here when the native Core service is connected."
                )
            }
        }
    }
}

private struct LogsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TextEditor(text: Binding(
            get: { state.logLines.joined(separator: "\n") },
            set: { _ in }
        ))
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .navigationTitle("Logs")
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            Form {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .disabled(true)
                Text("Launch at Login moves with the native app lifecycle implementation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                LabeledContent("Legacy profile location") {
                    Text(LegacyRepository.defaultConfigurationDirectory().path)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                Button("Reload Legacy Profiles") {
                    state.reloadLegacyData()
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem { Label("Migration", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 560, height: 300)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }
}
