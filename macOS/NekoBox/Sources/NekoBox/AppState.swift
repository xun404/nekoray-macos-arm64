import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSidebarItem: SidebarItem = .overview
    @Published var selectedGroupID: Int?
    @Published var selectedProfileID: Int?
    @Published private(set) var groups: [ProxyGroup] = []
    @Published private(set) var profiles: [ProxyProfile] = []
    @Published private(set) var connections: [Connection] = []
    @Published private(set) var logLines: [String] = []
    @Published private(set) var notice: String?
    @Published private(set) var coreAvailability: CoreAvailability
    @Published private(set) var isRunning = false
    @Published var systemProxyEnabled = false
    @Published var vpnEnabled = false

    private let repository: LegacyRepository
    private let coreService: any CoreService

    init(
        repository: LegacyRepository = LegacyRepository(),
        coreService: any CoreService = DeferredCoreService()
    ) {
        self.repository = repository
        self.coreService = coreService
        coreAvailability = coreService.availability
        reloadLegacyData()
    }

    var selectedGroup: ProxyGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var selectedProfile: ProxyProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    func profiles(matching query: String = "") -> [ProxyProfile] {
        let selected = profiles.filter { selectedGroupID == nil || $0.groupID == selectedGroupID }
        guard !query.isEmpty else { return selected }
        return selected.filter {
            $0.displayedName.localizedCaseInsensitiveContains(query) ||
            $0.address.localizedCaseInsensitiveContains(query) ||
            $0.type.localizedCaseInsensitiveContains(query)
        }
    }

    func reloadLegacyData() {
        let snapshot = repository.load()
        groups = snapshot.groups
        profiles = snapshot.profiles
        selectedGroupID = selectedGroupID.flatMap { id in groups.contains(where: { $0.id == id }) ? id : nil } ?? groups.first?.id
        selectedProfileID = selectedProfileID.flatMap { id in profiles.contains(where: { $0.id == id }) ? id : nil }
        appendLog(snapshot.sourceDescription)
    }

    func startSelectedProfile() {
        guard let profile = selectedProfile else {
            notice = "Select a proxy before connecting."
            return
        }
        Task {
            do {
                try await coreService.start(profile: profile)
                isRunning = true
                appendLog("Started \(profile.displayedName).")
            } catch {
                notice = error.localizedDescription
                appendLog("Start failed: \(error.localizedDescription)")
            }
        }
    }

    func stopCore() {
        Task {
            do {
                try await coreService.stop()
                isRunning = false
                appendLog("Stopped core service.")
            } catch {
                notice = error.localizedDescription
                appendLog("Stop failed: \(error.localizedDescription)")
            }
        }
    }

    func requestProfileEditor() {
        notice = "Profile editing is scheduled after the Swift config builder lands. Existing profiles are available read-only during migration."
    }

    func requestLatencyTest() {
        notice = "Latency testing will use the native gRPC client once the Swift Core service is connected."
    }

    func clearNotice() {
        notice = nil
    }

    private func appendLog(_ line: String) {
        let timestamp = DateFormatter.localizedString(from: .now, dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(timestamp)] \(line)")
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
    }
}
