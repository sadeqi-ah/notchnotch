import Foundation
import NotchProtocol

/// Extension-owned protocol. The host only transports these opaque JSON values.
@MainActor
final class MusicAdapter {
    private struct Request: Decodable {
        let jsonrpc: String
        let id: JSONValue?
        let method: String
        let params: JSONValue?
    }
    private struct Status: Encodable {
        var state: NowPlayingState?
        let authorized: [String]
        let errors: [String: String]
        let commandError: String?
    }
    private let provider = MusicProvider()
    private var input = Data()
    private var pending = 0

    func start() {
        provider.onChange = { [weak self] _ in
            guard let self else { return }
            self.send(.object(["jsonrpc": .string("2.0"), "method": .string("music/state"), "params": self.status()]))
        }
        provider.start()
    }

    func read(_ data: Data) {
        if data.isEmpty { provider.stop(); exit(0) }
        input.append(data)
        while let newline = input.firstIndex(of: 10) {
            let line = Data(input.prefix(upTo: newline))
            input.removeSubrange(...newline)
            guard line.count <= maximumConnectionPayloadBytes else { provider.stop(); exit(1) }
            guard let request = try? JSONDecoder().decode(Request.self, from: line), request.jsonrpc == "2.0" else {
                reject(.null, code: -32600, message: "Invalid JSON-RPC request")
                continue
            }
            guard let id = request.id else { continue }
            switch id {
            case .string, .number: break
            default: reject(.null, code: -32600, message: "Invalid request id"); continue
            }
            guard pending < 32 else { reject(id, code: -32000, message: "Too many pending requests"); continue }
            pending += 1
            Task { [self] in
                defer { pending -= 1 }
                do {
                    let result = try await handle(request)
                    send(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
                } catch HandledRequest.unknownMethod {
                    reject(id, code: -32601, message: "Unknown method: \(request.method)")
                } catch {
                    reject(id, code: -32602, message: error.localizedDescription)
                }
            }
        }
        guard input.count <= maximumConnectionPayloadBytes else { provider.stop(); exit(1) }
    }

    private func handle(_ request: Request) async throws -> JSONValue {
        switch request.method {
        case "music/getState": return status()
        case "music/connect":
            guard case let .object(params) = request.params,
                  case let .string(id) = params["player"], let player = MediaPlayer(rawValue: id) else {
                throw ProtocolError.invalid("Unknown music player")
            }
            await provider.connect(player)
            return status()
        case "music/command":
            guard let params = request.params else { throw ProtocolError.invalid("Missing command") }
            let command = try JSONDecoder().decode(MediaRequest.self, from: JSONEncoder().encode(params))
            try command.validate()
            guard provider.state != nil else { throw ProtocolError.invalid("No current track") }
            provider.perform(command)
            return .null
        default:
            throw HandledRequest.unknownMethod
        }
    }

    private enum HandledRequest: Error { case unknownMethod }

    private func status() -> JSONValue {
        var result = Status(state: provider.state, authorized: provider.authorized.map(\.rawValue).sorted(),
            errors: Dictionary(uniqueKeysWithValues: provider.errors.map { ($0.key.rawValue, String($0.value.prefix(1024))) }),
            commandError: provider.lastCommandError.map { String($0.prefix(1024)) })
        // Leave room for JSON-RPC fields inside the generic 64 KiB stream limit.
        var data = try? JSONEncoder().encode(result)
        if (data?.count ?? 0) > maximumConnectionPayloadBytes - 1024 {
            result.state?.artwork = nil
            data = try? JSONEncoder().encode(result)
        }
        return data.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
    }

    private func reject(_ id: JSONValue, code: Int, message: String) {
        send(.object(["jsonrpc": .string("2.0"), "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(String(message.prefix(1024)))])]))
    }

    private func send(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value), data.count <= maximumConnectionPayloadBytes else { return }
        do { try FileHandle.standardOutput.write(contentsOf: data + Data([10])) }
        catch { provider.stop(); exit(1) }
    }
}

let adapter = MusicAdapter()
adapter.start()
FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    Task { @MainActor in adapter.read(data) }
}
RunLoop.main.run()
