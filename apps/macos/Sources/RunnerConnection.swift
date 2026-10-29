import Foundation
import NotchProtocol
import NotchConnections
import AppKit

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
    private let directory: URL
    private var broker: ConnectionBroker?
    private let writer = DispatchQueue(label: "dev.notchnotch.runner-input", qos: .utility)
    private var queuedBytes = 0

    init(manifest: ExtensionManifest, directory: URL, onSnapshot: @escaping (Snapshot) -> Void,
         onFailure: @escaping (String) -> Void) {
        self.manifest = manifest; self.onSnapshot = onSnapshot; self.onFailure = onFailure
        self.directory = directory
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
                self.fail("\(self.manifest.name) stopped (exit \(status)). Restart extensions to try again.")
            }
        }
        do { try process.run() }
        catch { stop(); throw error }
    }

    func send(action: String, value: String?) {
        guard process.isRunning, !failed,
              let data = try? JSONEncoder().encode(UserEvent(action: action, value: value)) else { return }
        enqueue(data + Data([10]), failure: "Could not send event to \(manifest.name)")
    }

    func stop() {
        stopping = true
        resetConnections()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
    }

    func resetConnections() { broker?.stop(); broker = nil }

    private func handleConnection(_ command: ConnectionCommand) {
        if broker == nil {
            broker = ConnectionBroker(manifest: manifest, directory: directory) { [manifest] id, target in
                let definition = manifest.connections?[id]
                let alert = NSAlert()
                alert.messageText = "Allow \(manifest.name) to \(definition?.transport == .stdio ? "run a local tool" : "connect locally")?"
                alert.informativeText = "Connection: \(id)\n\(target)\n\n" + (definition?.transport == .stdio
                    ? "This tool runs with your user account and can access files and network. Allow only extensions and tools you trust."
                    : "The extension can exchange data with this local service. Access ends when the extension is reloaded or connections are disconnected.")
                alert.addButton(withTitle: "Allow for This Session")
                alert.addButton(withTitle: "Don't Allow")
                NSApp.activate(ignoringOtherApps: true)
                return alert.runModal() == .alertFirstButtonReturn
            } emit: { [weak self] json in self?.sendConnectionMessage(json) }
        }
        broker?.receive(command)
    }

    private func sendConnectionMessage(_ json: String) {
        guard process.isRunning, !failed, json.utf8.count <= maximumMessageBytes else { return }
        enqueue(Data((json + "\n").utf8), failure: "Could not deliver connection message to \(manifest.name)")
    }

    private func enqueue(_ data: Data, failure: String) {
        guard !stopping, !failed, queuedBytes + data.count <= 524_288 else {
            if !stopping, !failed { fail("\(manifest.name) is not keeping up with incoming messages") }
            return
        }
        queuedBytes += data.count
        let handle = input.fileHandleForWriting
        writer.async { [weak self] in
            do {
                try handle.write(contentsOf: data)
                Task { @MainActor [weak self] in self?.queuedBytes -= data.count }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.queuedBytes -= data.count
                    if !self.stopping { self.fail(failure) }
                }
            }
        }
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
                case "connectionCommand":
                    let command = try JSONDecoder().decode(ConnectionCommand.self, from: line)
                    try command.validate(expectedExtensionID: manifest.id)
                    handleConnection(command)
                default: throw ProtocolError.invalid("Unknown extension message")
                }
            } catch { fail(error.localizedDescription); return }
        }
        if buffer.count > maximumMessageBytes { fail("Extension message too large") }
    }
}
