import Foundation
import NotchProtocol

private final class LocalSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Transports are generic. Application-specific protocols stay in extension code.
@MainActor
public final class ConnectionBroker {
    @MainActor private final class Stream {
        let sessionID: String
        var process: StdioConnection?
        var websocket: URLSessionWebSocketTask?
        var reader: Task<Void, Never>?
        var intervalStart = Date.now
        var messageCount = 0
        init(sessionID: String) { self.sessionID = sessionID }
        func stop() { reader?.cancel(); websocket?.cancel(with: .goingAway, reason: nil); process?.stop() }
    }

    private let manifest: ExtensionManifest
    private let directory: URL
    private let authorize: (String, String) -> Bool
    private let emit: (String) -> Void
    private let session: URLSession
    private let websocketSession: URLSession
    private var decisions: [String: Bool] = [:]
    private var streams: [String: Stream] = [:]
    private var closedSessions: [String: String] = [:]
    private var operations: [String: Task<Void, Never>] = [:]
    private var stopped = false

    public init(manifest: ExtensionManifest, directory: URL,
                authorize: @escaping (String, String) -> Bool, emit: @escaping (String) -> Void) {
        self.manifest = manifest; self.directory = directory.resolvingSymlinksInPath()
        self.authorize = authorize; self.emit = emit
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: LocalSessionDelegate(), delegateQueue: nil)
        configuration.timeoutIntervalForResource = 604_800
        websocketSession = URLSession(configuration: configuration, delegate: LocalSessionDelegate(), delegateQueue: nil)
    }

    public func receive(_ command: ConnectionCommand) {
        guard !stopped else { return }
        do {
            try command.validate(expectedExtensionID: manifest.id)
            guard operations[command.requestID] == nil, operations.count < 32 else {
                throw ProtocolError.invalid("Too many pending or duplicate connection operations")
            }
            operations[command.requestID] = Task { [weak self] in
                guard let self else { return }
                defer { self.operations.removeValue(forKey: command.requestID) }
                do {
                    let result = try await self.perform(command)
                    if !Task.isCancelled { self.send(ConnectionResponse(requestID: command.requestID, result: result)) }
                } catch {
                    if !Task.isCancelled {
                        self.send(ConnectionResponse(requestID: command.requestID, error: String(error.localizedDescription.prefix(2048))))
                    }
                }
            }
        } catch { send(ConnectionResponse(requestID: command.requestID, error: error.localizedDescription)) }
    }

    public func stop() {
        guard !stopped else { return }
        for id in operations.keys { send(ConnectionResponse(requestID: id, error: "Extension connections disconnected")) }
        for (id, stream) in streams {
            send(ConnectionEvent(connectionID: id, sessionID: stream.sessionID, event: "closed", error: "Extension connections disconnected"))
        }
        stopped = true
        for operation in operations.values { operation.cancel() }
        operations.removeAll()
        for stream in streams.values { stream.stop() }
        streams.removeAll(); decisions.removeAll()
        session.invalidateAndCancel()
        websocketSession.invalidateAndCancel()
    }

    private func perform(_ command: ConnectionCommand) async throws -> JSONValue {
        try manifest.validate()
        guard let definition = manifest.connections?[command.connectionID] else {
            throw ProtocolError.invalid("Connection is not declared in this extension's manifest")
        }
        try definition.validate(permissions: manifest.permissions)
        if command.operation == .close {
            closedSessions[command.connectionID] = command.sessionID
            if let stream = streams[command.connectionID], stream.sessionID == command.sessionID {
                streams.removeValue(forKey: command.connectionID)?.stop()
            }
            return .null
        }
        let executable = definition.transport == .stdio ? try resolveExecutable(definition.executable!) : nil
        if decisions[command.connectionID] == nil {
            let target = executable.map { $0.path + "\nArguments: " + (definition.arguments ?? []).joined(separator: " · ") }
                ?? definition.endpoint!
            decisions[command.connectionID] = authorize(command.connectionID, target)
        }
        guard decisions[command.connectionID] == true, !stopped, !Task.isCancelled else {
            throw ProtocolError.invalid("Connection access was not granted. Reload the extension to ask again.")
        }
        switch command.operation {
        case .request:
            guard let request = command.request else { throw ProtocolError.invalid("HTTP request is missing") }
            return try await requestHTTP(request, definition: definition)
        case .open:
            guard definition.transport != .http, let sessionID = command.sessionID, !sessionID.isEmpty else {
                throw ProtocolError.invalid("Stream requires a session identifier and a WebSocket or stdio transport")
            }
            guard closedSessions[command.connectionID] != sessionID else { throw ProtocolError.invalid("Stream was closed while opening") }
            if let stream = streams[command.connectionID] {
                guard stream.sessionID == sessionID else { throw ProtocolError.invalid("Connection is already open") }
                return .null
            }
            let stream = Stream(sessionID: sessionID)
            streams[command.connectionID] = stream
            do {
                if let executable {
                    let process = StdioConnection()
                    stream.process = process
                    try process.start(executable: executable, arguments: definition.arguments ?? [],
                                      directory: definition.executable!.hasPrefix("./") ? directory : FileManager.default.homeDirectoryForCurrentUser) { [weak self, weak stream] message in
                        guard let self, let stream else { return }
                        self.deliver(message, id: command.connectionID, stream: stream)
                    } onClose: { [weak self, weak stream] error in
                        guard let self, let stream else { return }
                        self.closed(command.connectionID, stream: stream, error: error)
                    }
                } else {
                    let task = websocketSession.webSocketTask(with: URL(string: definition.endpoint!)!)
                    task.maximumMessageSize = maximumConnectionPayloadBytes
                    stream.websocket = task; task.resume()
                    stream.reader = Task { [weak self, weak stream] in
                        do {
                            while !Task.isCancelled {
                                let frame = try await task.receive()
                                let data: Data
                                switch frame {
                                case .string(let text): data = Data(text.utf8)
                                case .data(let bytes): data = bytes
                                @unknown default: throw ProtocolError.invalid("Unsupported WebSocket frame")
                                }
                                guard data.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Connection message exceeds 64 KiB") }
                                let value = try JSONDecoder().decode(JSONValue.self, from: data)
                                guard let self, let stream else { return }
                                self.deliver(value, id: command.connectionID, stream: stream)
                            }
                        } catch {
                            if !Task.isCancelled, let self, let stream { self.closed(command.connectionID, stream: stream, error: error.localizedDescription) }
                        }
                    }
                }
            } catch { streams.removeValue(forKey: command.connectionID)?.stop(); throw error }
            return .null
        case .send:
            guard let stream = streams[command.connectionID], stream.sessionID == command.sessionID,
                  let message = command.message else { throw ProtocolError.invalid("Stream is closed or message is missing") }
            let data = try JSONEncoder().encode(message)
            guard data.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Connection message exceeds 64 KiB") }
            if let process = stream.process { try await process.write(data + Data([10])) }
            else if let websocket = stream.websocket { try await websocket.send(.string(String(decoding: data, as: UTF8.self))) }
            return .null
        case .close: return .null
        }
    }

    private func requestHTTP(_ input: ConnectionHTTPRequest, definition: ConnectionDefinition) async throws -> JSONValue {
        var request = URLRequest(url: try input.url(for: definition))
        request.httpMethod = input.method
        request.timeoutInterval = Double(input.timeoutMs ?? 15_000) / 1000
        request.allHTTPHeaderFields = input.headers
        request.httpBody = input.body.map { Data($0.utf8) }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw ProtocolError.invalid("Invalid HTTP response") }
        if response.expectedContentLength > maximumConnectionPayloadBytes { throw ProtocolError.invalid("HTTP response exceeds 64 KiB") }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumConnectionPayloadBytes else { throw ProtocolError.invalid("HTTP response exceeds 64 KiB") }
            body.append(byte)
        }
        guard let text = String(data: body, encoding: .utf8) else { throw ProtocolError.invalid("HTTP response must be UTF-8 text") }
        let headers = response.allHeaderFields.reduce(into: [String: JSONValue]()) { values, item in
            values[String(describing: item.key)] = .string(String(describing: item.value))
        }
        let result = JSONValue.object(["status": .number(Double(response.statusCode)), "headers": .object(headers), "body": .string(text)])
        guard try JSONEncoder().encode(result).count <= maximumMessageBytes - 1024 else {
            throw ProtocolError.invalid("Encoded HTTP response exceeds the message limit")
        }
        return result
    }

    private func resolveExecutable(_ name: String) throws -> URL {
        let manager = FileManager.default
        let candidate: URL
        if name.hasPrefix("./") {
            candidate = directory.appendingPathComponent(String(name.dropFirst(2))).resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(directory.path + "/") else { throw ProtocolError.invalid("Bundled helper escapes the extension directory") }
        } else if name.hasPrefix("/") { candidate = URL(fileURLWithPath: name).resolvingSymlinksInPath() }
        else {
            let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", manager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
            guard let found = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent(name) }).first(where: { manager.isExecutableFile(atPath: $0.path) }) else {
                throw ProtocolError.invalid("Install \(name) or declare its absolute executable path in the manifest")
            }
            candidate = found.resolvingSymlinksInPath()
        }
        guard manager.isExecutableFile(atPath: candidate.path) else { throw ProtocolError.invalid("Connection executable is not runnable") }
        return candidate
    }

    private func deliver(_ message: JSONValue, id: String, stream: Stream) {
        guard streams[id] === stream else { return }
        if Date.now.timeIntervalSince(stream.intervalStart) >= 1 { stream.intervalStart = .now; stream.messageCount = 0 }
        stream.messageCount += 1
        guard stream.messageCount <= 256 else { closed(id, stream: stream, error: "Connection exceeded 256 messages per second"); return }
        send(ConnectionEvent(connectionID: id, sessionID: stream.sessionID, event: "message", message: message))
    }

    private func closed(_ id: String, stream: Stream, error: String?) {
        guard streams[id] === stream else { return }
        streams.removeValue(forKey: id)?.stop()
        send(ConnectionEvent(connectionID: id, sessionID: stream.sessionID, event: "closed", error: error.map { String($0.prefix(2048)) }))
    }

    private func send(_ value: some Encodable) {
        guard !stopped, let data = try? JSONEncoder().encode(value) else { return }
        guard data.count <= maximumMessageBytes else { return }
        emit(String(decoding: data, as: UTF8.self))
    }
}
