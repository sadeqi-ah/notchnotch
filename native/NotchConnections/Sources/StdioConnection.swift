import Foundation
import NotchProtocol

@MainActor
final class StdioConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writer = DispatchQueue(label: "dev.notchnotch.connection-input", qos: .utility)
    private var buffer = Data()
    private var diagnostic = ""
    private var stopped = false

    func start(executable: URL, arguments: [String], directory: URL,
               onMessage: @escaping @MainActor (JSONValue) -> Void,
               onClose: @escaping @MainActor (String?) -> Void) throws {
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        // Native adapters are explicitly trusted user processes. HOME supports
        // their own normal login/config files; shell tokens are never inherited.
        process.environment = ["LANG": "en_US.UTF-8", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                               "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.buffer.append(data)
                do {
                    while let newline = self.buffer.firstIndex(of: 10) {
                        let line = self.buffer.prefix(upTo: newline)
                        guard line.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Helper message exceeds 64 KiB") }
                        let message = line.isEmpty ? nil : try JSONDecoder().decode(JSONValue.self, from: line)
                        self.buffer.removeSubrange(...newline)
                        if let message { onMessage(message) }
                    }
                    guard self.buffer.count <= maximumConnectionPayloadBytes else { throw ProtocolError.invalid("Helper message exceeds 64 KiB") }
                } catch { onClose(error.localizedDescription) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self else { return }
                self.diagnostic = String((self.diagnostic + String(decoding: data, as: UTF8.self)).suffix(2048))
            }
        }
        process.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                onClose(status == 0 ? nil : "Helper exited (\(status)). \(self.diagnostic)")
            }
        }
        do { try process.run() } catch { stop(); throw error }
    }

    func write(_ data: Data) async throws {
        guard !stopped, process.isRunning else { throw ProtocolError.invalid("Helper is not running") }
        let handle = input.fileHandleForWriting
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            writer.async {
                do { try handle.write(contentsOf: data); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close(); try? errors.fileHandleForReading.close()
    }
}
