import Foundation

/// Reads the existing Qt application's JSON files without mutating them.
///
/// NekoBox's legacy profile format is intentionally decoded only to the level
/// needed for navigation and list presentation. Editing or generating an
/// outbound is deferred until the C++ config builder has a Swift replacement.
struct LegacyRepository {
    private let fileManager: FileManager
    let configurationDirectory: URL

    init(
        configurationDirectory: URL = LegacyRepository.defaultConfigurationDirectory(),
        fileManager: FileManager = .default
    ) {
        self.configurationDirectory = configurationDirectory
        self.fileManager = fileManager
    }

    func load() -> LegacySnapshot {
        let groupsDirectory = configurationDirectory.appending(path: "groups", directoryHint: .isDirectory)
        let profilesDirectory = configurationDirectory.appending(path: "profiles", directoryHint: .isDirectory)

        guard fileManager.fileExists(atPath: configurationDirectory.path) else {
            return LegacySnapshot(
                groups: [ProxyGroup(id: 0, name: "Default", isArchived: false, subscriptionURL: nil, profileOrder: [])],
                profiles: [],
                sourceDescription: "No legacy configuration was found at \(configurationDirectory.path)."
            )
        }

        let groupOrder = loadGroupOrder(from: groupsDirectory)
        var groups = loadGroups(from: groupsDirectory)
        if groups.isEmpty {
            groups = [ProxyGroup(id: 0, name: "Default", isArchived: false, subscriptionURL: nil, profileOrder: [])]
        }
        groups.sort { lhs, rhs in
            let lhsIndex = groupOrder.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = groupOrder.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex == rhsIndex ? lhs.id < rhs.id : lhsIndex < rhsIndex
        }

        let profiles = loadProfiles(from: profilesDirectory, groups: groups)
        return LegacySnapshot(
            groups: groups,
            profiles: profiles,
            sourceDescription: "Loaded \(profiles.count) profiles from \(configurationDirectory.path)."
        )
    }

    static func defaultConfigurationDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["NEKOBOX_LEGACY_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Preferences", directoryHint: .isDirectory)
            .appending(path: "nekoray", directoryHint: .isDirectory)
            .appending(path: "config", directoryHint: .isDirectory)
    }

    private func loadGroupOrder(from directory: URL) -> [Int] {
        guard let data = try? Data(contentsOf: directory.appending(path: "pm.json")),
              let metadata = try? JSONDecoder().decode(LegacyGroupIndex.self, from: data)
        else { return [] }
        return metadata.groups
    }

    private func loadGroups(from directory: URL) -> [ProxyGroup] {
        jsonFiles(in: directory).compactMap { file in
            guard file.lastPathComponent != "pm.json",
                  let data = try? Data(contentsOf: file),
                  let group = try? JSONDecoder().decode(LegacyGroup.self, from: data)
            else { return nil }

            return ProxyGroup(
                id: group.id,
                name: group.name.isEmpty ? "Untitled Group" : group.name,
                isArchived: group.archive,
                subscriptionURL: URL(string: group.url),
                profileOrder: group.order
            )
        }
    }

    private func loadProfiles(from directory: URL, groups: [ProxyGroup]) -> [ProxyProfile] {
        let profiles = jsonFiles(in: directory).compactMap { file -> ProxyProfile? in
            guard let data = try? Data(contentsOf: file),
                  let profile = try? JSONDecoder().decode(LegacyProfile.self, from: data)
            else { return nil }

            let address = profile.bean.address.isEmpty ? "Not configured" : profile.bean.address
            let endpoint = profile.bean.port > 0 ? "\(address):\(profile.bean.port)" : address
            return ProxyProfile(
                id: profile.id,
                groupID: profile.groupID,
                type: profile.type,
                name: profile.bean.name,
                address: endpoint,
                latencyMilliseconds: profile.latency,
                uploadedBytes: profile.traffic.uploaded,
                downloadedBytes: profile.traffic.downloaded,
                testReport: profile.report
            )
        }

        let orderByGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.profileOrder) })
        return profiles.sorted { lhs, rhs in
            guard lhs.groupID == rhs.groupID else { return lhs.groupID < rhs.groupID }
            let order = orderByGroup[lhs.groupID] ?? []
            let lhsIndex = order.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = order.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex == rhsIndex ? lhs.id < rhs.id : lhsIndex < rhsIndex
        }
    }

    private func jsonFiles(in directory: URL) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "json" }
    }
}

private struct LegacyGroupIndex: Decodable {
    let groups: [Int]
}

private struct LegacyGroup: Decodable {
    let id: Int
    let archive: Bool
    let name: String
    let url: String
    let order: [Int]

    private enum CodingKeys: String, CodingKey {
        case id, archive, name, url, order
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        archive = try values.decodeIfPresent(Bool.self, forKey: .archive) ?? false
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        order = try values.decodeIfPresent([Int].self, forKey: .order) ?? []
    }
}

private struct LegacyProfile: Decodable {
    let type: String
    let id: Int
    let groupID: Int
    let latency: Int
    let report: String
    let bean: LegacyBean
    let traffic: LegacyTraffic

    private enum CodingKeys: String, CodingKey {
        case type, id, gid, yc, report, bean, traffic
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "custom"
        id = try values.decode(Int.self, forKey: .id)
        groupID = try values.decodeIfPresent(Int.self, forKey: .gid) ?? 0
        latency = try values.decodeIfPresent(Int.self, forKey: .yc) ?? 0
        report = try values.decodeIfPresent(String.self, forKey: .report) ?? ""
        bean = try values.decodeIfPresent(LegacyBean.self, forKey: .bean) ?? LegacyBean()
        traffic = try values.decodeIfPresent(LegacyTraffic.self, forKey: .traffic) ?? LegacyTraffic()
    }
}

private struct LegacyBean: Decodable {
    let name: String
    let address: String
    let port: Int

    private enum CodingKeys: String, CodingKey {
        case name, address = "addr", port
    }

    init() {
        name = ""
        address = ""
        port = 0
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        address = try values.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try values.decodeIfPresent(Int.self, forKey: .port) ?? 0
    }
}

private struct LegacyTraffic: Decodable {
    let uploaded: Int64
    let downloaded: Int64

    private enum CodingKeys: String, CodingKey {
        case uploaded = "ul", downloaded = "dl"
    }

    init() {
        uploaded = 0
        downloaded = 0
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        uploaded = try values.decodeIfPresent(Int64.self, forKey: .uploaded) ?? 0
        downloaded = try values.decodeIfPresent(Int64.self, forKey: .downloaded) ?? 0
    }
}
