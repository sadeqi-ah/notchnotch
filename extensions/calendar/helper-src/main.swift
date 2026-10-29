import AppKit
import Foundation
import NotchProtocol

/// The extension owns this protocol; the host transports opaque JSONL messages.
@MainActor
final class CalendarAdapter {
    private struct Request: Decodable {
        let jsonrpc: String
        let id: JSONValue?
        let method: String
        let params: JSONValue?
    }
    private let source = CalendarSource()
    private var input = Data()
    private var pending = 0
    private var connecting = false

    func start() {
        source.onChange = { [weak self] status in
            self?.send(.object(["jsonrpc": .string("2.0"), "method": .string("calendar/state"), "params": Self.json(status)]))
        }
        source.start()
    }

    func read(_ data: Data) {
        if data.isEmpty { source.stop(); exit(0) }
        input.append(data)
        while let newline = input.firstIndex(of: 10) {
            let line = Data(input.prefix(upTo: newline))
            input.removeSubrange(...newline)
            guard line.count <= maximumConnectionPayloadBytes else { source.stop(); exit(1) }
            guard let request = try? JSONDecoder().decode(Request.self, from: line), request.jsonrpc == "2.0" else {
                reject(.null, code: -32600, message: "Invalid JSON-RPC request"); continue
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
                    send(.object(["jsonrpc": .string("2.0"), "id": id, "result": try await handle(request)]))
                } catch RequestError.unknownMethod {
                    reject(id, code: -32601, message: "Unknown method")
                } catch {
                    reject(id, code: -32602, message: error.localizedDescription)
                }
            }
        }
        guard input.count <= maximumConnectionPayloadBytes else { source.stop(); exit(1) }
    }

    private func handle(_ request: Request) async throws -> JSONValue {
        switch request.method {
        case "calendar/getState":
            source.refresh()
            return Self.json(source.status)
        case "calendar/connect":
            guard !connecting else { throw ProtocolError.invalid("Calendar access request is already open") }
            connecting = true
            defer { connecting = false }
            await source.connect()
            return Self.json(source.status)
        case "calendar/select":
            guard case let .object(params) = request.params, case let .array(values) = params["ids"] else {
                throw ProtocolError.invalid("Expected calendar identifiers")
            }
            let ids = values.compactMap { value -> String? in if case let .string(id) = value { id } else { nil } }
            guard ids.count == values.count else { throw ProtocolError.invalid("Expected calendar identifiers") }
            try source.select(ids)
            return Self.json(source.status)
        case "calendar/open":
            try await source.openCalendar()
            return .null
        case "calendar/join":
            guard case let .object(params) = request.params, case let .string(id) = params["id"] else {
                throw ProtocolError.invalid("Expected an event identifier")
            }
            try source.join(id)
            return .null
        default: throw RequestError.unknownMethod
        }
    }

    private enum RequestError: Error { case unknownMethod }

    private static func json(_ status: CalendarStatus) -> JSONValue {
        var bounded = status
        while let data = try? JSONEncoder().encode(bounded) {
            if data.count <= maximumConnectionPayloadBytes - 1024 {
                return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
            }
            if bounded.events.count > 1 { bounded.events.removeLast() }
            else if !bounded.calendars.isEmpty { bounded.calendars.removeLast() }
            else { return .null }
        }
        return .null
    }

    private func reject(_ id: JSONValue, code: Int, message: String) {
        send(.object(["jsonrpc": .string("2.0"), "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(String(message.prefix(1024)))])]))
    }

    private func send(_ value: JSONValue) {
        guard let data = try? JSONEncoder().encode(value), data.count <= maximumConnectionPayloadBytes else { return }
        do { try FileHandle.standardOutput.write(contentsOf: data + Data([10])) }
        catch { source.stop(); exit(1) }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let adapter = CalendarAdapter()
adapter.start()
FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    Task { @MainActor in adapter.read(data) }
}
RunLoop.main.run()
