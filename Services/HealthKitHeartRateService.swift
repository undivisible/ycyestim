import Foundation
import HealthKit

enum HeartRateServiceError: Error, LocalizedError {
    case unavailable
    case heartRateTypeUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit is not available on this device"
        case .heartRateTypeUnavailable:
            return "Heart rate data is unavailable"
        }
    }
}

struct HeartRateReading: Equatable {
    let bpm: Double
    let sampleDate: Date
}

enum HeartRateAuthorizationStatus: Equatable {
    case unavailable
    case unknown
    case shouldRequest
    case unnecessary
}

final class HealthKitHeartRateService: @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    deinit {
        stopMonitoring()
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HeartRateServiceError.unavailable
        }
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw HeartRateServiceError.heartRateTypeUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: [heartRate]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HeartRateServiceError.unavailable)
                }
            }
        }
    }

    func authorizationStatus() async throws -> HeartRateAuthorizationStatus {
        guard isAvailable else {
            return .unavailable
        }
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw HeartRateServiceError.heartRateTypeUnavailable
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HeartRateAuthorizationStatus, Error>) in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [heartRate]) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                switch status {
                case .unknown:
                    continuation.resume(returning: .unknown)
                case .shouldRequest:
                    continuation.resume(returning: .shouldRequest)
                case .unnecessary:
                    continuation.resume(returning: .unnecessary)
                @unknown default:
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    func startMonitoring(onUpdate: @escaping @MainActor (HeartRateReading) -> Void) throws {
        guard isAvailable else {
            throw HeartRateServiceError.unavailable
        }
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            throw HeartRateServiceError.heartRateTypeUnavailable
        }

        stopMonitoring()

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKAnchoredObjectQuery(
            type: heartRate,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            Self.emitLatestBPM(from: samples, onUpdate: onUpdate)
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            Self.emitLatestBPM(from: samples, onUpdate: onUpdate)
        }

        self.query = query
        healthStore.execute(query)

        let sampleQuery = HKSampleQuery(
            sampleType: heartRate,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            Self.emitLatestBPM(from: samples, onUpdate: onUpdate)
        }
        healthStore.execute(sampleQuery)
    }

    func stopMonitoring() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
    }

    private static func emitLatestBPM(from samples: [HKSample]?, onUpdate: @escaping @MainActor (HeartRateReading) -> Void) {
        guard let sample = samples?.compactMap({ $0 as? HKQuantitySample }).max(by: { $0.endDate < $1.endDate }) else {
            return
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = sample.quantity.doubleValue(for: unit)
        let reading = HeartRateReading(bpm: bpm, sampleDate: sample.endDate)
        Task { @MainActor in
            onUpdate(reading)
        }
    }
}
