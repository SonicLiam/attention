import Foundation

// MARK: - WebSocket Message Types

struct SyncChange: Codable, Sendable {
    let entityType: String
    let entityId: String
    let action: String
    let data: [String: AnyCodableValue]?
    let version: Int
}

struct SyncLogEntry: Codable, Sendable {
    let id: Int
    let entityType: String
    let entityId: String
    let action: String
    let version: Int
    let payload: [String: AnyCodableValue]?
    let createdAt: String?
}

struct PushMessage: Codable, Sendable {
    let type: String
    let changes: [SyncChange]
}

struct PullMessage: Codable, Sendable {
    let type: String
    let lastSyncId: Int
}

struct PushAckMessage: Codable, Sendable {
    let type: String
    let syncedIds: [Int]?
    let latestSyncId: Int?
}

struct PullResponseMessage: Codable, Sendable {
    let type: String
    let changes: [SyncLogEntry]?
    let latestSyncId: Int?
}

struct ChangesMessage: Codable, Sendable {
    let type: String
    let changes: [SyncLogEntry]?
}

struct WSErrorMessage: Codable, Sendable {
    let type: String
    let message: String?
}

// MARK: - AnyCodableValue for flexible JSON

enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .null: try container.encodeNil()
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }
}

// MARK: - Connection State

enum WebSocketConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case authenticating
    case authenticated
    case reconnecting(attempt: Int)
}

// MARK: - WebSocket Client

@MainActor
@Observable
final class WebSocketClient {
    var connectionState: WebSocketConnectionState = .disconnected

    var isConnected: Bool {
        if case .authenticated = connectionState { return true }
        return false
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let baseURL: String
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var deviceId: String

    // Callbacks
    var onPushAck: (@Sendable (PushAckMessage) -> Void)?
    var onPullResponse: (@Sendable (PullResponseMessage) -> Void)?
    var onRemoteChanges: (@Sendable (ChangesMessage) -> Void)?
    var onAuthFailure: (@Sendable () -> Void)?

    init(baseURL: String = "ws://118.196.142.21") {
        self.baseURL = baseURL
        let storedDeviceId = UserDefaults.standard.string(forKey: "attention_device_id")
        if let storedDeviceId {
            self.deviceId = storedDeviceId
        } else {
            #if os(macOS)
            let platform = "macos"
            #elseif os(watchOS)
            let platform = "watchos"
            #else
            let platform = "ios"
            #endif
            let newId = "\(platform)-\(UUID().uuidString)"
            UserDefaults.standard.set(newId, forKey: "attention_device_id")
            self.deviceId = newId
        }
    }

    // MARK: - Connect

    func connect(token: String) {
        disconnect()
        connectionState = .connecting

        guard let url = URL(string: "\(baseURL)/ws/sync?token=\(token)&deviceId=\(deviceId)") else {
            connectionState = .disconnected
            return
        }

        let wsTask = session.webSocketTask(with: url)
        self.webSocketTask = wsTask
        wsTask.resume()

        connectionState = .authenticating
        startReceiving()
        startPingTimer()
        reconnectAttempt = 0
    }

    // MARK: - Disconnect

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    // MARK: - Send Messages

    func pushChanges(_ changes: [SyncChange]) {
        let message = PushMessage(type: "push", changes: changes)
        sendMessage(message)
    }

    func pullChanges(lastSyncId: Int) {
        let message = PullMessage(type: "pull", lastSyncId: lastSyncId)
        sendMessage(message)
    }

    private func sendMessage<T: Codable & Sendable>(_ message: T) {
        guard let wsTask = webSocketTask else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(message),
              let string = String(data: data, encoding: .utf8) else { return }

        wsTask.send(.string(string)) { [weak self] error in
            if error != nil {
                Task { @MainActor [weak self] in
                    self?.handleDisconnect()
                }
            }
        }
    }

    // MARK: - Receive Messages

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let wsTask = await self.getWebSocketTask() else { break }
                do {
                    let message = try await wsTask.receive()
                    await self.handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        await self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private nonisolated func getWebSocketTask() async -> URLSessionWebSocketTask? {
        await MainActor.run { self.webSocketTask }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()

        // Try to parse the type first
        struct TypeMessage: Codable { let type: String }
        guard let typeMsg = try? decoder.decode(TypeMessage.self, from: data) else { return }

        switch typeMsg.type {
        case "auth_success":
            connectionState = .authenticated
            reconnectAttempt = 0

        case "push_ack":
            if let msg = try? decoder.decode(PushAckMessage.self, from: data) {
                onPushAck?(msg)
            }

        case "pull_response":
            if let msg = try? decoder.decode(PullResponseMessage.self, from: data) {
                onPullResponse?(msg)
            }

        case "changes":
            if let msg = try? decoder.decode(ChangesMessage.self, from: data) {
                onRemoteChanges?(msg)
            }

        case "error":
            if let msg = try? decoder.decode(WSErrorMessage.self, from: data),
               msg.message?.contains("Authentication") == true {
                onAuthFailure?()
            }

        case "pong":
            break // Heartbeat response, no action needed

        default:
            break
        }
    }

    // MARK: - Ping/Pong Heartbeat

    private func startPingTimer() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                let msg: [String: String] = ["type": "ping"]
                if let data = try? JSONEncoder().encode(msg),
                   let string = String(data: data, encoding: .utf8) {
                    await self.sendPing(string)
                }
            }
        }
    }

    private func sendPing(_ string: String) {
        webSocketTask?.send(.string(string)) { _ in }
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        guard case .disconnected = connectionState else {
            // Only reconnect if we were previously connected
            if case .reconnecting = connectionState { return }
            scheduleReconnect()
            return
        }
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)
        connectionState = .reconnecting(attempt: reconnectAttempt)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard let token = await APIClient.shared.accessToken else {
                self.connectionState = .disconnected
                return
            }
            self.connect(token: token)
        }
    }
}
