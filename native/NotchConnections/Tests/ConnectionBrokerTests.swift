import Foundation
import Testing
import NotchProtocol
@testable import NotchConnections

private func manifest(permissions: [String] = ["process"], connections: String = #"{"echo":{"transport":"stdio","executable":"/usr/bin/tee","arguments":[]}}"#) throws -> ExtensionManifest {
    let permissionsJSON = String(decoding: try JSONEncoder().encode(permissions), as: UTF8.self)
    return try JSONDecoder().decode(ExtensionManifest.self, from: Data("""
    {"id":"dev.test.bridge","name":"Bridge test","version":"1","apiVersion":1,"entry":"bundle.js","permissions":\(permissionsJSON),"connections":\(connections)}
    """.utf8))
}

@Test func localOriginsAndRequestsCannotEscapeTheirDeclaredDestination() throws {
    let definition = ConnectionDefinition(transport: .http, endpoint: "http://127.0.0.1:4242")
    try definition.validate(permissions: ["local-network"])
    let url = try ConnectionHTTPRequest(path: "/connections?waiting=true").url(for: definition)
    #expect(url.absoluteString == "http://127.0.0.1:4242/connections?waiting=true")
    for endpoint in ["https://example.com:443", "http://localhost:4242", "http://127.0.0.1.example.com:4242",
                     "http://127.0.0.1:4242/path", "http://user:secret@127.0.0.1:4242", "file:///tmp/socket"] {
        #expect(throws: ProtocolError.self) {
            try ConnectionDefinition(transport: .http, endpoint: endpoint).validate(permissions: ["local-network"])
        }
    }
    for path in ["https://example.com/", "//example.com/path", "/\\example.com/path", "/path#fragment"] {
        #expect(throws: ProtocolError.self) { try ConnectionHTTPRequest(path: path).url(for: definition) }
    }
    #expect(throws: ProtocolError.self) {
        try ConnectionHTTPRequest(path: "/", headers: ["Host": "example.com"]).url(for: definition)
    }
    #expect(throws: ProtocolError.self) { try definition.validate(permissions: []) }
}

@Test func processDeclarationsRequirePermissionAndCannotTraverseOutOfBundle() throws {
    try manifest().validate()
    #expect(throws: ProtocolError.self) { try manifest(permissions: []).validate() }
    #expect(throws: ProtocolError.self) {
        try ConnectionDefinition(transport: .stdio, executable: "./helpers/../../secret").validate(permissions: ["process"])
    }
    #expect(throws: ProtocolError.self) {
        try ConnectionDefinition(transport: .stdio, executable: "bin/tool").validate(permissions: ["process"])
    }
}

@Test @MainActor func stdioRoundTripRequiresConsentAndRetainsSessionIdentity() async throws {
    var messages: [[String: Any]] = []
    var authorizations = 0
    let broker = ConnectionBroker(manifest: try manifest(), directory: URL(fileURLWithPath: "/tmp"), authorize: { _, target in
        authorizations += 1
        return target.contains("/usr/bin/tee")
    }, emit: { json in
        if let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] { messages.append(value) }
    })
    defer { broker.stop() }
    broker.receive(.init(extensionID: "dev.test.bridge", requestID: "open", connectionID: "echo", operation: .open, sessionID: "one"))
    for _ in 0..<100 where !messages.contains(where: { $0["requestID"] as? String == "open" }) { try await Task.sleep(for: .milliseconds(10)) }
    #expect(messages.contains { $0["requestID"] as? String == "open" && $0["error"] == nil })
    broker.receive(.init(extensionID: "dev.test.bridge", requestID: "send", connectionID: "echo", operation: .send,
                         sessionID: "one", message: .object(["decision": .string("direct")])) )
    for _ in 0..<100 where !messages.contains(where: { $0["type"] as? String == "connectionEvent" }) { try await Task.sleep(for: .milliseconds(10)) }
    let event = messages.first { $0["type"] as? String == "connectionEvent" }
    #expect(event?["sessionID"] as? String == "one")
    #expect((event?["message"] as? [String: String])?["decision"] == "direct")
    #expect(authorizations == 1)
    broker.stop()
    #expect(messages.contains { $0["event"] as? String == "closed" })
}

@Test @MainActor func undeclaredDeniedAndCrossExtensionRequestsCannotStartAProcess() async throws {
    var responses: [ConnectionResponse] = []
    var authorizations = 0
    let broker = ConnectionBroker(manifest: try manifest(), directory: URL(fileURLWithPath: "/tmp"), authorize: { _, _ in
        authorizations += 1; return false
    }, emit: { json in
        if let value = try? JSONDecoder().decode(ConnectionResponse.self, from: Data(json.utf8)) { responses.append(value) }
    })
    defer { broker.stop() }
    broker.receive(.init(extensionID: "another.extension", requestID: "foreign", connectionID: "echo", operation: .open, sessionID: "a"))
    broker.receive(.init(extensionID: "dev.test.bridge", requestID: "unknown", connectionID: "undeclared", operation: .open, sessionID: "b"))
    broker.receive(.init(extensionID: "dev.test.bridge", requestID: "denied", connectionID: "echo", operation: .open, sessionID: "c"))
    for _ in 0..<100 where responses.count < 3 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(responses.count == 3)
    #expect(responses.allSatisfy { $0.error != nil })
    #expect(authorizations == 1)
}
