import CryptoKit
import Foundation

struct CoreInstallationRecord: Codable, Hashable {
    let core: CoreKind
    let version: String
    let assetName: String
    let sourceURL: String
    let installedAt: Date
}

struct CoreDownloadResult: Hashable {
    let core: CoreKind
    let version: String
    let executableURL: URL
}

enum CoreInstallation {
    static func managedDirectory(for core: CoreKind) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "NekoBox", directoryHint: .isDirectory)
            .appending(path: "cores", directoryHint: .isDirectory)
            .appending(path: core.rawValue, directoryHint: .isDirectory)
    }

    static func managedExecutableURL(for core: CoreKind) -> URL {
        managedDirectory(for: core).appending(path: executableName(for: core))
    }

    static func record(for core: CoreKind) -> CoreInstallationRecord? {
        let url = managedDirectory(for: core).appending(path: "installation.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CoreInstallationRecord.self, from: data)
    }

    static func allRecords() -> [CoreKind: CoreInstallationRecord] {
        Dictionary(uniqueKeysWithValues: CoreKind.allCases.compactMap { core in
            record(for: core).map { (core, $0) }
        })
    }

    static func install(
        extractedExecutable: URL,
        core: CoreKind,
        version: String,
        assetName: String,
        sourceURL: URL
    ) throws -> CoreDownloadResult {
        let fileManager = FileManager.default
        let directory = managedDirectory(for: core)
        let destination = managedExecutableURL(for: core)
        let staging = directory.appending(path: ".\(executableName(for: core)).new")
        let backup = directory.appending(path: ".\(executableName(for: core)).previous")

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try removeIfPresent(staging, with: fileManager)
        try removeIfPresent(backup, with: fileManager)
        try fileManager.copyItem(at: extractedExecutable, to: staging)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)

        let hadExistingExecutable = fileManager.fileExists(atPath: destination.path)
        if hadExistingExecutable {
            try fileManager.moveItem(at: destination, to: backup)
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if hadExistingExecutable, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }

        try removeIfPresent(backup, with: fileManager)
        let record = CoreInstallationRecord(
            core: core,
            version: version,
            assetName: assetName,
            sourceURL: sourceURL.absoluteString,
            installedAt: .now
        )
        let recordURL = directory.appending(path: "installation.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: recordURL, options: .atomic)
        return CoreDownloadResult(core: core, version: version, executableURL: destination)
    }

    private static func executableName(for core: CoreKind) -> String {
        core.rawValue
    }

    private static func removeIfPresent(_ url: URL, with fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

enum CoreDownloadError: LocalizedError {
    case releaseRequestFailed(String, String)
    case assetUnavailable(String)
    case checksumUnavailable(String)
    case checksumMismatch
    case archiveExtractionFailed(String)
    case executableMissing(String)
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .releaseRequestFailed(let core, let reason):
            L10n.text("download.releaseRequestFailed", core, reason)
        case .assetUnavailable(let core):
            L10n.text("download.assetUnavailable", core)
        case .checksumUnavailable(let core):
            L10n.text("download.checksumUnavailable", core)
        case .checksumMismatch:
            L10n.text("download.checksumMismatch")
        case .archiveExtractionFailed(let reason):
            L10n.text("download.archiveExtractionFailed", reason)
        case .executableMissing(let core):
            L10n.text("download.executableMissing", core)
        case .installationFailed(let reason):
            L10n.text("download.installationFailed", reason)
        }
    }
}

enum CoreDownloader {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    static func downloadAndInstall(_ core: CoreKind) async throws -> CoreDownloadResult {
        let release = try await latestRelease(for: core)
        guard let asset = release.assets.first(where: { isCompatible($0, with: core) }) else {
            throw CoreDownloadError.assetUnavailable(core.displayName)
        }
        guard let checksum = normalizedChecksum(asset.digest) else {
            throw CoreDownloadError.checksumUnavailable(core.displayName)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "NekoBox-Core-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let archiveURL = temporaryDirectory.appending(path: asset.name)
        let downloadedURL = try await download(asset: asset, core: core)
        try FileManager.default.copyItem(at: downloadedURL, to: archiveURL)

        let archiveData = try Data(contentsOf: archiveURL)
        let actualChecksum = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard actualChecksum.caseInsensitiveCompare(checksum) == .orderedSame else {
            throw CoreDownloadError.checksumMismatch
        }

        let extractionDirectory = temporaryDirectory.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try extract(archiveURL, for: core, into: extractionDirectory)
        guard let executable = findExecutable(for: core, in: extractionDirectory) else {
            throw CoreDownloadError.executableMissing(core.displayName)
        }

        do {
            return try CoreInstallation.install(
                extractedExecutable: executable,
                core: core,
                version: release.tagName,
                assetName: asset.name,
                sourceURL: asset.browserDownloadURL
            )
        } catch {
            throw CoreDownloadError.installationFailed(error.localizedDescription)
        }
    }

    static func officialReleaseURL(for core: CoreKind) -> URL {
        URL(string: "https://github.com/\(repository(for: core))/releases/latest")!
    }

    private static func latestRelease(for core: CoreKind) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repository(for: core))/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NekoBox macOS", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw CoreDownloadError.releaseRequestFailed(core.displayName, "HTTP request failed")
            }
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch let error as CoreDownloadError {
            throw error
        } catch {
            throw CoreDownloadError.releaseRequestFailed(core.displayName, error.localizedDescription)
        }
    }

    private static func download(asset: GitHubAsset, core: CoreKind) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("NekoBox macOS", forHTTPHeaderField: "User-Agent")
        do {
            let (url, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw CoreDownloadError.releaseRequestFailed(core.displayName, "Asset download failed")
            }
            return url
        } catch let error as CoreDownloadError {
            throw error
        } catch {
            throw CoreDownloadError.releaseRequestFailed(core.displayName, error.localizedDescription)
        }
    }

    private static func extract(_ archiveURL: URL, for core: CoreKind, into directory: URL) throws {
        switch core {
        case .xray:
            try runCommand("/usr/bin/unzip", arguments: ["-qq", archiveURL.path, "-d", directory.path])
        case .singBox:
            try runCommand("/usr/bin/tar", arguments: ["-xzf", archiveURL.path, "-C", directory.path])
        }
    }

    private static func findExecutable(for core: CoreKind, in directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let candidate as URL in enumerator {
            guard candidate.lastPathComponent == core.rawValue,
                  (try? candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                continue
            }
            return candidate
        }
        return nil
    }

    private static func runCommand(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw CoreDownloadError.archiveExtractionFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CoreDownloadError.archiveExtractionFailed(String(message.prefix(1_000)))
        }
    }

    private static func repository(for core: CoreKind) -> String {
        switch core {
        case .xray: "XTLS/Xray-core"
        case .singBox: "SagerNet/sing-box"
        }
    }

    private static func isCompatible(_ asset: GitHubAsset, with core: CoreKind) -> Bool {
        let name = asset.name.lowercased()
        return switch core {
        case .xray:
            name.hasPrefix("xray-macos-arm64") && name.hasSuffix(".zip")
        case .singBox:
            name.hasPrefix("sing-box-")
                && name.contains("darwin-arm64")
                && name.hasSuffix(".tar.gz")
        }
    }

    private static func normalizedChecksum(_ value: String?) -> String? {
        guard let value,
              value.lowercased().hasPrefix("sha256:")
        else {
            return nil
        }
        let checksum = String(value.dropFirst("sha256:".count))
        return checksum.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) == nil ? nil : checksum
    }
}
