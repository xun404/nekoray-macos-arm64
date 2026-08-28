import Foundation

enum CoreKind: String, CaseIterable, Codable, Identifiable {
    case xray
    case singBox = "sing-box"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xray: "Xray"
        case .singBox: "sing-box"
        }
    }

    var selectedOrDetectedPath: String {
        switch self {
        case .xray: XrayCoreLocator.selectedOrDetectedPath
        case .singBox: SingBoxCoreLocator.selectedOrDetectedPath
        }
    }

    var isAvailable: Bool {
        switch self {
        case .xray: XrayCoreLocator.executableURL != nil
        case .singBox: SingBoxCoreLocator.executableURL != nil
        }
    }

    var hasCustomExecutable: Bool {
        switch self {
        case .xray: XrayCoreLocator.hasCustomExecutable
        case .singBox: SingBoxCoreLocator.hasCustomExecutable
        }
    }

    func setExecutable(_ url: URL) {
        switch self {
        case .xray: XrayCoreLocator.setExecutable(url)
        case .singBox: SingBoxCoreLocator.setExecutable(url)
        }
    }

    func clearCustomExecutable() {
        switch self {
        case .xray: XrayCoreLocator.clearCustomExecutable()
        case .singBox: SingBoxCoreLocator.clearCustomExecutable()
        }
    }
}

/// The native UI depends on this protocol instead of a concrete process
/// implementation so each supported core can manage its own lifecycle.
@MainActor
protocol CoreService {
    var availability: CoreAvailability { get }
    var isRunning: Bool { get }
    func start(profile: ProxyProfile) async throws
    func stop() async throws
}

enum CoreServiceManagerError: LocalizedError {
    case switchWhileRunning

    var errorDescription: String? {
        switch self {
        case .switchWhileRunning:
            L10n.text("core.switchWhileRunning")
        }
    }
}

@MainActor
final class CoreServiceManager: CoreService {
    private static let selectedCorePreferenceKey = "selectedCore"

    private let xrayService = XrayCoreService()
    private let singBoxService = SingBoxCoreService()

    private(set) var selectedCore: CoreKind

    init() {
        selectedCore = CoreKind(
            rawValue: UserDefaults.standard.string(forKey: Self.selectedCorePreferenceKey) ?? ""
        ) ?? .xray
    }

    var availability: CoreAvailability {
        currentService.availability
    }

    var isRunning: Bool {
        xrayService.isRunning || singBoxService.isRunning
    }

    func select(_ core: CoreKind) throws {
        guard !isRunning else { throw CoreServiceManagerError.switchWhileRunning }
        selectedCore = core
        UserDefaults.standard.set(core.rawValue, forKey: Self.selectedCorePreferenceKey)
    }

    func start(profile: ProxyProfile) async throws {
        try await currentService.start(profile: profile)
    }

    func stop() async throws {
        try await currentService.stop()
    }

    private var currentService: any CoreService {
        switch selectedCore {
        case .xray: xrayService
        case .singBox: singBoxService
        }
    }
}
