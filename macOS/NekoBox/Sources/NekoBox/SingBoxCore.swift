import Foundation

enum SingBoxCoreLocator {
    private static let executablePreferenceKey = "singBoxExecutablePath"

    static var executableURL: URL? {
        if let path = UserDefaults.standard.string(forKey: executablePreferenceKey), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        for candidate in automaticCandidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    static var selectedOrDetectedPath: String {
        executableURL?.path ?? L10n.text("singbox.notFound")
    }

    static var hasCustomExecutable: Bool {
        let path = UserDefaults.standard.string(forKey: executablePreferenceKey) ?? ""
        return !path.isEmpty
    }

    static func setExecutable(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: executablePreferenceKey)
    }

    static func clearCustomExecutable() {
        UserDefaults.standard.removeObject(forKey: executablePreferenceKey)
    }

    static func configurationURL() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "NekoBox", directoryHint: .isDirectory)
            .appending(path: "config", directoryHint: .isDirectory)
            .appending(path: "sing-box", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "config.json")
    }

    private static var automaticCandidates: [URL] {
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "sing-box", withExtension: nil) {
            candidates.append(bundled)
        }
        candidates += [
            CoreInstallation.managedExecutableURL(for: .singBox),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "NekoBox", directoryHint: .isDirectory)
                .appending(path: "sing-box"),
            URL(fileURLWithPath: "/opt/homebrew/bin/sing-box"),
            URL(fileURLWithPath: "/usr/local/bin/sing-box"),
        ]
        return candidates
    }
}

enum SingBoxConfigurationError: LocalizedError {
    case unsupportedProtocol(String)
    case unsupportedTransport(String)
    case missingCredential(String)
    case missingRealityKey
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocol(let protocolName):
            L10n.text("singbox.unsupportedProtocol", protocolName)
        case .unsupportedTransport(let transport):
            L10n.text("singbox.unsupportedTransport", transport)
        case .missingCredential(let credential):
            L10n.text("singbox.missingCredential", credential)
        case .missingRealityKey:
            L10n.text("singbox.missingRealityKey")
        case .invalidEndpoint:
            L10n.text("singbox.invalidEndpoint")
        }
    }
}

enum SingBoxConfigurationGenerator {
    static let socksPort = 10_808
    static let httpPort = 10_809

    static func configurationData(for profile: ProxyProfile) throws -> Data {
        let configuration: [String: Any] = [
            "log": ["level": "warn"],
            "inbounds": [
                [
                    "type": "socks",
                    "tag": "socks-in",
                    "listen": "127.0.0.1",
                    "listen_port": socksPort,
                    "sniff": true,
                ],
                [
                    "type": "http",
                    "tag": "http-in",
                    "listen": "127.0.0.1",
                    "listen_port": httpPort,
                    "sniff": true,
                ],
            ],
            "outbounds": [
                try outbound(for: profile),
                ["type": "direct", "tag": "direct"],
                ["type": "block", "tag": "block"],
            ],
            "route": [
                "rules": [
                    [
                        "inbound": ["socks-in", "http-in"],
                        "outbound": "proxy",
                    ],
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
    }

    private static func outbound(for profile: ProxyProfile) throws -> [String: Any] {
        let endpoint = try endpoint(from: profile.address)
        let settings = profile.xraySettings ?? XrayProfileSettings()
        let protocolName = normalizedProtocol(profile.type)
        var outbound: [String: Any] = [
            "type": protocolName,
            "tag": "proxy",
            "server": endpoint.address,
            "server_port": endpoint.port,
        ]

        switch protocolName {
        case "vless", "vmess":
            guard !settings.userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SingBoxConfigurationError.missingCredential("\(protocolName.uppercased()) UUID")
            }
            outbound["uuid"] = settings.userID
            if protocolName == "vless", !settings.flow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outbound["flow"] = settings.flow
            }
            if protocolName == "vmess", !settings.vmessSecurity.isEmpty {
                outbound["security"] = settings.vmessSecurity
            }
        case "trojan":
            guard !settings.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SingBoxConfigurationError.missingCredential("Trojan password")
            }
            outbound["password"] = settings.password
        case "shadowsocks":
            guard !settings.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SingBoxConfigurationError.missingCredential("Shadowsocks password")
            }
            outbound["method"] = settings.method
            outbound["password"] = settings.password
            return outbound
        default:
            throw SingBoxConfigurationError.unsupportedProtocol(protocolName)
        }

