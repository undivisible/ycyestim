import Foundation

// MARK: - Preset Store (persistent storage)

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [Preset] = []
    @Published var programs: [Program] = []
    @Published var sessions: [SessionRecord] = []

    private let presetsKey = "ycy.presets"
    private let programsKey = "ycy.programs"
    private let sessionsKey = "ycy.sessions"

    init() {
        loadPresets()
        loadPrograms()
        loadSessions()
    }

    // MARK: - Presets

    private func loadPresets() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: presetsKey),
           let loaded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = Preset.allBuiltins + loaded.filter { !$0.isBuiltin }
        } else {
            presets = Preset.allBuiltins
        }
    }

    func savePreset(_ preset: Preset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persistPresets()
    }

    func deletePreset(_ preset: Preset) {
        guard !preset.isBuiltin else { return }
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        let custom = presets.filter { !$0.isBuiltin }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    // MARK: - Export/Import

    func exportPresets() -> Data? {
        let custom = presets.filter { !$0.isBuiltin }
        return try? JSONEncoder().encode(custom)
    }

    func importPresets(from data: Data) {
        guard let imported = try? JSONDecoder().decode([Preset].self, from: data) else {
            return
        }
        presets.append(contentsOf: imported)
        persistPresets()
    }

    // MARK: - Programs

    private func loadPrograms() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: programsKey),
           let loaded = try? JSONDecoder().decode([Program].self, from: data) {
            programs = Program.allBuiltins + loaded
        } else {
            programs = Program.allBuiltins
        }
    }

    func saveProgram(_ program: Program) {
        if let index = programs.firstIndex(where: { $0.id == program.id }) {
            programs[index] = program
        } else {
            programs.append(program)
        }
        persistPrograms()
    }

    func deleteProgram(_ program: Program) {
        programs.removeAll { $0.id == program.id }
        persistPrograms()
    }

    private func persistPrograms() {
        if let data = try? JSONEncoder().encode(programs) {
            UserDefaults.standard.set(data, forKey: programsKey)
        }
    }

    // MARK: - Sessions

    private func loadSessions() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: sessionsKey),
           let loaded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            sessions = loaded.sorted { $0.startTime > $1.startTime }
        }
    }

    func saveSession(_ session: SessionRecord) {
        sessions.insert(session, at: 0)
        // Keep last 100 sessions
        if sessions.count > 100 {
            sessions = Array(sessions.prefix(100))
        }
        persistSessions()
    }

    func deleteAllSessions() {
        sessions = []
        UserDefaults.standard.removeObject(forKey: sessionsKey)
    }

    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}
