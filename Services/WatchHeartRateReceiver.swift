import Foundation
import WatchConnectivity

final class WatchHeartRateReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onReading: @MainActor @Sendable (HeartRateReading) -> Void

    init(onReading: @escaping @MainActor @Sendable (HeartRateReading) -> Void) {
        self.onReading = onReading
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    deinit {
        if WCSession.isSupported(), WCSession.default.delegate === self {
            WCSession.default.delegate = nil
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        emitReading(from: message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        emitReading(from: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        emitReading(from: userInfo)
    }

    private func emitReading(from payload: [String: Any]) {
        guard let bpm = payload["bpm"] as? Double else { return }
        let timestamp = payload["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let reading = HeartRateReading(bpm: bpm, sampleDate: Date(timeIntervalSince1970: timestamp))
        Task { @MainActor in
            onReading(reading)
        }
    }
}