        if let tls = try tlsSettings(for: settings.stream) {
            outbound["tls"] = tls
        }
        if let transport = try transportSettings(for: settings.stream) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func tlsSettings(for settings: XrayStreamSettings) throws -> [String: Any]? {
        let usesReality = !settings.realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || settings.security.lowercased() == "reality"
        let usesTLS = settings.security.lowercased() == "tls"
        guard usesReality || usesTLS else { return nil }

        var result: [String: Any] = [
            "enabled": true,
            "insecure": settings.allowInsecure,
        ]
        if !settings.serverName.isEmpty { result["server_name"] = settings.serverName }
        if !settings.fingerprint.isEmpty {
            result["utls"] = ["enabled": true, "fingerprint": settings.fingerprint]
        }
        if usesReality {
            guard !settings.realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SingBoxConfigurationError.missingRealityKey
            }
            result["reality"] = [
                "enabled": true,
                "public_key": settings.realityPublicKey,
                "short_id": settings.realityShortID,
            ]
        }
        return result
    }

    private static func transportSettings(for settings: XrayStreamSettings) throws -> [String: Any]? {
        switch settings.network.lowercased() {
        case "", "tcp", "raw":
            return nil
        case "ws", "websocket":
            var result: [String: Any] = ["type": "ws"]
            if !settings.path.isEmpty { result["path"] = settings.path }
            if !settings.host.isEmpty { result["headers"] = ["Host": settings.host] }
            return result
        case "grpc":
            var result: [String: Any] = ["type": "grpc"]
            if !settings.path.isEmpty { result["service_name"] = settings.path }
            return result
        case "httpupgrade":
            var result: [String: Any] = ["type": "httpupgrade"]
            if !settings.path.isEmpty { result["path"] = settings.path }
            if !settings.host.isEmpty { result["host"] = settings.host }
            return result
        default:
            throw SingBoxConfigurationError.unsupportedTransport(settings.network)
        }
    }

    private static func normalizedProtocol(_ value: String) -> String {
        switch value.lowercased() {
        case "ss": "shadowsocks"
        default: value.lowercased()
        }
    }

    private static func endpoint(from value: String) throws -> (address: String, port: Int) {
        if value.hasPrefix("["),
           let closingBracket = value.firstIndex(of: "]"),
           value.index(after: closingBracket) < value.endIndex,
           value[value.index(after: closingBracket)] == ":",
           let port = Int(value[value.index(closingBracket, offsetBy: 2)...]) {
            return (String(value[value.index(after: value.startIndex)..<closingBracket]), port)
        }

        guard let separator = value.lastIndex(of: ":"),
              let port = Int(value[value.index(after: separator)...])
        else {
            throw SingBoxConfigurationError.invalidEndpoint
        }
        return (String(value[..<separator]), port)
    }
}

enum SingBoxCoreError: LocalizedError {
    case executableNotFound
    case alreadyRunning
    case validationFailed(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            L10n.text("singbox.executableNotFound")
        case .alreadyRunning:
            L10n.text("singbox.alreadyRunning")
        case .validationFailed(let output):
            L10n.text("singbox.validationFailed", output)
        case .launchFailed(let reason):
            L10n.text("singbox.launchFailed", reason)
        }
    }
}

@MainActor
final class SingBoxCoreService: CoreService {
    private var process: Process?

    var availability: CoreAvailability {
        SingBoxCoreLocator.executableURL == nil ? .unavailable : .ready
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(profile: ProxyProfile) async throws {
        guard !isRunning else { throw SingBoxCoreError.alreadyRunning }
        guard let executableURL = SingBoxCoreLocator.executableURL else {
            throw SingBoxCoreError.executableNotFound
        }

        let configurationURL = try SingBoxCoreLocator.configurationURL()
        try SingBoxConfigurationGenerator.configurationData(for: profile).write(to: configurationURL, options: .atomic)
        try validate(configurationAt: configurationURL, with: executableURL)

        let singBox = Process()
        singBox.executableURL = executableURL
        singBox.arguments = ["run", "-c", configurationURL.path]
        singBox.currentDirectoryURL = executableURL.deletingLastPathComponent()
        singBox.standardOutput = Pipe()
        singBox.standardError = Pipe()
        do {
            try singBox.run()
        } catch {
            throw SingBoxCoreError.launchFailed(error.localizedDescription)
        }
        process = singBox
    }

    func stop() async throws {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil
    }

    private func validate(configurationAt configurationURL: URL, with executableURL: URL) throws {
        let validator = Process()
        let output = Pipe()
        validator.executableURL = executableURL
        validator.arguments = ["check", "-c", configurationURL.path]
        validator.currentDirectoryURL = executableURL.deletingLastPathComponent()
        validator.standardOutput = output
        validator.standardError = output
        do {
            try validator.run()
        } catch {
            throw SingBoxCoreError.launchFailed(error.localizedDescription)
        }
        validator.waitUntilExit()
        guard validator.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SingBoxCoreError.validationFailed(String(text.prefix(1_000)))
        }
    }
}
