import Foundation
import Network
import Testing
import NotchProtocol
@testable import NotchConnections

private final class HTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.notchnotch.http-fixture")
    private let websocket: Bool

    init(websocket: Bool = false) throws {
        self.websocket = websocket
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        if websocket {
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        }
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [queue, websocket] connection in
            connection.start(queue: queue)
            if websocket {
                connection.receiveMessage { data, _, _, _ in
                    let context = NWConnection.ContentContext(identifier: "echo", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
                    connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in connection.cancel() })
                }
                return
            }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let response: String
                if request.contains(" /redirect ") {
                    response = "HTTP/1.1 302 Found\r\nLocation: https://example.com/private\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                } else if request.contains(" /large ") {
                    response = "HTTP/1.1 200 OK\r\nContent-Length: 65537\r\nConnection: close\r\n\r\n"
                } else {
                    let body = "{\"route\":\"direct\"}"
                    response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                }
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: listener.stateUpdateHandler = nil; continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error): listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }
}

@Test @MainActor func actualLocalWebSocketExchangesJSONOverADeclaredEndpoint() async throws {
    let server = try HTTPFixture(websocket: true)
    let port = try await server.start()
    defer { server.stop() }
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
    {"id":"dev.test.websocket","name":"WebSocket test","version":"1","apiVersion":1,"entry":"bundle.js","permissions":["local-network"],
     "connections":{"events":{"transport":"websocket","endpoint":"ws://127.0.0.1:\(port)/events"}}}
    """.utf8))
    var messages: [ConnectionEvent] = []
    var opened = false
    let broker = ConnectionBroker(manifest: manifest, directory: URL(fileURLWithPath: "/tmp"), authorize: { _, _ in true }, emit: { json in
        let data = Data(json.utf8)
        if let event = try? JSONDecoder().decode(ConnectionEvent.self, from: data) { messages.append(event) }
        if let response = try? JSONDecoder().decode(ConnectionResponse.self, from: data), response.requestID == "open", response.error == nil { opened = true }
    })
    defer { broker.stop() }
    broker.receive(.init(extensionID: manifest.id, requestID: "open", connectionID: "events", operation: .open, sessionID: "socket-one"))
    for _ in 0..<100 where !opened { try await Task.sleep(for: .milliseconds(10)) }
    broker.receive(.init(extensionID: manifest.id, requestID: "send", connectionID: "events", operation: .send, sessionID: "socket-one",
                         message: .object(["route": .string("proxy:work")])))
    for _ in 0..<300 where !messages.contains(where: { $0.event == "message" }) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(messages.contains { $0.sessionID == "socket-one" && $0.message == .object(["route": .string("proxy:work")]) })
}

@Test @MainActor func actualLocalHTTPRoundTripsDecisionsRejectsRedirectsAndBoundsResponses() async throws {
    let server = try HTTPFixture()
    let port = try await server.start()
    defer { server.stop() }
    let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
    {"id":"dev.test.http","name":"HTTP test","version":"1","apiVersion":1,"entry":"bundle.js","permissions":["local-network"],
     "connections":{"service":{"transport":"http","endpoint":"http://127.0.0.1:\(port)"}}}
    """.utf8))
    var responses: [ConnectionResponse] = []
    let broker = ConnectionBroker(manifest: manifest, directory: URL(fileURLWithPath: "/tmp"), authorize: { _, _ in true }, emit: { json in
        if let response = try? JSONDecoder().decode(ConnectionResponse.self, from: Data(json.utf8)) { responses.append(response) }
    })
    defer { broker.stop() }
    for (id, path) in [("decision", "/decision"), ("redirect", "/redirect"), ("large", "/large")] {
        broker.receive(.init(extensionID: manifest.id, requestID: id, connectionID: "service", operation: .request,
                             request: .init(path: path, method: "POST", body: "{\"route\":\"direct\"}")))
    }
    for _ in 0..<300 where responses.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
    let decision = responses.first { $0.requestID == "decision" }
    guard case .object(let result) = decision?.result else { Issue.record("Expected an HTTP response"); return }
    #expect(result["status"] == .number(200))
    #expect(result["body"] == .string("{\"route\":\"direct\"}"))
    guard case .object(let redirect) = responses.first(where: { $0.requestID == "redirect" })?.result else {
        Issue.record("Expected the redirect itself rather than following it"); return
    }
    #expect(redirect["status"] == .number(302))
    #expect(responses.first(where: { $0.requestID == "large" })?.error != nil)
}
