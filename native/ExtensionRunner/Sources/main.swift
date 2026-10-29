import Foundation
import NotchRuntime
import NotchProtocol

@MainActor
final class Runner {
    let runtime: JavaScriptRuntime
    private var input = Data()
    init(bundle: URL, extensionID: String) throws {
        runtime = try JavaScriptRuntime(extensionID: extensionID) { json in
            FileHandle.standardOutput.write(Data((json + "\n").utf8))
        }
        try runtime.evaluate(String(contentsOf: bundle, encoding: .utf8), sourceURL: bundle)
    }
    func read(_ data: Data) {
        if data.isEmpty { runtime.stop(); exit(0) }
        input.append(data)
        while let newline = input.firstIndex(of: 10) {
            let line = input.prefix(upTo: newline)
            guard line.count <= maximumMessageBytes else { runtime.stop(); exit(1) }
            input.removeSubrange(...newline)
            if let json = String(data: line, encoding: .utf8) { runtime.receive(json) }
        }
        guard input.count <= maximumMessageBytes else { runtime.stop(); exit(1) }
    }
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: ExtensionRunner <bundle.js> <extension-id>\n".utf8))
    exit(64)
}
do {
    let runner = try Runner(bundle: URL(fileURLWithPath: CommandLine.arguments[1]), extensionID: CommandLine.arguments[2])
    FileHandle.standardInput.readabilityHandler = { handle in
        let data = handle.availableData
        Task { @MainActor in runner.read(data) }
    }
    RunLoop.main.run()
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
