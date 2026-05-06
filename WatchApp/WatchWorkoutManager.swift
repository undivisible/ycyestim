import Combine
import Foundation
import HealthKit
import WatchConnectivity

enum WatchWorkoutStatus: Equatable {
    case idle
    case authorizing
    case running
    case ending
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "Ready"
        case .authorizing:
            return "Authorizing"
        case .running:
            return "Running"
        case .ending:
            return "Ending"
        case .failed(let message):
            return message
        }
    }
}

final class WatchWorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, WCSessionDelegate, @unchecked Sendable {
    @Published var status: WatchWorkoutStatus = .idle
    @Published var latestBPM: Double?
    @Published var elapsedSeconds = 0

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var elapsedTimer: Timer?

    override init() {
        super.init()
        activateConnectivity()
    }

    deinit {
        elapsedTimer?.invalidate()
        session?.delegate = nil
        builder?.delegate = nil
        if WCSession.isSupported(), WCSession.default.delegate === self {
            WCSession.default.delegate = nil
        }
    }

    @MainActor
    func startWorkout() async {
        status = .authorizing

        do {
            try await requestAuthorization()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .other
            configuration.locationType = .unknown

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            self.startDate = startDate
            session.startActivity(with: startDate)
            try await beginCollection(builder: builder, at: startDate)

            status = .running
            startElapsedTimer()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func stopWorkout() {
        guard session != nil else { return }
        status = .ending
        elapsedTimer?.invalidate()
        session?.end()
    }

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HeartRateWorkoutError.unavailable
        }
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw HeartRateWorkoutError.heartRateUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [heartRate]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HeartRateWorkoutError.authorizationDenied)
                }
            }
        }
    }

    private func beginCollection(builder: HKLiveWorkoutBuilder, at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: date) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func finishWorkout() {
        let endDate = Date()
        builder?.endCollection(withEnd: endDate) { [weak self] _, error in
            if let error {
                Task { @MainActor in
                    self?.status = .failed(error.localizedDescription)
                }
                return
            }

            self?.builder?.finishWorkout { _, error in
                Task { @MainActor in
                    if let error {
                        self?.status = .failed(error.localizedDescription)
                    } else {
                        self?.status = .idle
                    }
                    self?.session = nil
                    self?.builder = nil
                    self?.startDate = nil
                    self?.elapsedSeconds = 0
                }
            }
        }
    }

    private func activateConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func sendHeartRate(_ bpm: Double, sampleDate: Date) {
        let payload: [String: Any] = [
            "bpm": bpm,
            "timestamp": sampleDate.timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil)
        }
        try? WCSession.default.updateApplicationContext(payload)
        WCSession.default.transferUserInfo(payload)
    }

    @MainActor
    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startDate = self.startDate else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startDate))
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended {
            finishWorkout()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            status = .failed(error.localizedDescription)
            elapsedTimer?.invalidate()
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType) else {
            return
        }

        let bpm = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        guard let bpm else { return }
        let sampleDate = statistics.endDate

        sendHeartRate(bpm, sampleDate: sampleDate)
        Task { @MainActor in
            latestBPM = bpm
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }
}

enum HeartRateWorkoutError: Error, LocalizedError {
    case unavailable
    case heartRateUnavailable
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit is unavailable on this watch"
        case .heartRateUnavailable:
            return "Heart rate is unavailable"
        case .authorizationDenied:
            return "HealthKit permission was not granted"
        }
    }
}
