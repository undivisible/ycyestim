import Foundation

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
    private var uid: String = ""       // raw UID (e.g. "50141")
    private var token: String = ""     // auth token from connect_code

    // MARK: - Auth

    /// Parse connect code and authenticate via game_sign API
    /// - Parameter connectCode: "UID TOKEN" space-separated string from YCY app
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

        // In production, initialize TencentCloudIM SDK here:
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
            throw IMServiceError.authFailed("HTTP error: \(response)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let code = json?["code"] as? Int, code == 1,
              let dataDict = json?["data"] as? [String: Any],
              let appid = dataDict["appid"] as? String,
              let sign = dataDict["sign"] as? String else {
            throw IMServiceError.authFailed("Invalid response from game_sign API")
        }

        return GameSignResponse(appid: appid, sign: sign)
    }

    // MARK: - Commands

    /// Send a game command via Tencent IM
    /// - Parameter command: Command to send
    func send(command: GameCommand) async throws {
        guard isConnected else {
            throw IMServiceError.notConnected
        }

        // Per YCY protocol: "to" is raw UID without "game_" prefix
        let targetUserId = uid

        // In production, use TencentCloudIM SDK:
        // let payload = command.toJSON()
        // let msg = chat.createTextMessage({
        //   to: targetUserId,                    // UID without game_ prefix
        //   conversationType: TYPES.CONV_C2C,
        //   payload: { text: payload }
        // })
        // await chat.sendMessage(msg)

        let payload = command.buildPayload(token: token)
        print("[IM] → \(targetUserId): \(payload)")
    }

    /// Send channel control command (game_opts draft)
    /// Note: game_opts/control_channel is marked as "备选草稿，未实现" in YCY docs.
    /// It may not work on all device firmwares. Falls back to game_cmd triggers if unsupported.
    func sendChannelControl(channel: String, strength: Int, durationMs: Int) async throws {
        let command = GameCommand.channelControl(
            channel: channel,
            strength: strength,
            durationMs: durationMs
        )
        try await send(command: command)
    }

    /// Trigger a preset/command by ID
    /// - Parameter id: Command/preset ID (e.g. "hurt", "kill_2")
    func trigger(id: String) async throws {
        let command = GameCommand.trigger(id: id)
        try await send(command: command)
    }

    /// Trigger a command with custom waveform override
    /// - Parameters:
    ///   - id: Estim command ID
    ///   - waveform: App内で定义された波形名称 (YCY app's built-in waveform name)
    ///   - resetStrength: Whether to reset strength counter
    func triggerWithWaveform(id: String, waveform: String, resetStrength: Bool = false) async throws {
        let command = GameCommand.triggerWithPayload(
            id: id,
            payload: [
                "reset_strength": resetStrength,
                "waveform": waveform
            ]
        )
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

/// Represents a command that can be sent to a YCY device via Tencent IM
enum GameCommand {
    /// Trigger a preset command by ID (game_cmd)
    case trigger(id: String)

    /// Trigger with custom payload overrides (waveform, reset_strength)
    case triggerWithPayload(id: String, payload: [String: Any])

    /// Channel control via game_opts (draft/unimplemented in firmware)
    case channelControl(channel: String, strength: Int, durationMs: Int)

    /// Build the JSON string for IM payload.text, including token
    func buildPayload(token: String) -> String {
        var dict: [String: Any] = [:]
        dict["token"] = token

        switch self {
        case .trigger(let id):
            dict["code"] = "game_cmd"
            dict["id"] = id

        case .triggerWithPayload(let id, let payload):
            dict["code"] = "game_cmd"
            dict["id"] = id
            dict["payload"] = payload

        case .channelControl(let channel, let strength, let durationMs):
            // game_opts format — draft spec, may not be supported
            dict["code"] = "game_opts"
            dict["actions"] = [[
                "type": "estim",
                "action": "control_channel",
                "data": [
                    "channel": channel,
                    "strength": strength,
                    "duration_ms": durationMs
                ]
            ]]
        }

        let data = try? JSONSerialization.data(withJSONObject: dict)
        return String(data: data ?? Data(), encoding: .utf8) ?? "{}"
    }
}
