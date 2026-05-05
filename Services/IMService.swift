import Foundation
import UIKit

// MARK: - Error Types

enum IMServiceError: Error, LocalizedError {
    case invalidConnectCode
    case authFailed(String)
    case notConnected
    case sendFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidConnectCode:
            return "Invalid connect code. Format: UID TOKEN (space-separated)"
        case .authFailed(let msg):
            return "Authentication failed: \(msg)"
        case .notConnected:
            return "Not connected to IM"
        case .sendFailed(let msg):
            return "Failed to send: \(msg)"
        case .timeout:
            return "Connection timed out"
        }
    }
}

// MARK: - IM Service (Tencent Cloud IM)

actor IMService {
    private static let apiBase = "https://suo.jiushu1234.com/api.php"

    private var isConnected = false
    private var appId: String = ""
    private var userSig: String = ""
    private var uid: String = ""
    private var token: String = ""

    // MARK: - Auth

    /// Parse connect code and authenticate
    /// - Parameter connectCode: "UID TOKEN" space-separated string
    func authenticate(connectCode: String) async throws {
        let trimmed = connectCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1)

        guard parts.count == 2 else {
            throw IMServiceError.invalidConnectCode
        }

        uid = String(parts[0])
        token = String(parts[1])

        // Request game sign from YCY API
        let signResponse = try await requestGameSign()
        appId = signResponse.appid
        userSig = signResponse.sign

        // In a real app, initialize TencentCloudIM SDK here:
        // let chat = TencentCloudChat.create(SDKAppID: appId)
        // await chat.login(userID: "game_\(uid)", userSig: userSig)

        isConnected = true
    }

    /// Call the YCY game_sign API
    private func requestGameSign() async throws -> GameSignResponse {
        let url = URL(string: "\(Self.apiBase)/user/game_sign")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["connect_code": "\(uid) \(token)"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IMServiceError.authFailed("HTTP error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = json?["code"] as? Int, code == 1,
              let dataDict = json?["data"] as? [String: Any],
              let appid = dataDict["appid"] as? String,
              let sign = dataDict["sign"] as? String else {
            throw IMServiceError.authFailed("Invalid response")
        }

        return GameSignResponse(appid: appid, sign: sign)
    }

    // MARK: - Commands

    /// Send a game command
    /// - Parameter command: Command object
    func send(command: GameCommand) async throws {
        guard isConnected else {
            throw IMServiceError.notConnected
        }

        // In production, this would use TencentCloudIM SDK:
        // let msg = chat.createTextMessage(...)
        // chat.sendMessage(msg)

        // For now, log the command
        let payload = command.toJSON()
        print("[IM] Sending command: \(payload)")
    }

    /// Send channel control command
    /// - Parameters:
    ///   - channel: Channel identifier ("A", "B", or "AB")
    ///   - strength: 0–100
    ///   - durationMs: Duration in milliseconds (0 = indefinite)
    func sendChannelControl(channel: String, strength: Int, durationMs: Int) async throws {
        let action = ChannelControlAction(
            channel: channel,
            strength: strength,
            durationMs: durationMs
        )
        let command = GameCommand.gameOpts(actions: [action])
        try await send(command: command)
    }

    /// Trigger a preset/command by ID
    /// - Parameter id: Command/preset ID
    func trigger(id: String) async throws {
        let command = GameCommand.gameCmd(id: id, payload: nil)
        try await send(command: command)
    }

    /// Emergency stop all channels
    func emergencyStop() async throws {
        try await trigger(id: "_stop_all")
    }

    // MARK: - Connection State

    func disconnect() async {
        isConnected = false
        // In production: await chat.logout()
        // await chat.destroy()
    }

    var connectionState: ConnectionState {
        isConnected ? .connected : .disconnected
    }

    enum ConnectionState {
        case connected
        case connecting
        case disconnected
    }

    // MARK: - Response Models

    struct GameSignResponse {
        let appid: String
        let sign: String
    }
}

// MARK: - Command Models

enum GameCommand {
    case gameOpts(actions: [ChannelControlAction])
    case gameCmd(id: String, payload: [String: Any]?)

    func toJSON() -> String {
        var dict: [String: Any] = [:]

        switch self {
        case .gameOpts(let actions):
            dict["code"] = "game_opts"
            dict["actions"] = actions.map { $0.toDict() }
        case .gameCmd(let id, let payload):
            dict["code"] = "game_cmd"
            dict["id"] = id
            if let payload { dict["payload"] = payload }
        }

        let data = try? JSONSerialization.data(withJSONObject: dict)
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }
}

struct ChannelControlAction {
    let channel: String
    let strength: Int
    let durationMs: Int

    func toDict() -> [String: Any] {
        [
            "type": "estim",
            "action": "control_channel",
            "data": [
                "channel": channel,
                "strength": strength,
                "duration_ms": durationMs
            ]
        ]
    }
}
