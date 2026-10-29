import Foundation
import Carbon
import NotchProtocol

/// Playback writes use Spotify's published Apple-event dictionary directly.
/// They have their own serial lane, so a slow metadata read cannot block a click.
actor SpotifyCommands {
    func perform(_ request: MediaRequest, state: NowPlayingState) throws {
        try request.validate()
        let event: NSAppleEventDescriptor
        switch request.command {
        case .playPause: event = transport(state.isPlaying ? "Paus" : "Play")
        case .previous: event = transport("Prev")
        case .next: event = transport("Next")
        case .seek: event = try set("pPos", value: .init(double: (request.value ?? 0) * state.duration))
        case .volume: event = try set("pVol", value: .init(int32: Int32((request.value ?? 0) * 100)))
        case .shuffle: event = try set("pShu", value: .init(boolean: !state.shuffle))
        case .repeatMode: event = try set("pRep", value: .init(boolean: !state.repeating))
        case .openPlayer: return
        }
        let reply = try event.sendEvent(options: .waitForReply, timeout: 2)
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw ProtocolError.invalid(reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue ?? "Spotify could not apply the playback command")
        }
    }

    private func transport(_ command: String) -> NSAppleEventDescriptor {
        .init(eventClass: code("spfy"), eventID: code(command),
              targetDescriptor: .init(bundleIdentifier: MediaPlayer.spotify.rawValue),
              returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    private func set(_ property: String, value: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: OSType(typeProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(.init(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(.init(typeCode: code(property)), forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(.null(), forKeyword: AEKeyword(keyAEContainer))
        guard let specifier = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw ProtocolError.invalid("Could not address Spotify's playback property")
        }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAESetData),
            targetDescriptor: .init(bundleIdentifier: MediaPlayer.spotify.rawValue),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(specifier, forKeyword: AEKeyword(keyDirectObject))
        event.setParam(value, forKeyword: AEKeyword(keyAEData))
        return event
    }

    private func code(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
