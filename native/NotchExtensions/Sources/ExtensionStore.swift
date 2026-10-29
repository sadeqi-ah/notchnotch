import Foundation
import NotchProtocol

public enum ExtensionOrigin: String, Sendable {
    case bundled = "Included", development = "Development", local = "Installed locally"
}

public struct InstalledExtension: Identifiable, Equatable, Sendable {
    public let manifest: ExtensionManifest
    public let directory: URL
    public let origin: ExtensionOrigin
    public var id: String { manifest.id }
}

public struct ExtensionScan: Sendable {
    public var extensions: [InstalledExtension] = []
    public var issues: [String: String] = [:]
}

public struct ExtensionPackage: Identifiable, Sendable {
    public let manifest: ExtensionManifest
    public let directory: URL
    public let byteCount: Int
    public var id: String { manifest.id }
}

/// Local, explicitly trusted packages. Installing a bundle never runs its build
/// script or native helper; connections still require the usual session consent.
public struct ExtensionStore: Sendable {
    public let directory: URL
    private static let maximumBundleBytes = 64 * 1024 * 1024
    public init(directory: URL) { self.directory = directory.resolvingSymlinksInPath().standardizedFileURL }

    public func scan(included: URL, development: Bool = false) -> ExtensionScan {
        let manager = FileManager.default
        var result = ExtensionScan()
        var ids: Set<String> = []
        for (root, origin) in [(included, development ? ExtensionOrigin.development : .bundled), (directory, .local)] {
            guard manager.fileExists(atPath: root.path) else {
                if origin != .local { result.issues[root.path] = "The included extension folder is unavailable." }
                continue
            }
            do {
                let folders = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for folder in folders {
                    guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    do {
                        let package = try inspect(folder)
                        if origin == .local, folder.lastPathComponent != package.id {
                            throw ProtocolError.invalid("Installed folders must be named after their extension identifier. Import this package through Settings & Extensions.")
                        }
                        guard ids.insert(package.id).inserted else {
                            throw ProtocolError.invalid("Another extension already uses \(package.id). Included extensions cannot be replaced by a local package.")
                        }
                        result.extensions.append(.init(manifest: package.manifest, directory: package.directory, origin: origin))
                    } catch { result.issues[folder.path] = error.localizedDescription }
                }
            } catch { result.issues[root.path] = error.localizedDescription }
        }
        result.extensions.sort { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
        return result
    }

    public func inspect(_ source: URL) throws -> ExtensionPackage {
        let root = source.resolvingSymlinksInPath().standardizedFileURL
        let manager = FileManager.default
        guard (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw ProtocolError.invalid("Choose an extension folder containing notchnotch.json and bundle.js.")
        }
        let manifestURL = root.appendingPathComponent("notchnotch.json")
        let manifestInfo = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard manifestInfo.isRegularFile == true, manifestInfo.isSymbolicLink != true,
              (manifestInfo.fileSize ?? Int.max) <= 65_536 else { throw ProtocolError.invalid("Invalid extension manifest file.") }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
        try manifest.validate()
        let entry = try root.appendingPathComponent(manifest.entry).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard entry.isRegularFile == true, entry.isSymbolicLink != true,
              (1...8_388_608).contains(entry.fileSize ?? 0) else {
            throw ProtocolError.invalid("The extension must include a built bundle.js file smaller than 8 MiB.")
        }
        var bytes = 0
        var count = 0
        var pending = [root]
        while let folder = pending.popLast() {
            for file in try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) {
                count += 1
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard count <= 512, values.isSymbolicLink != true,
                      values.isRegularFile == true || values.isDirectory == true else {
                    throw ProtocolError.invalid("Extension folders may contain up to 512 regular files/folders and no symbolic links.")
                }
                if values.isDirectory == true { pending.append(file) }
                bytes += values.fileSize ?? 0
                guard bytes <= Self.maximumBundleBytes else { throw ProtocolError.invalid("The extension exceeds 64 MiB.") }
            }
        }
        return .init(manifest: manifest, directory: root, byteCount: bytes)
    }

    public func install(_ reviewed: ExtensionPackage, replacing: Bool = false) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appendingPathComponent(".install-" + UUID().uuidString)
        let backup = directory.appendingPathComponent(".previous-" + UUID().uuidString)
        let target = directory.appendingPathComponent(reviewed.id)
        guard !stage.path.hasPrefix(reviewed.directory.path + "/") else {
            throw ProtocolError.invalid("Choose a package outside the installed extension directory.")
        }
        defer { try? manager.removeItem(at: stage) }
        try manager.copyItem(at: reviewed.directory, to: stage)
        let staged = try inspect(stage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(staged.manifest) == encoder.encode(reviewed.manifest) else {
            throw ProtocolError.invalid("The extension changed after review. Choose its folder again.")
        }
        let exists = manager.fileExists(atPath: target.path)
        guard !exists || replacing else { throw ProtocolError.invalid("This extension is already installed.") }
        if exists { try manager.moveItem(at: target, to: backup) }
        do { try manager.moveItem(at: stage, to: target) }
        catch {
            if exists { try? manager.moveItem(at: backup, to: target) }
            throw error
        }
        if exists { try? manager.removeItem(at: backup) }
        return target
    }

    public func isManaged(_ record: InstalledExtension) -> Bool {
        record.origin == .local && record.directory.standardizedFileURL == directory.appendingPathComponent(record.id).standardizedFileURL
    }
}
