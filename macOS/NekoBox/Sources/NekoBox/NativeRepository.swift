import Foundation

struct NativeSnapshot: Codable {
    var groups: [ProxyGroup]
    var profiles: [ProxyProfile]
    var selectedGroupID: Int?
    var selectedProfileID: Int?

    static let empty = NativeSnapshot(
        groups: [],
        profiles: [],
        selectedGroupID: nil,
        selectedProfileID: nil
    )
}

struct NativeRepository {
    private let fileManager: FileManager
    let stateURL: URL

    init(
        stateURL: URL = NativeRepository.defaultStateURL(),
        fileManager: FileManager = .default
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
    }

    func load() -> NativeSnapshot {
        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let snapshot = try? JSONDecoder().decode(NativeSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    func save(_ snapshot: NativeSnapshot) throws {
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: stateURL, options: .atomic)
    }

    static func defaultStateURL() -> URL {
        let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "NekoBox", directoryHint: .isDirectory)
        return applicationSupport.appending(path: "profiles.json")
    }
}
