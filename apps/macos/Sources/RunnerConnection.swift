import Foundation
import NotchProtocol

@MainActor
final class RunnerConnection {
    let manifest: ExtensionManifest
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private var stopping = false
    private var failed = false
    private let onSnapshot: (Snapshot) -> Void
    private let onFailure: (String) -> Void
    private let onMediaCommand: (MediaRequest) -> Void

    init(manifest: ExtensionManifest, onSnapshot: @escaping (Snapshot) -> Void,
         onMediaCommand: @escaping (MediaRequest) -> Void, onFailure: @escaping (String) -> Void) {
        self.manifest = manifest; self.onSnapshot = onSnapshot; self.onFailure = onFailure
        self.onMediaCommand = onMediaCommand
    }

    func sendMedia(_ state: NowPlayingState?) {
        guard manifest.permissions.contains("media"), process.isRunning, !failed,
              let data = try? JSONEncoder().encode(MediaUpdate(state: state)), data.count <= maximumMessageBytes else { return }
        do { try input.fileHandleForWriting.write(contentsOf: data + Data([10])) }
        catch { fail("Could not update music in \(manifest.name)") }
    }

    func start(executable: URL, bundle: URL) throws {
        try manifest.validate()
        process.executableURL = executable
        process.arguments = [bundle.path, manifest.id]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // Do not pass the developer shell's environment (and potential secrets) into extensions.
        process.environment = ["LANG": "en_US.UTF-8"]
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.read(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                let message = String(decoding: data.prefix(4096), as: UTF8.self)
                Task { @MainActor in self?.fail(message) }
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self, !self.stopping else { return }
                self.fail("\(self.manifest.name) stopped (exit \(status)). Restart demos to try again.")
            }
        }
        do { try process.run() }
        catch { stop(); throw error }
    }

    func send(action: String, value: String?) {
        guard process.isRunning, !failed,
              let data = try? JSONEncoder().encode(UserEvent(action: action, value: value)) else { return }
        do { try input.fileHandleForWriting.write(contentsOf: data + Data([10])) }
        catch { fail("Could not send event to \(manifest.name)") }
    }

    func stop() {
        stopping = true
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func fail(_ message: String) {
        guard !failed, !stopping else { return }
        failed = true
        onFailure(String(message.prefix(4096)))
        stop()
    }

    private func read(_ data: Data) {
        guard !data.isEmpty, !failed, !stopping else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: newline))
            buffer.removeSubrange(...newline)
            guard line.count <= maximumMessageBytes else { fail("Extension message too large"); return }
            do {
                struct Header: Decodable { let type: String; let protocolVersion: Int; let extensionID: String }
                let header = try JSONDecoder().decode(Header.self, from: line)
                guard header.protocolVersion == 1, header.extensionID == manifest.id else {
                    throw ProtocolError.invalid("Extension sent an invalid envelope")
                }
                switch header.type {
                case "snapshot":
                    let snapshot = try JSONDecoder().decode(Snapshot.self, from: line)
                    try snapshot.validate(expectedExtensionID: manifest.id)
                    onSnapshot(snapshot)
                case "error":
                    let notice = try JSONDecoder().decode(RuntimeNotice.self, from: line)
                    fail(notice.message)
                case "log": break
                case "mediaCommand":
                    guard manifest.permissions.contains("media") else {
                        throw ProtocolError.invalid("This extension has no media permission")
                    }
                    let message = try JSONDecoder().decode(MediaCommandMessage.self, from: line)
                    try message.request.validate()
                    onMediaCommand(message.request)
                default: throw ProtocolError.invalid("Unknown extension message")
                }
            } catch { fail(error.localizedDescription); return }
        }
        if buffer.count > maximumMessageBytes { fail("Extension message too large") }
    }
}
