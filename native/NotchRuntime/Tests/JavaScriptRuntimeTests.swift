import Foundation
import Testing
import NotchProtocol
@testable import NotchRuntime

@Test @MainActor func javascriptCanSendAndReceiveWithoutNodeGlobals() throws {
    var messages: [String] = []
    let runtime = try JavaScriptRuntime(extensionID: "test.extension") { messages.append($0) }
    defer { runtime.stop() }
    try runtime.evaluate(#"""
    if (typeof process !== 'undefined' || typeof require !== 'undefined') throw Error('Unexpected Node globals');
    globalThis.__notchnotchDispatch = (json) => __notchnotchSend(JSON.parse(json).value);
    """#)
    let event = UserEvent(action: "field", value: "A session")
    runtime.receive(String(decoding: try JSONEncoder().encode(event), as: UTF8.self))
    #expect(messages == ["A session"])
    runtime.receive(#"{"protocolVersion":2,"type":"event","action":"field","value":"invalid"}"#)
    #expect(messages.count == 1)
}

@Test @MainActor func javascriptExceptionIsReported() throws {
    var messages: [String] = []
    let runtime = try JavaScriptRuntime(extensionID: "test.extension") { messages.append($0) }
    defer { runtime.stop() }
    #expect(throws: ProtocolError.self) { try runtime.evaluate("throw new Error('broken extension')") }
    #expect(messages.contains { $0.contains("broken extension") })
}

@Test @MainActor func mediaStateIsValidatedAndLargeArtworkCanCrossTheBridge() throws {
    var messages: [String] = []
    let runtime = try JavaScriptRuntime(extensionID: "test.music") { messages.append($0) }
    defer { runtime.stop() }
    try runtime.evaluate("globalThis.__notchnotchDispatch = (json) => __notchnotchSend(JSON.parse(json).state?.title ?? 'empty')")
    var state = NowPlayingState(id: "track", eventID: "event", player: .spotify, title: "Music", artist: "Artist",
                                artwork: "data:image/jpeg;base64," + String(repeating: "a", count: 24_000),
                                duration: 204, position: 12, isPlaying: true)
    func receive(_ state: NowPlayingState?) throws {
        runtime.receive(String(decoding: try JSONEncoder().encode(MediaUpdate(state: state)), as: UTF8.self))
    }
    try receive(state)
    #expect(messages == ["Music"])
    state.artwork = "file:///private/data"
    try receive(state)
    #expect(messages.count == 1)
    try receive(nil)
    #expect(messages.last == "empty")
}
