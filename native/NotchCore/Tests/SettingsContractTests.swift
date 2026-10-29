import Testing
import NotchProtocol
import NotchCore

@Test func settingsOnlyExtensionsNeverCreateANotchActivity() throws {
    let settings = UINode(id: "setup", type: .column, children: [
        .init(id: "connect", type: .button, props: .init(text: "Connect", action: "connect:action")),
    ])
    let snapshot = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [], settings: settings)
    var platform = PlatformState()
    try platform.apply(snapshot, expectedExtensionID: "test.settings")
    #expect(platform.surfaces.isEmpty)
    #expect(platform.presentation == .idle)
    #expect(!platform.isExpanded)
}

@Test func settingsShareTheSnapshotBudgetAndRejectPlaybackNodes() throws {
    let playback = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [],
        settings: .init(id: "wave", type: .waveform))
    #expect(throws: ProtocolError.self) { try playback.validate(expectedExtensionID: "test.settings") }
    let large = Snapshot(extensionID: "test.settings", revision: 1, surfaces: [], settings:
        .init(id: "setup", type: .column, children: (0..<512).map { .init(id: "node-\($0)", type: .text) }))
    #expect(throws: ProtocolError.self) { try large.validate(expectedExtensionID: "test.settings") }
    let shared = UINode(id: "shared", type: .column)
    let duplicate = Snapshot(extensionID: "test.settings", revision: 1,
        surfaces: [.init(id: "activity", kind: .activity, title: "Activity", initialView: .expanded, expanded: shared)], settings: shared)
    #expect(throws: ProtocolError.self) { try duplicate.validate(expectedExtensionID: "test.settings") }
}
