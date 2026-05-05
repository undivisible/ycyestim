import Foundation

// MARK: - HTTP/WS Service (API-bridge)

actor HTTPService {
    private var baseURL: String = ""
    private var wsTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var messageHandler: ((String) -> Void)?

    // MARK: - Connection

    func connect(url: String) {
        baseURL = url
        isConnected = true
        startWebSocket()
    }

    func disconnect() {
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        isConnected = false
    }

    // MARK: - WebSocket

    private func startWebSocket() {
        guard let wsURL = URL(string: baseURL.replacingOccurrences(of: "http", with: "ws")) else {
            return
        }
        wsTask = URLSession.shared.webSocketTask(with: wsURL)
        wsTask?.resume()
        listenForMessages()
    }

    private func listenForMessages() {
        wsTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.messageHandler?(text)
                case .data:
                    break
                @unknown default:
                    break
                }
                self?.listenForMessages()
            case .failure:
                break
            }
        }
    }

    func onMessage(_ handler: @escaping (String) -> Void) {
        messageHandler = handler
    }

    // MARK: - HTTP Commands

    func sendCommand(_ command: [String: Any]) async throws {
        guard isConnected else {
            throw HTTPServiceError.notConnected
        }

        let url = URL(string: "\(baseURL)/api/send-command")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: command)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPServiceError.sendFailed
        }
    }

    func sendChannelControl(channel: String, strength: Int, durationMs: Int) async throws {
        let command: [String: Any] = [
            "commandId": "channel_control",
            "data": [
                "channel": channel,
                "strength": strength,
                "duration_ms": durationMs
            ]
        ]
        try await sendCommand(command)
    }

    func emergencyStop() async throws {
        let command: [String: Any] = [
            "commandId": "emergency_stop"
        ]
        try await sendCommand(command)
    }

    // MARK: - Status

    func getStatus() async throws -> String {
        let url = URL(string: "\(baseURL)/api/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum HTTPServiceError: Error, LocalizedError {
    case notConnected
    case sendFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to server"
        case .sendFailed: return "Failed to send command"
        case .invalidURL: return "Invalid server URL"
        }
    }
}
