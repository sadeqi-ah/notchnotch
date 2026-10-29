import Foundation
import Testing
import NotchProtocol

@Test func onlyBoundedAlbumArtAndApprovedCDNsAreAccepted() {
    #expect(NowPlayingState.isArtworkSource("https://i.scdn.co/image/cover"))
    #expect(NowPlayingState.isArtworkSource("https://is1-ssl.mzstatic.com/image/cover.jpg"))
    #expect(NowPlayingState.isArtworkSource("data:image/jpeg;base64,YWJj"))
    for source in ["file:///etc/passwd", "http://i.scdn.co/image/cover", "https://i.scdn.co.attacker.example/image",
                   "https://127.0.0.1/", "https://attacker.example/", "data:image/svg+xml;base64,YWJj",
                   "data:image/jpeg;base64," + String(repeating: "a", count: 65_536)] {
        #expect(!NowPlayingState.isArtworkSource(source))
    }
}

@Test func mediaRequestsValidateCommandsAndNormalizedValues() throws {
    try MediaRequest(command: .playPause).validate()
    try MediaRequest(command: .seek, value: 0.5).validate()
    try MediaRequest(command: .volume, value: 0).validate()
    for value in [-0.1, 1.1, Double.infinity, Double.nan] {
        #expect(throws: ProtocolError.self) { try MediaRequest(command: .seek, value: value).validate() }
    }
    #expect(throws: ProtocolError.self) { try MediaRequest(command: .seek).validate() }
    #expect(throws: ProtocolError.self) { try MediaRequest(command: .next, value: 0.5).validate() }
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(MediaRequest.self, from: Data(#"{"command":"runScript","value":0}"#.utf8))
    }
}

@Test func manifestsUseGenericConnectionsAndRejectTheRemovedMediaPermission() throws {
    let json = #"{"id":"dev.example.music","name":"Music","version":"1","apiVersion":1,"entry":"bundle.js","permissions":["process"]}"#
    try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8)).validate()
    for permission in ["media", "filesystem", "shell", "network"] {
        #expect(throws: ProtocolError.self) {
            try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.replacingOccurrences(of: "\"process\"", with: "\"\(permission)\"").utf8)).validate()
        }
    }
}
