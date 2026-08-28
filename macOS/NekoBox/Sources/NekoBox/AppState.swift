import AppKit
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
    @Published private(set) var activityLogs: [ActivityLog] = []
    @Published private(set) var notice: String?
    @Published private(set) var coreAvailability: CoreAvailability
    @Published private(set) var isRunning = false

    private let legacyRepository: LegacyRepository
    private let nativeRepository: NativeRepository
    private let coreService: any CoreService
    private var nativeSnapshot: NativeSnapshot
    private var legacySnapshot: LegacySnapshot?

    init(
        legacyRepository: LegacyRepository = LegacyRepository(),
        nativeRepository: NativeRepository = NativeRepository(),
        coreService: any CoreService = DeferredCoreService()
    ) {
        self.legacyRepository = legacyRepository
        self.nativeRepository = nativeRepository
        self.coreService = coreService
        nativeSnapshot = nativeRepository.load()
        coreAvailability = coreService.availability
        reloadLegacyData()
        appendActivity(
            "Native profile storage is ready at \(nativeRepository.stateURL.path).",
            level: .info
        )
    }

    var selectedGroup: ProxyGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    var selectedProfile: ProxyProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var selectedProfileIsNative: Bool {
        selectedProfile?.origin == .native
    }

    var nativeProfileCount: Int {
        nativeSnapshot.profiles.count
    }

    var nativeStorageLocation: String {
        nativeRepository.stateURL.path
    }

    var coreStatusTitle: String {
        isRunning ? "Connected" : "Core unavailable"
    }

    func profiles(matching query: String = "") -> [ProxyProfile] {
        let groupProfiles = profiles.filter { selectedGroupID == nil || $0.groupID == selectedGroupID }
        guard !query.isEmpty else { return groupProfiles }

        return groupProfiles.filter {
            $0.displayedName.localizedCaseInsensitiveContains(query) ||
            $0.address.localizedCaseInsensitiveContains(query) ||
            $0.type.localizedCaseInsensitiveContains(query)
        }
    }

    func profileCount(in group: ProxyGroup) -> Int {
        profiles.filter { $0.groupID == group.id }.count
    }

    func selectGroup(_ groupID: Int?) {
        selectedGroupID = groupID
        if let groupID, !profiles.contains(where: { $0.id == selectedProfileID && $0.groupID == groupID }) {
            selectedProfileID = profiles.first(where: { $0.groupID == groupID })?.id
        }
        persistSelection()
    }

    func selectProfile(_ profileID: Int?) {
        selectedProfileID = profileID
        if let profileID, let profile = profiles.first(where: { $0.id == profileID }) {
            selectedGroupID = profile.groupID
        }
        persistSelection()
    }

    func reloadLegacyData() {
        legacySnapshot = legacyRepository.load()
        rebuildVisibleData()
        appendActivity(legacySnapshot?.sourceDescription ?? "Legacy profiles were reloaded.", level: .info)
    }

    func makeNewProfileDraft() -> ProxyDraft {
        ProxyDraft(groupID: selectedGroupID ?? groups.first?.id ?? 0)
    }

    func makeProfileDraft(for profile: ProxyProfile) -> ProxyDraft {
        ProxyDraft(profile: profile)
    }

    func saveProfile(_ draft: ProxyDraft) {
        guard draft.isValid else {
            notice = "Enter a name, a server address, and a port from 1 to 65535."
            return
        }

        if let id = draft.id,
           let index = nativeSnapshot.profiles.firstIndex(where: { $0.id == id }) {
            nativeSnapshot.profiles[index].name = draft.trimmedName
            nativeSnapshot.profiles[index].type = draft.type
            nativeSnapshot.profiles[index].address = draft.endpoint
            nativeSnapshot.profiles[index].groupID = draft.groupID
            nativeSnapshot.profiles[index].origin = .native
            selectedProfileID = id
            appendActivity("Updated \(draft.trimmedName).", level: .success)
        } else {
            let profile = ProxyProfile(
                id: nextNativeProfileID(),
                groupID: draft.groupID,
                type: draft.type,
                name: draft.trimmedName,
                address: draft.endpoint,
                latencyMilliseconds: 0,
                uploadedBytes: 0,
                downloadedBytes: 0,
                testReport: "",
                origin: .native
            )
            nativeSnapshot.profiles.append(profile)
            selectedGroupID = profile.groupID
            selectedProfileID = profile.id
            appendActivity("Added \(profile.displayedName).", level: .success)
        }

        rebuildVisibleData()
        persistNativeData()
    }

    func deleteSelectedProfile() {
        guard let profile = selectedProfile else {
            notice = "Select a proxy to remove."
            return
        }

        guard profile.origin == .native else {
            notice = "Legacy profiles are read-only. Use Edit to create an editable native copy."
            return
        }

        nativeSnapshot.profiles.removeAll { $0.id == profile.id }
        selectedProfileID = profiles.first(where: { $0.groupID == selectedGroupID && $0.id != profile.id })?.id
        rebuildVisibleData()
        persistNativeData()
        appendActivity("Removed \(profile.displayedName).", level: .warning)
    }

    func createGroup(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            notice = "Enter a name for the group."
            return
        }

        let group = ProxyGroup(
            id: nextNativeGroupID(),
            name: trimmedName,
            isArchived: false,
            subscriptionURL: nil,
            profileOrder: [],
            origin: .native
        )
        nativeSnapshot.groups.append(group)
        selectedGroupID = group.id
        selectedProfileID = nil
        rebuildVisibleData()
        persistNativeData()
        appendActivity("Created the \(group.name) group.", level: .success)
    }

    func renameGroup(_ group: ProxyGroup, to name: String) {
        guard group.origin == .native else {
            notice = "Legacy groups are read-only."
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            notice = "Enter a name for the group."
            return
        }

        guard let index = nativeSnapshot.groups.firstIndex(where: { $0.id == group.id }) else { return }
        nativeSnapshot.groups[index].name = trimmedName
        rebuildVisibleData()
        persistNativeData()
        appendActivity("Renamed the group to \(trimmedName).", level: .success)
    }

    func deleteGroup(_ group: ProxyGroup) {
        guard group.origin == .native else {
            notice = "Legacy groups are read-only."
            return
        }

        let fallbackGroupID = groups.first(where: { $0.id != group.id })?.id ?? 0
        nativeSnapshot.groups.removeAll { $0.id == group.id }
        nativeSnapshot.profiles = nativeSnapshot.profiles.map { profile in
            var profile = profile
            if profile.groupID == group.id {
                profile.groupID = fallbackGroupID
            }
            return profile
        }
        selectedGroupID = fallbackGroupID
        selectedProfileID = nil
        rebuildVisibleData()
        persistNativeData()
        appendActivity("Removed the \(group.name) group.", level: .warning)
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
                appendActivity("Started \(profile.displayedName).", level: .success)
            } catch {
                notice = error.localizedDescription
                appendActivity("Connection was not started: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    func stopCore() {
        Task {
            do {
                try await coreService.stop()
                isRunning = false
                appendActivity("Stopped the local Core service.", level: .info)
            } catch {
                notice = error.localizedDescription
                appendActivity("Core stop failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func requestLatencyTest() {
        guard selectedProfile != nil else {
            notice = "Select a proxy before running a latency test."
            return
        }
        notice = "Latency testing becomes available when the native Core service is connected."
        appendActivity("Latency test requested before Core integration.", level: .info)
    }

    func showSystemServiceStatus() {
        notice = "System Proxy and VPN controls remain unavailable until the native Core and network-extension integrations are complete."
    }

    func copySelectedEndpoint() {
        guard let profile = selectedProfile else {
            notice = "Select a proxy to copy its endpoint."
            return
        }
        copyToPasteboard(profile.address)
        notice = "Copied \(profile.address)."
        appendActivity("Copied the endpoint for \(profile.displayedName).", level: .info)
    }

    func copyLogs() {
        let text = activityLogs.map { entry in
            let timestamp = entry.date.formatted(date: .omitted, time: .standard)
            return "[\(timestamp)] \(entry.level.rawValue.uppercased()): \(entry.message)"
        }
        .joined(separator: "\n")
        copyToPasteboard(text)
        notice = "Copied \(activityLogs.count) log entries."
    }

    func clearLogs() {
        activityLogs.removeAll()
        appendActivity("Cleared the activity log.", level: .info)
    }

    func clearNotice() {
        notice = nil
    }

    func presentNotice(_ message: String) {
        notice = message
    }

    private func rebuildVisibleData() {
        let legacyGroups = legacySnapshot?.groups ?? []
        let legacyProfiles = legacySnapshot?.profiles ?? []
        let nativeGroups = nativeSnapshot.groups.map { group -> ProxyGroup in
            var group = group
            group.origin = .native
            return group
        }
        let nativeProfiles = nativeSnapshot.profiles.map { profile -> ProxyProfile in
            var profile = profile
            profile.origin = .native
            return profile
        }

        groups = merge(legacyGroups, with: nativeGroups)
        profiles = legacyProfiles + nativeProfiles

        let requestedGroupID = selectedGroupID ?? nativeSnapshot.selectedGroupID
        selectedGroupID = groups.contains(where: { $0.id == requestedGroupID })
            ? requestedGroupID
            : groups.first?.id

        let requestedProfileID = selectedProfileID ?? nativeSnapshot.selectedProfileID
        selectedProfileID = profiles.contains(where: { $0.id == requestedProfileID })
            ? requestedProfileID
            : profiles.first(where: { $0.groupID == selectedGroupID })?.id
    }

    private func merge(_ legacyGroups: [ProxyGroup], with nativeGroups: [ProxyGroup]) -> [ProxyGroup] {
        var result = legacyGroups
        for group in nativeGroups where !result.contains(where: { $0.id == group.id }) {
            result.append(group)
        }
        return result.sorted {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func persistSelection() {
        nativeSnapshot.selectedGroupID = selectedGroupID
        nativeSnapshot.selectedProfileID = selectedProfileID
        persistNativeData()
    }

    private func persistNativeData() {
        nativeSnapshot.selectedGroupID = selectedGroupID
        nativeSnapshot.selectedProfileID = selectedProfileID
        do {
            try nativeRepository.save(nativeSnapshot)
        } catch {
            notice = "Could not save native profiles: \(error.localizedDescription)"
            appendActivity("Native profile storage failed: \(error.localizedDescription)", level: .error)
        }
    }

    private func nextNativeGroupID() -> Int {
        (nativeSnapshot.groups.map(\.id).min() ?? 0) - 1
    }

    private func nextNativeProfileID() -> Int {
        (nativeSnapshot.profiles.map(\.id).min() ?? 0) - 1
    }

    private func appendActivity(_ message: String, level: ActivityLog.Level) {
        activityLogs.append(ActivityLog(id: UUID(), date: .now, level: level, message: message))
        if activityLogs.count > 250 {
            activityLogs.removeFirst(activityLogs.count - 250)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
