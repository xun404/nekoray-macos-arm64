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
            Button(L10n.text("common.ok"), role: .cancel) {
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
                            Button(L10n.text("sidebar.renameGroup")) {
                                groupToRename = group
                            }
                            Divider()
                            Button(L10n.text("sidebar.deleteGroup"), role: .destructive) {
                                state.deleteGroup(group)
                            }
                        } else {
                            Text(L10n.text("state.legacyGroupReadOnly"))
                        }
                    }
                }
            } header: {
                HStack {
                    Text(L10n.text("sidebar.proxyGroups"))
                    Spacer()
                    Button {
                        isCreatingGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text("sidebar.newGroupHelp"))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NekoBox")
        .sheet(isPresented: $isCreatingGroup) {
            GroupEditorSheet(title: L10n.text("sidebar.newGroup")) { name in
                state.createGroup(named: name)
            }
        }
        .sheet(item: $groupToRename) { group in
            GroupEditorSheet(title: L10n.text("sidebar.renameGroup"), initialName: group.name) { name in
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
                Label(L10n.text("common.connect"), systemImage: "power")
            }
            .disabled(state.selectedProfile == nil || state.isRunning)
            .help(L10n.text("toolbar.connectHelp"))

            Button {
                state.stopCore()
            } label: {
                Label(L10n.text("common.disconnect"), systemImage: "power.circle")
            }
            .disabled(!state.isRunning)

            Button {
                state.reloadLegacyData()
            } label: {
                Label(L10n.text("common.reload"), systemImage: "arrow.clockwise")
            }
            .help(L10n.text("toolbar.reloadLegacyHelp"))
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
                        Text(L10n.text("sidebar.overview"))
                            .font(.largeTitle.weight(.semibold))
                        Text(L10n.text("overview.subtitle"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        state.selectedSidebarItem = .proxies
                    } label: {
                        Label(L10n.text("overview.manageProxies"), systemImage: "server.rack")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(minimum: 230)), GridItem(.flexible(minimum: 230))],
                    spacing: 16
                ) {
                    StatusCard(
                        title: L10n.text("overview.core"),
                        value: state.coreStatusTitle,
                        detail: state.coreAvailabilityDescription,
                        systemImage: state.isRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle",
                        tint: state.isRunning ? .green : .orange
                    )

                    StatusCard(
                        title: L10n.text("overview.selectedProxy"),
                        value: state.selectedProfile?.displayedName ?? L10n.text("overview.noSelection"),
                        detail: state.selectedProfile?.address ?? L10n.text("overview.selectProxyHint"),
                        systemImage: "server.rack",
                        tint: .blue
                    )

                    StatusCard(
                        title: L10n.text("overview.profiles"),
                        value: "\(state.profiles.count)",
                        detail: L10n.text("overview.nativeProfileCount", String(state.nativeProfileCount)),
                        systemImage: "tray.full",
                        tint: .indigo
                    )

                    StatusCard(
                        title: L10n.text("overview.activity"),
                        value: "\(state.activityLogs.count)",
                        detail: L10n.text("overview.recentEvents"),
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        tint: .teal
                    )
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(L10n.text("overview.quickActions"), systemImage: "bolt.fill")
                                .font(.headline)
                            Spacer()
                            if let selectedProfile = state.selectedProfile {
                                Text(selectedProfile.origin == .native ? L10n.text("overview.nativeProfile") : L10n.text("overview.legacyProfile"))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                state.copySelectedEndpoint()
                            } label: {
                                Label(L10n.text("overview.copyEndpoint"), systemImage: "doc.on.doc")
                            }
                            .disabled(state.selectedProfile == nil)

                            Button {
                                state.requestLatencyTest()
                            } label: {
                                Label(L10n.text("overview.testLatency"), systemImage: "gauge.with.dots.needle.67percent")
                            }
                            .disabled(state.selectedProfile == nil)

                            Button {
                                state.reloadLegacyData()
                            } label: {
                                Label(L10n.text("overview.reloadImports"), systemImage: "arrow.triangle.2.circlepath")
                            }
                        }

                        Divider()

                        LabeledContent(L10n.text("overview.nativeProfileStorage")) {
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
                            Label(L10n.text("overview.networkServices"), systemImage: "network")
                                .font(.headline)
                            Spacer()
                            Text(L10n.text("overview.coreRequired"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }

                        Text(L10n.text("overview.networkServicesDescription"))
                            .foregroundStyle(.secondary)

                        Button(L10n.text("overview.showIntegrationStatus")) {
                            state.showSystemServiceStatus()
                        }
                    }
                    .padding(4)
                }
            }
            .frame(maxWidth: 1_040, alignment: .leading)
            .padding(32)
        }
        .navigationTitle(L10n.text("sidebar.overview"))
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
            TableColumn(L10n.text("table.name")) { profile in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.displayedName)
                        if profile.origin == .native {
                            Text(L10n.text("overview.nativeProfile"))
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
            TableColumn(L10n.text("table.type")) { profile in
                Text(profile.type.uppercased())
                    .foregroundStyle(.secondary)
            }
            TableColumn(L10n.text("table.latency")) { profile in
                Text(profile.latencyDescription)
                    .foregroundStyle(latencyColor(for: profile))
                    .monospacedDigit()
            }
            TableColumn(L10n.text("table.traffic")) { profile in
                Text(profile.trafficDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .searchable(text: $query, prompt: L10n.text("proxies.search"))
        .navigationTitle(state.selectedGroup?.name ?? L10n.text("sidebar.proxies"))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button {
                        draft = state.makeNewProfileDraft()
                        isPresentingEditor = true
                    } label: {
                        Label(L10n.text("proxies.newProxy"), systemImage: "plus")
                    }
                    Button {
                        isPresentingGroupEditor = true
                    } label: {
                        Label(L10n.text("sidebar.newGroup"), systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label(L10n.text("common.add"), systemImage: "plus")
                }

                Button {
                    guard let profile = state.selectedProfile else {
                        state.presentNotice(L10n.text("proxies.selectProxyToEdit"))
                        return
                    }
                    draft = state.makeProfileDraft(for: profile)
                    isPresentingEditor = true
                } label: {
                    Label(
                        state.selectedProfileIsNative ? L10n.text("common.edit") : L10n.text("proxies.makeEditableCopy"),
                        systemImage: state.selectedProfileIsNative ? "pencil" : "doc.on.doc"
                    )
                }
                .disabled(state.selectedProfile == nil)

                Button(role: .destructive) {
                    state.deleteSelectedProfile()
                } label: {
                    Label(L10n.text("common.delete"), systemImage: "trash")
                }
                .disabled(!state.selectedProfileIsNative)

                Button {
                    state.requestLatencyTest()
                } label: {
                    Label(L10n.text("overview.testLatency"), systemImage: "gauge.with.dots.needle.67percent")
                }
                .disabled(state.selectedProfile == nil)
            }
        }
        .overlay {
            if state.profiles(matching: query).isEmpty {
                EmptyStateView(
                    title: query.isEmpty ? L10n.text("proxies.emptyGroup") : L10n.text("proxies.emptySearch"),
                    systemImage: "server.rack",
                    message: query.isEmpty
                        ? L10n.text("proxies.emptyGroupDescription")
                        : L10n.text("proxies.emptySearchDescription")
                )
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            ProxyEditorSheet(draft: draft, groups: state.groups) { savedDraft in
                state.saveProfile(savedDraft)
            }
        }
        .sheet(isPresented: $isPresentingGroupEditor) {
            GroupEditorSheet(title: L10n.text("sidebar.newGroup")) { name in
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
                    Text(draft.id == nil ? L10n.text("editor.newNativeProxy") : L10n.text("editor.editNativeProxy"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.text("editor.storageNotice"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("common.cancel")) {
                    dismiss()
                }
            }

            Form {
                TextField(L10n.text("editor.name"), text: $draft.name)

                Picker(L10n.text("editor.type"), selection: $draft.type) {
                    Text("Shadowsocks").tag("Shadowsocks")
                    Text("VLESS").tag("VLESS")
                    Text("VMess").tag("VMess")
                    Text("Trojan").tag("Trojan")
                    Text("SOCKS").tag("SOCKS")
                    Text("HTTP").tag("HTTP")
                    Text(L10n.text("editor.custom")).tag("Custom")
                }

                Picker(L10n.text("editor.group"), selection: $draft.groupID) {
                    ForEach(groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }

                TextField(L10n.text("editor.server"), text: $draft.host, prompt: Text("example.com"))
                TextField(L10n.text("editor.port"), value: $draft.port, format: .number)

                LabeledContent(L10n.text("editor.endpointPreview")) {
                    Text(draft.endpoint)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                Section(L10n.text("editor.coreSettings")) {
                    if ["vless", "vmess"].contains(draft.type.lowercased()) {
                        TextField(L10n.text("editor.userID"), text: $draft.xraySettings.userID)
                    }

                    if ["trojan", "shadowsocks"].contains(draft.type.lowercased()) {
                        SecureField(L10n.text("editor.password"), text: $draft.xraySettings.password)
                    }

                    if draft.type.caseInsensitiveCompare("Shadowsocks") == .orderedSame {
                        TextField(L10n.text("editor.method"), text: $draft.xraySettings.method)
                    }

                    if draft.type.caseInsensitiveCompare("VLESS") == .orderedSame {
                        TextField(L10n.text("editor.flow"), text: $draft.xraySettings.flow)
                    }

                    Picker(L10n.text("editor.transport"), selection: $draft.xraySettings.stream.network) {
                        Text("TCP").tag("tcp")
                        Text("WebSocket").tag("ws")
                        Text("gRPC").tag("grpc")
                        Text("XHTTP").tag("xhttp")
                        Text("HTTPUpgrade").tag("httpupgrade")
                    }

                    Picker(L10n.text("editor.transportSecurity"), selection: $draft.xraySettings.stream.security) {
                        Text(L10n.text("editor.securityNone")).tag("none")
                        Text("TLS").tag("tls")
                        Text("REALITY").tag("reality")
                    }

                    TextField(L10n.text("editor.path"), text: $draft.xraySettings.stream.path)
                    TextField(L10n.text("editor.host"), text: $draft.xraySettings.stream.host)
                    TextField(L10n.text("editor.serverName"), text: $draft.xraySettings.stream.serverName)
                    Toggle(L10n.text("editor.allowInsecure"), isOn: $draft.xraySettings.stream.allowInsecure)
                    TextField(L10n.text("editor.fingerprint"), text: $draft.xraySettings.stream.fingerprint)

                    if draft.xraySettings.stream.security.caseInsensitiveCompare("reality") == .orderedSame {
                        TextField(L10n.text("editor.realityPublicKey"), text: $draft.xraySettings.stream.realityPublicKey)
                        TextField(L10n.text("editor.realityShortID"), text: $draft.xraySettings.stream.realityShortID)
                        TextField(L10n.text("editor.realitySpiderX"), text: $draft.xraySettings.stream.realitySpiderX)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !draft.isValid {
                    Label(L10n.text("editor.validFieldsRequired"), systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("common.save")) {
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
            TextField(L10n.text("groupEditor.groupName"), text: $name)
            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) {
                    dismiss()
                }
                Button(L10n.text("common.save")) {
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
                    title: L10n.text("connections.noActive"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: L10n.text("connections.emptyDescription")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(state.connections) {
                    TableColumn(L10n.text("connections.inbound")) { Text($0.inbound) }
                    TableColumn(L10n.text("connections.destination")) { Text($0.destination) }
                    TableColumn(L10n.text("connections.rule")) { Text($0.rule) }
                    TableColumn(L10n.text("connections.started")) {
                        Text($0.createdAt, format: .dateTime.hour().minute().second())
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(L10n.text("sidebar.connections"))
    }
}

private struct LogsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            if state.activityLogs.isEmpty {
                EmptyStateView(
                    title: L10n.text("logs.noActivity"),
                    systemImage: "text.alignleft",
                    message: L10n.text("logs.emptyDescription")
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
        .navigationTitle(L10n.text("sidebar.logs"))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    state.copyLogs()
                } label: {
                    Label(L10n.text("common.copy"), systemImage: "doc.on.doc")
                }
                .disabled(state.activityLogs.isEmpty)

                Button(role: .destructive) {
                    state.clearLogs()
                } label: {
                    Label(L10n.text("common.clear"), systemImage: "trash")
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
    @AppStorage("language") private var languageID = AppLanguage.english.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            generalSettings
            .tabItem {
                Label(L10n.text("settings.general"), systemImage: "gearshape")
            }

            CoreManagementSettings()
            .tabItem {
                Label(L10n.text("settings.core"), systemImage: "bolt.horizontal.circle")
            }

            storageSettings
            .tabItem {
                Label(L10n.text("sidebar.proxies"), systemImage: "tray.full")
            }
        }
        .frame(width: 720, height: 560)
    }

    private var generalSettings: some View {
        Form {
            Section(L10n.text("settings.languageAndAppearance")) {
                Picker(L10n.text("language"), selection: $languageID) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                Picker(L10n.text("appearance"), selection: $appearance) {
                    Text(L10n.text("appearance.system")).tag("system")
                    Text(L10n.text("appearance.light")).tag("light")
                    Text(L10n.text("appearance.dark")).tag("dark")
                }
            }
            Section(L10n.text("settings.application")) {
                Toggle(L10n.text("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .disabled(true)
                Text(L10n.text("settings.launchAtLoginDescription"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var storageSettings: some View {
        Form {
            Section(L10n.text("settings.dataLocations")) {
                LabeledContent(L10n.text("settings.legacyProfileLocation")) {
                    Text(LegacyRepository.defaultConfigurationDirectory().path)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(L10n.text("overview.nativeProfileStorage")) {
                    Text(state.nativeStorageLocation)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section {
                Button(L10n.text("settings.reloadLegacyProfiles")) {
                    state.reloadLegacyData()
                }
            } footer: {
                Text(L10n.text("settings.legacyDataDescription"))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct CoreManagementSettings: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("settings.coreManagement"))
                        .font(.title2.weight(.semibold))
                    Text(L10n.text("settings.coreManagementDescription"))
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(L10n.text("settings.activeCore"), selection: Binding(
                            get: { state.selectedCore },
                            set: { state.selectCore($0) }
                        )) {
                            ForEach(CoreKind.allCases) { core in
                                Text(core.displayName).tag(core)
                            }
                        }
                        .disabled(state.isRunning || state.hasActiveCoreDownload)

                        Text(L10n.text("settings.activeCoreDescription"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(4)
                } label: {
                    Label(L10n.text("settings.activeCore"), systemImage: "bolt.horizontal.circle.fill")
                }

                ForEach(CoreKind.allCases) { core in
                    CoreInstallationCard(core: core)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SOCKS5 127.0.0.1:\(SingBoxConfigurationGenerator.socksPort)")
                        Text("HTTP 127.0.0.1:\(SingBoxConfigurationGenerator.httpPort)")
                    }
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding(4)
                } label: {
                    Label(L10n.text("settings.localEndpoints"), systemImage: "point.3.connected.trianglepath.dotted")
                }

                Text(L10n.text("settings.localEndpointsDescription"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private struct CoreInstallationCard: View {
    let core: CoreKind
    @EnvironmentObject private var state: AppState

    private var record: CoreInstallationRecord? {
        state.installationRecord(for: core)
    }

    private var canModifyInstallation: Bool {
        !state.isRunning && !state.hasActiveCoreDownload
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(core.displayName)
                            .font(.headline)
                        Text(core.isAvailable ? L10n.text("settings.coreReady") : L10n.text("settings.coreNotInstalled"))
                            .font(.callout)
                            .foregroundStyle(core.isAvailable ? .green : .secondary)
                    }
                    Spacer()
                    if state.selectedCore == core {
                        Text(L10n.text("settings.active"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }

                LabeledContent(L10n.text("settings.coreExecutable", core.displayName)) {
                    Text(core.selectedOrDetectedPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }

                if let record {
                    LabeledContent(L10n.text("settings.installedVersion")) {
                        Text(record.version)
                            .textSelection(.enabled)
                    }
                }

                HStack(spacing: 10) {
                    if state.isDownloadingCore(core) {
                        ProgressView(L10n.text("settings.downloadingCore", core.displayName))
                            .controlSize(.small)
                    } else {
                        Button(core.isAvailable ? L10n.text("settings.updateCore", core.displayName) : L10n.text("settings.downloadCore", core.displayName)) {
                            state.downloadOfficialCore(core)
                        }
                        .disabled(!canModifyInstallation)
                    }

                    Button(L10n.text("settings.chooseCoreExecutable", core.displayName)) {
                        chooseExecutable()
                    }
                    .disabled(!canModifyInstallation)

                    if core.hasCustomExecutable {
                        Button(L10n.text("settings.useDetectedCore", core.displayName)) {
                            core.clearCustomExecutable()
                            state.refreshCoreAvailability()
                        }
                        .disabled(!canModifyInstallation)
                    }

                    Spacer()

                    Link(L10n.text("settings.officialRelease"), destination: CoreDownloader.officialReleaseURL(for: core))
                }
            }
            .padding(4)
        } label: {
            Label(core.displayName, systemImage: core == .xray ? "bolt.horizontal.circle" : "shippingbox")
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("settings.chooseCoreExecutable", core.displayName)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            state.presentNotice(L10n.text("core.notExecutable"))
            return
        }
        core.setExecutable(url)
        state.refreshCoreAvailability()
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
