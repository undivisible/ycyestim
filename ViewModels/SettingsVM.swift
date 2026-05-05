import Foundation

// MARK: - Settings ViewModel

@MainActor
final class SettingsVM: ObservableObject {
    @Published var safetyConfig: SafetyConfig
    @Published var connectionConfig: ConnectionConfig
    @Published var appearanceConfig: AppearanceConfig
    @Published var notificationConfig: NotificationConfig
    @Published var heartRateSafetyConfig: HeartRateSafetyConfig
    @Published var edgeModeConfig: EdgeModeConfig
    @Published var channelAConfig: ChannelConfig
    @Published var channelBConfig: ChannelConfig
    @Published var programConfig: ProgramConfig

    struct ProgramConfig: Codable, Equatable {
        var autoProgress: Bool
        var defaultLoopCount: Int
        var defaultTransitionSmoothness: Double
        var defaultPauseBetweenSteps: Int

        static let `default` = ProgramConfig(
            autoProgress: true,
            defaultLoopCount: 0,
            defaultTransitionSmoothness: 0.5,
            defaultPauseBetweenSteps: 0
        )
    }

    private let safetyKey = "ycy.safety"
    private let connectionKey = "ycy.connection"
    private let appearanceKey = "ycy.appearance"
    private let notificationsKey = "ycy.notifications"
    private let heartRateSafetyKey = "ycy.heartRateSafety"
    private let edgeModeKey = "ycy.edgeMode"
    private let channelAKey = "ycy.channelA"
    private let channelBKey = "ycy.channelB"
    private let programKey = "ycy.program"

    init() {
        safetyConfig = Self.load(safetyKey) ?? .default
        connectionConfig = Self.load(connectionKey) ?? .default
        appearanceConfig = Self.load(appearanceKey) ?? .default
        notificationConfig = Self.load(notificationsKey) ?? .default
        heartRateSafetyConfig = Self.load(heartRateSafetyKey) ?? .default
        edgeModeConfig = Self.load(edgeModeKey) ?? .default
        channelAConfig = Self.load(channelAKey) ?? .standard
        channelBConfig = Self.load(channelBKey) ?? .standard
        programConfig = Self.load(programKey) ?? .default
    }

    func saveAll() {
        Self.save(safetyConfig, safetyKey)
        Self.save(connectionConfig, connectionKey)
        Self.save(appearanceConfig, appearanceKey)
        Self.save(notificationConfig, notificationsKey)
        Self.save(heartRateSafetyConfig, heartRateSafetyKey)
        Self.save(edgeModeConfig, edgeModeKey)
        Self.save(channelAConfig, channelAKey)
        Self.save(channelBConfig, channelBKey)
        Self.save(programConfig, programKey)
    }

    func resetToDefaults() {
        safetyConfig = .default
        connectionConfig = .default
        appearanceConfig = .default
        notificationConfig = .default
        heartRateSafetyConfig = .default
        edgeModeConfig = .default
        channelAConfig = .standard
        channelBConfig = .standard
        programConfig = .default
        saveAll()
    }

    private static func load<T: Codable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Codable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
