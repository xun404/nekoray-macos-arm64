import AppKit
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
        .alert(
            "NekoBox",
            isPresented: Binding(
                get: { state.notice != nil },
                set: { isPresented in
                    if !isPresented {
                        state.clearNotice()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                state.clearNotice()
            }
        } message: {
            Text(state.notice ?? "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedSidebarItem {
        case .overview:
            OverviewView()
        case .proxies:
            ProxiesView()
        case .connections:
            ConnectionsView()
        case .logs:
            LogsView()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light":
            .light
        case "dark":
            .dark
        default:
            nil
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @State private var isCreatingGroup = false
    @State private var groupToRename: ProxyGroup?

    var body: some View {
        List(selection: $state.selectedSidebarItem) {
            Section("NekoBox") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            Section {
                ForEach(state.groups) { group in
                    Button {
                        state.selectGroup(group.id)
                        state.selectedSidebarItem = .proxies
                    } label: {
                        HStack(spacing: 8) {
                            Label(group.name, systemImage: group.isArchived ? "archivebox" : "folder")
                            Spacer()
                            Text(state.profileCount(in: group), format: .number)
                                .foregroundStyle(.secondary)
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if group.origin == .native {
                            Button("Rename Group") {
                                groupToRename = group
                            }
                            Divider()
                            Button("Delete Group", role: .destructive) {
                                state.deleteGroup(group)
                            }
                        } else {
                            Text("Legacy groups are read-only.")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Proxy Groups")
                    Spacer()
                    Button {
                        isCreatingGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Group")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NekoBox")
        .sheet(isPresented: $isCreatingGroup) {
            GroupEditorSheet(title: "New Group") { name in
                state.createGroup(named: name)
            }
        }
        .sheet(item: $groupToRename) { group in
            GroupEditorSheet(title: "Rename Group", initialName: group.name) { name in
                state.renameGroup(group, to: name)
            }
        }
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
            .disabled(state.selectedProfile == nil || state.isRunning)
            .help("Connect the selected proxy when the native Core is available.")

            Button {
                state.stopCore()
            } label: {
                Label("Disconnect", systemImage: "power.circle")
            }
            .disabled(!state.isRunning)

            Button {
                state.reloadLegacyData()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload read-only legacy profiles.")
        }
    }
}

private struct OverviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Overview")
                            .font(.largeTitle.weight(.semibold))
                        Text("Native profile management for macOS")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.selectedSidebarItem = .proxies
                    } label: {
                        Label("Manage Proxies", systemImage: "server.rack")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(minimum: 230)), GridItem(.flexible(minimum: 230))],
                    spacing: 16
                ) {
                    StatusCard(
                        title: "Core",
                        value: state.coreStatusTitle,
                        detail: state.coreAvailability.description,
                        systemImage: state.isRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle",
                        tint: state.isRunning ? .green : .orange
                    )

                    StatusCard(
                        title: "Selected Proxy",
                        value: state.selectedProfile?.displayedName ?? "No selection",
                        detail: state.selectedProfile?.address ?? "Choose a proxy to connect or copy its endpoint.",
                        systemImage: "server.rack",
                        tint: .blue
                    )

                    StatusCard(
                        title: "Profiles",
                        value: "\(state.profiles.count)",
                        detail: "\(state.nativeProfileCount) stored in native profile storage",
                        systemImage: "tray.full",
                        tint: .indigo
                    )

                    StatusCard(
                        title: "Activity",
                        value: "\(state.activityLogs.count)",
                        detail: "Recent local events are available in Logs.",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        tint: .teal
                    )
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Quick Actions", systemImage: "bolt.fill")
                                .font(.headline)
                            Spacer()
                            if let selectedProfile = state.selectedProfile {
                                Text(selectedProfile.origin == .native ? "Native profile" : "Legacy profile")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                state.copySelectedEndpoint()
                            } label: {
                                Label("Copy Endpoint", systemImage: "doc.on.doc")
                            }
                            .disabled(state.selectedProfile == nil)

                            Button {
                                state.requestLatencyTest()
                            } label: {
                                Label("Test Latency", systemImage: "gauge.with.dots.needle.67percent")
                            }
                            .disabled(state.selectedProfile == nil)

                            Button {
                                state.reloadLegacyData()
                            } label: {
                                Label("Reload Imports", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        Divider()

                        LabeledContent("Native profile storage") {
                            Text(state.nativeStorageLocation)
                                .textSelection(.enabled)
                                .font(.caption.monospaced())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Network Services", systemImage: "network")
                                .font(.headline)
                            Spacer()
                            Text("Core required")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }

                        Text("System Proxy, VPN Mode, inbound listeners, and connection inspection will become available after native Core integration.")
                            .foregroundStyle(.secondary)

                        Button("Show Integration Status") {
                            state.showSystemServiceStatus()
                        }
                    }
                    .padding(4)
                }
            }
            .frame(maxWidth: 1_040, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Overview")
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary)
        }
    }
}

private struct ProxiesView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var isPresentingEditor = false
    @State private var isPresentingGroupEditor = false
    @State private var draft = ProxyDraft(groupID: 0)

    var body: some View {
        Table(state.profiles(matching: query), selection: profileSelection) {
            TableColumn("Name") { profile in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.displayedName)
                        if profile.origin == .native {
                            Text("Native")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
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
        .searchable(text: $query, prompt: "Search name, address, or type")
        .navigationTitle(state.selectedGroup?.name ?? "Proxies")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button {
                        draft = state.makeNewProfileDraft()
                        isPresentingEditor = true
                    } label: {
                        Label("New Proxy", systemImage: "plus")
                    }
                    Button {
                        isPresentingGroupEditor = true
                    } label: {
                        Label("New Group", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Button {
                    guard let profile = state.selectedProfile else {
                        state.presentNotice("Select a proxy to edit.")
                        return
                    }
                    draft = state.makeProfileDraft(for: profile)
                    isPresentingEditor = true
                } label: {
                    Label(
                        state.selectedProfileIsNative ? "Edit" : "Make Editable Copy",
                        systemImage: state.selectedProfileIsNative ? "pencil" : "doc.on.doc"
                    )
                }
                .disabled(state.selectedProfile == nil)

                Button(role: .destructive) {
                    state.deleteSelectedProfile()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!state.selectedProfileIsNative)

                Button {
                    state.requestLatencyTest()
                } label: {
                    Label("Test Latency", systemImage: "gauge.with.dots.needle.67percent")
                }
                .disabled(state.selectedProfile == nil)
            }
        }
        .overlay {
            if state.profiles(matching: query).isEmpty {
                EmptyStateView(
                    title: query.isEmpty ? "No Proxies in This Group" : "No Matching Proxies",
                    systemImage: "server.rack",
                    message: query.isEmpty
                        ? "Add a native proxy or reload the read-only legacy import."
                        : "Try a different name, address, or proxy type."
                )
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            ProxyEditorSheet(draft: draft, groups: state.groups) { savedDraft in
                state.saveProfile(savedDraft)
            }
        }
        .sheet(isPresented: $isPresentingGroupEditor) {
            GroupEditorSheet(title: "New Group") { name in
                state.createGroup(named: name)
            }
        }
    }

    private var profileSelection: Binding<Int?> {
        Binding(
            get: { state.selectedProfileID },
            set: { state.selectProfile($0) }
        )
    }

    private func latencyColor(for profile: ProxyProfile) -> Color {
        if profile.latencyMilliseconds < 0 {
            return .red
        }
        if profile.latencyMilliseconds == 0 {
            return .secondary
        }
        return profile.latencyMilliseconds < 200 ? .green : .orange
    }
}

private struct ProxyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProxyDraft
    let groups: [ProxyGroup]
    let onSave: (ProxyDraft) -> Void

    init(draft: ProxyDraft, groups: [ProxyGroup], onSave: @escaping (ProxyDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.groups = groups
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.id == nil ? "New Native Proxy" : "Edit Native Proxy")
                        .font(.title2.weight(.semibold))
                    Text("Saved only in NekoBox Application Support storage.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }

            Form {
                TextField("Name", text: $draft.name)

                Picker("Type", selection: $draft.type) {
                    Text("Shadowsocks").tag("Shadowsocks")
                    Text("VLESS").tag("VLESS")
                    Text("VMess").tag("VMess")
                    Text("Trojan").tag("Trojan")
                    Text("SOCKS").tag("SOCKS")
                    Text("HTTP").tag("HTTP")
                    Text("Custom").tag("Custom")
                }

                Picker("Group", selection: $draft.groupID) {
                    ForEach(groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }

                TextField("Server", text: $draft.host, prompt: Text("example.com"))
                TextField("Port", value: $draft.port, format: .number)

                LabeledContent("Endpoint preview") {
                    Text(draft.endpoint)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                if !draft.isValid {
                    Label("A name, server, and valid port are required.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct GroupEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (String) -> Void
    @State private var name: String

    init(title: String, initialName: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
            TextField("Group name", text: $name)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct ConnectionsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.connections.isEmpty {
                EmptyStateView(
                    title: "No Active Connections",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: "Connection inspection will populate here when the native Core service is connected."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(state.connections) {
                    TableColumn("Inbound") { Text($0.inbound) }
                    TableColumn("Destination") { Text($0.destination) }
                    TableColumn("Rule") { Text($0.rule) }
                    TableColumn("Started") {
                        Text($0.createdAt, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Connections")
    }
}

private struct LogsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            if state.activityLogs.isEmpty {
                EmptyStateView(
                    title: "No Activity Yet",
                    systemImage: "text.alignleft",
                    message: "Profile changes and Core actions will appear here."
                )
                .frame(maxWidth: .infinity, minHeight: 260)
                .listRowSeparator(.hidden)
            } else {
                ForEach(state.activityLogs.reversed()) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.level.systemImage)
                            .foregroundStyle(logColor(for: entry.level))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.message)
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    state.copyLogs()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(state.activityLogs.isEmpty)

                Button(role: .destructive) {
                    state.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(state.activityLogs.isEmpty)
            }
        }
    }

    private func logColor(for level: ActivityLog.Level) -> Color {
        switch level {
        case .info:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
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
                Text("Launch at Login becomes available with the native app lifecycle integration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                LabeledContent("Legacy profile location") {
                    Text(LegacyRepository.defaultConfigurationDirectory().path)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Native profile storage") {
                    Text(state.nativeStorageLocation)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                Button("Reload Legacy Profiles") {
                    state.reloadLegacyData()
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("Profiles", systemImage: "tray.full")
            }
        }
        .frame(width: 600, height: 340)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(24)
    }
}
