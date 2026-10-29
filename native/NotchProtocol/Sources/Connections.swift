import Foundation

public let maximumConnectionPayloadBytes = 65_536

public indirect enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        }
    }
}

public struct ConnectionDefinition: Codable, Equatable, Sendable {
    public enum Transport: String, Codable, Sendable { case http, websocket, stdio }
    public var transport: Transport
    public var endpoint: String?
    public var executable: String?
    public var arguments: [String]?

    public init(transport: Transport, endpoint: String? = nil, executable: String? = nil, arguments: [String]? = nil) {
        self.transport = transport; self.endpoint = endpoint; self.executable = executable; self.arguments = arguments
    }

    public func validate(permissions: [String]) throws {
        switch transport {
        case .http, .websocket:
            guard permissions.contains("local-network"), executable == nil, arguments == nil,
                  let endpoint, let url = URL(string: endpoint),
                  endpoint.range(of: transport == .http
                    ? #"^https?://(127\.0\.0\.1|\[::1\]):[0-9]+/?$"#
                    : #"^wss?://(127\.0\.0\.1|\[::1\]):[0-9]+(/[^?#]*)?$"#, options: .regularExpression) != nil,
                  Self.isLoopback(url), let port = url.port, (1...65535).contains(port),
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  transport == .websocket || url.path.isEmpty || url.path == "/",
                  transport == .http ? ["http", "https"].contains(url.scheme ?? "") : ["ws", "wss"].contains(url.scheme ?? "") else {
                throw ProtocolError.invalid("Local connections require an explicit loopback origin and local-network permission")
            }
        case .stdio:
            guard permissions.contains("process"), endpoint == nil, let executable,
                  !executable.isEmpty, executable.utf8.count <= 1024, !executable.contains("\0"),
                  executable.hasPrefix("/") || !executable.contains("/") || Self.isBundledPath(executable),
                  (arguments?.count ?? 0) <= 32,
                  (arguments ?? []).allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }) else {
                throw ProtocolError.invalid("Stdio connections require a fixed executable, bounded arguments, and process permission")
            }
        }
    }

    public static func isLoopback(_ url: URL) -> Bool {
        // Literal addresses avoid DNS rebinding and proxying localhost to a remote host.
        ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? "")
    }
    private static func isBundledPath(_ path: String) -> Bool {
        path.hasPrefix("./") && !path.split(separator: "/").contains("..")
    }
}

public struct ConnectionHTTPRequest: Codable, Sendable {
    public var path: String
    public var method: String
    public var headers: [String: String]?
    public var body: String?
    public var timeoutMs: Int?

    public init(path: String, method: String = "GET", headers: [String: String]? = nil, body: String? = nil, timeoutMs: Int? = nil) {
        self.path = path; self.method = method; self.headers = headers; self.body = body; self.timeoutMs = timeoutMs
    }

    public func url(for definition: ConnectionDefinition) throws -> URL {
        guard definition.transport == .http, let endpoint = definition.endpoint, let origin = URL(string: endpoint),
              path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"),
              let result = URL(string: path, relativeTo: origin)?.absoluteURL,
              result.scheme == origin.scheme, result.host == origin.host, result.port == origin.port,
              result.user == nil, result.password == nil, result.fragment == nil,
              ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(method),
              (body?.utf8.count ?? 0) <= maximumConnectionPayloadBytes,
              (1...30_000).contains(timeoutMs ?? 15_000),
              (headers?.count ?? 0) <= 32,
              (headers ?? [:]).allSatisfy({ name, value in
                  !name.isEmpty && name.utf8.count <= 128 && value.utf8.count <= 4096 &&
                  !["host", "connection", "content-length", "transfer-encoding", "proxy-authorization"].contains(name.lowercased()) &&
                  name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || "!#$%&'*+-.^_`|~".utf8.contains($0) }) &&
                  !value.contains("\r") && !value.contains("\n")
              }) else { throw ProtocolError.invalid("Invalid local HTTP request") }
        return result
    }
}

public struct ConnectionCommand: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case request, open, send, close }
    public var protocolVersion = 1
    public var type = "connectionCommand"
    public var extensionID: String
    public var requestID: String
    public var connectionID: String
    public var operation: Operation
    public var sessionID: String?
    public var request: ConnectionHTTPRequest?
    public var message: JSONValue?

    private enum CodingKeys: String, CodingKey { case protocolVersion, type, extensionID, requestID, connectionID, operation, sessionID, request, message }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        type = try values.decode(String.self, forKey: .type)
        extensionID = try values.decode(String.self, forKey: .extensionID)
        requestID = try values.decode(String.self, forKey: .requestID)
        connectionID = try values.decode(String.self, forKey: .connectionID)
        operation = try values.decode(Operation.self, forKey: .operation)
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID)
        request = try values.decodeIfPresent(ConnectionHTTPRequest.self, forKey: .request)
        message = values.contains(.message) ? try values.decode(JSONValue.self, forKey: .message) : nil
    }

    public init(extensionID: String, requestID: String, connectionID: String, operation: Operation,
                sessionID: String? = nil, request: ConnectionHTTPRequest? = nil, message: JSONValue? = nil) {
        self.extensionID = extensionID; self.requestID = requestID; self.connectionID = connectionID
        self.operation = operation; self.sessionID = sessionID; self.request = request; self.message = message
    }

    public func validate(expectedExtensionID: String) throws {
        guard protocolVersion == 1, type == "connectionCommand", extensionID == expectedExtensionID,
              !requestID.isEmpty, requestID.count <= 128, !connectionID.isEmpty, connectionID.count <= 64,
              (sessionID?.count ?? 0) <= 128 else {
            throw ProtocolError.invalid("Invalid connection command")
        }
        if let message, try JSONEncoder().encode(message).count > maximumConnectionPayloadBytes {
            throw ProtocolError.invalid("Connection message exceeds 64 KiB")
        }
    }
}

public struct ConnectionResponse: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "connectionResponse"
    public let requestID: String
    public let result: JSONValue?
    public let error: String?
    public init(requestID: String, result: JSONValue? = nil, error: String? = nil) {
        self.requestID = requestID; self.result = result; self.error = error
    }
}

public struct ConnectionEvent: Codable, Sendable {
    public var protocolVersion = 1
    public var type = "connectionEvent"
    public let connectionID: String
    public let sessionID: String
    public let event: String
    public let message: JSONValue?
    public let error: String?
    public init(connectionID: String, sessionID: String, event: String, message: JSONValue? = nil, error: String? = nil) {
        self.connectionID = connectionID; self.sessionID = sessionID; self.event = event; self.message = message; self.error = error
    }
}
