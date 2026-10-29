import Foundation
import Carbon
import NotchProtocol

/// A bounded lane of public Apple events for one fixed player. No script engine,
/// application-supplied source code, or implicit player launch is involved.
struct PlayerEvents {
    let player: MediaPlayer
    let deadline: Date

    func get(_ property: String, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let event = event(eventClass: "core", id: "getd")
        event.setParam(try Self.property(property, of: container), forKeyword: AEKeyword(keyDirectObject))
        guard let value = try send(event).paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            throw ProtocolError.invalid("\(player.name) returned no playback value")
        }
        return value
    }

    func set(_ property: String, value: NSAppleEventDescriptor) throws {
        let event = event(eventClass: "core", id: "setd")
        event.setParam(try Self.property(property, of: .null()), forKeyword: AEKeyword(keyDirectObject))
        event.setParam(value, forKeyword: AEKeyword(keyAEData))
        _ = try send(event)
    }

    func command(_ id: String) throws {
        _ = try send(event(eventClass: player == .spotify ? "spfy" : "hook", id: id))
    }

    static func element(_ objectClass: String, index: Int32, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try specifier(objectClass: code(objectClass), form: OSType(formAbsolutePosition), key: .init(int32: index), container: container)
    }

    private static func property(_ property: String, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try specifier(objectClass: OSType(typeProperty), form: OSType(formPropertyID), key: .init(typeCode: code(property)), container: container)
    }

    private static func specifier(objectClass: OSType, form: OSType, key: NSAppleEventDescriptor,
                                  container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: objectClass), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(.init(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        guard let result = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw ProtocolError.invalid("Could not address a playback property")
        }
        return result
    }

    private func event(eventClass: String, id: String) -> NSAppleEventDescriptor {
        .init(eventClass: Self.code(eventClass), eventID: Self.code(id),
              targetDescriptor: .init(bundleIdentifier: player.rawValue),
              returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    private func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw ProtocolError.invalid("\(player.name) did not respond within two seconds") }
        // A background read never creates an Automation dialog, launches a
        // player or switches the foreground app. Connect requests consent first.
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: remaining)
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw ProtocolError.invalid(reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                ?? "\(player.name) could not complete the playback request (\(error.int32Value))")
        }
        return reply
    }

    static func code(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}

/// Writes have their own serial actor, independent of reads and OS permission
/// dialogs, so a delayed metadata sample cannot stall a user command.
actor PlayerCommands {
    func perform(_ request: MediaRequest, state: NowPlayingState) throws {
        try request.validate()
        guard let player = MediaPlayer(rawValue: state.player) else { throw ProtocolError.invalid("Unknown player") }
        let events = PlayerEvents(player: player, deadline: .now.addingTimeInterval(2))
        switch request.command {
        case .playPause: try events.command(state.isPlaying ? "Paus" : "Play")
        case .previous: try events.command("Prev")
        case .next: try events.command("Next")
        case .seek: try events.set("pPos", value: .init(double: (request.value ?? 0) * state.duration))
        case .volume: try events.set("pVol", value: .init(int32: Int32((request.value ?? 0) * 100)))
        case .shuffle: try events.set(player == .spotify ? "pShu" : "pShE", value: .init(boolean: !state.shuffle))
        case .repeatMode:
            try events.set(player == .spotify ? "pRep" : "pRpt", value: player == .spotify
                ? .init(boolean: !state.repeating) : .init(enumCode: PlayerEvents.code(state.repeating ? "kRpO" : "kAll")))
        case .openPlayer: break
        }
    }
}
