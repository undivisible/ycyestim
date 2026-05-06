import Foundation

// MARK: - HTTP/WS Service (API-bridge)

actor HTTPService {
    private var baseURL: URL?
    private var apiKey: String = ""
    private var wsTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var messageHandler: ((String) -> Void)?

    deinit {
        wsTask?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - Connection

    func connect(url: String, apiKey: String) async throws {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedURL = URL(string: trimmedURL),
              let scheme = parsedURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              parsedURL.host?.isEmpty == false else {
            throw HTTPServiceError.invalidURL
        }

        baseURL = parsedURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        isConnected = false
        try await verifyReady()
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
        guard let baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            isConnected = false
            return
        }
        if components.scheme == "https" {
            components.scheme = "wss"
        } else {
            components.scheme = "ws"
        }
        guard let wsURL = components.url else {
            isConnected = false
            return
        }
        wsTask = URLSession.shared.webSocketTask(with: wsURL)
        wsTask?.resume()
        listenForMessages()
    }

    private func listenForMessages() {
        wsTask?.receive { [weak self] result in
            Task {
                await self?.handleWebSocketResult(result)
            }
        }
    }

    private func handleWebSocketResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                messageHandler?(text)
            case .data:
                break
            @unknown default:
                break
            }
            listenForMessages()
        case .failure:
            break
        }
    }

    func onMessage(_ handler: @escaping (String) -> Void) {
        messageHandler = handler
    }

    // MARK: - HTTP Commands

    func sendCommandID(_ commandID: String) async throws {
        guard isConnected else {
            throw HTTPServiceError.notConnected
        }

        let trimmedID = commandID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw HTTPServiceError.missingCommandID
        }

        let url = try endpoint("api", "send-command")
        var request = authorizedRequest(for: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["commandId": trimmedID])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPServiceError.sendFailed
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = object["success"] as? Bool,
           !success {
            throw HTTPServiceError.sendFailed
        }
    }

    func sendChannelControl(commandID: String) async throws {
        try await sendCommandID(commandID)
    }

    func emergencyStop(commandID: String = "_stop_all") async throws {
        try await sendCommandID(commandID)
    }

    // MARK: - Status

    func getStatus() async throws -> String {
        let url = try endpoint("api", "status")
        let (data, _) = try await URLSession.shared.data(for: authorizedRequest(for: url))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func healthCheck() async -> Bool {
        guard let url = try? endpoint("health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(for: authorizedRequest(for: url))
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func endpoint(_ components: String...) throws -> URL {
        guard var url = baseURL else { throw HTTPServiceError.invalidURL }
        for component in components {
            url.appendPathComponent(component)
        }
        return url
    }

    private func authorizedRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return request
    }

    private func verifyReady() async throws {
        let url = try endpoint("health")
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(for: url))
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw HTTPServiceError.bridgeNotReady
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let imReady = object["imReady"] as? Bool,
           !imReady {
            throw HTTPServiceError.bridgeNotReady
        }
    }
}

// MARK: - Errors

enum HTTPServiceError: Error, LocalizedError {
    case notConnected
    case sendFailed
    case invalidURL
    case bridgeNotReady
    case missingCommandID

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to server"
        case .sendFailed: return "Failed to send command"
        case .invalidURL: return "Invalid server URL"
        case .bridgeNotReady: return "HTTP bridge is reachable but IM is not ready"
        case .missingCommandID: return "Missing HTTP command ID"
        }
    }
}
