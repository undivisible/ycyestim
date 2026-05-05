import Foundation

// MARK: - Active Session

struct SessionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var durationMs: Int
    var channelA: SessionChannelStats
    var channelB: SessionChannelStats?
    var presetsUsed: [String]
    var maxStrengthReached: Double
    var mode: ConnectionMode
    var notes: String

    struct SessionChannelStats: Codable, Equatable {
        var totalOutputMs: Int
        var avgStrength: Double
        var peakStrength: Double
        var waveformsUsed: [String]
    }

    init(id: UUID = UUID(),
         startTime: Date = .now,
         endTime: Date? = nil,
         durationMs: Int = 0,
         channelA: SessionChannelStats = .init(),
         channelB: SessionChannelStats? = nil,
         presetsUsed: [String] = [],
         maxStrengthReached: Double = 0,
         mode: ConnectionMode = .im,
         notes: String = "") {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationMs = durationMs
        self.channelA = channelA
        self.channelB = channelB
        self.presetsUsed = presetsUsed
        self.maxStrengthReached = maxStrengthReached
        self.mode = mode
        self.notes = notes
    }

    var isComplete: Bool { endTime != nil }

    var formattedDuration: String {
        let totalSec = durationMs / 1000
        let min = totalSec / 60
        let sec = totalSec % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - Session State (runtime)

enum SessionState: Equatable {
    case idle
    case starting
    case active(elapsedMs: Int, currentStep: Int)
    case stopping
    case emergencyStopped

    var isActive: Bool {
        switch self {
        case .active: return true
        default: return false
        }
    }
}
