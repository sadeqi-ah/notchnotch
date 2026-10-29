import Foundation
import Testing
import NotchProtocol
@testable import NotchExtensions

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchnotch-packages-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func package(at root: URL, id: String = "dev.test.extension", version: String = "1") throws -> URL {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("""
    {"id":"\(id)","name":"Example","version":"\(version)","apiVersion":1,"entry":"bundle.js","permissions":[]}
    """.utf8).write(to: root.appendingPathComponent("notchnotch.json"))
    try Data("console.log('example');".utf8).write(to: root.appendingPathComponent("bundle.js"))
    return root
}

@Test func installingCopiesTheReviewedPackageWithoutExecutingBuildScripts() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try package(at: root.appendingPathComponent("source"))
    try Data("throw new Error('must never execute');".utf8).write(to: source.appendingPathComponent("build.mjs"))
    let store = ExtensionStore(directory: root.appendingPathComponent("installed"))
    let reviewed = try store.inspect(source)
    let installed = try store.install(reviewed)
    #expect(installed.lastPathComponent == reviewed.id)
    #expect(try Data(contentsOf: installed.appendingPathComponent("bundle.js")) == Data(contentsOf: source.appendingPathComponent("bundle.js")))
    #expect(throws: ProtocolError.self) { try store.install(reviewed) }
}

@Test func changedPermissionsAreRejectedAndAnExistingInstallationSurvives() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try package(at: root.appendingPathComponent("source"))
    let store = ExtensionStore(directory: root.appendingPathComponent("installed"))
    let original = try store.inspect(source)
    let installed = try store.install(original)
    var data = try String(contentsOf: source.appendingPathComponent("notchnotch.json"), encoding: .utf8)
    data = data.replacingOccurrences(of: "\"permissions\":[]", with: "\"permissions\":[\"process\"]")
    try Data(data.utf8).write(to: source.appendingPathComponent("notchnotch.json"))
    #expect(throws: ProtocolError.self) { try store.install(original, replacing: true) }
    #expect(try store.inspect(installed).manifest.permissions.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == [original.id])
}

@Test func aReviewedUpdateReplacesOnlyItsOwnPackage() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try package(at: root.appendingPathComponent("source"))
    let other = try package(at: root.appendingPathComponent("other"), id: "dev.test.other")
    let store = ExtensionStore(directory: root.appendingPathComponent("installed"))
    _ = try store.install(store.inspect(source))
    _ = try store.install(store.inspect(other))
    _ = try package(at: source, version: "2")
    let target = try store.install(store.inspect(source), replacing: true)
    #expect(try store.inspect(target).manifest.version == "2")
    #expect(try store.inspect(store.directory.appendingPathComponent("dev.test.other")).manifest.version == "1")
}

@Test func incompleteBundlesSymlinksAndOversizedResourcesAreRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = try package(at: root.appendingPathComponent("source"))
    let store = ExtensionStore(directory: root.appendingPathComponent("installed"))
    try FileManager.default.removeItem(at: source.appendingPathComponent("bundle.js"))
    #expect(throws: (any Error).self) { try store.inspect(source) }
    _ = try package(at: source)
    let link = source.appendingPathComponent("outside")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    #expect(throws: ProtocolError.self) { try store.inspect(source) }
    try FileManager.default.removeItem(at: link)
    let large = source.appendingPathComponent("large.data")
    #expect(FileManager.default.createFile(atPath: large.path, contents: nil))
    let handle = try FileHandle(forWritingTo: large)
    try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
    try handle.close()
    #expect(throws: ProtocolError.self) { try store.inspect(source) }
}

@Test func localPackagesCannotShadowIncludedExtensionsOrAppearAsStagingInstalls() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let included = root.appendingPathComponent("included")
    _ = try package(at: included.appendingPathComponent("example"))
    let store = ExtensionStore(directory: root.appendingPathComponent("installed"))
    _ = try package(at: store.directory.appendingPathComponent("dev.test.extension"), version: "99")
    _ = try package(at: store.directory.appendingPathComponent(".install-pending"), id: "dev.test.staging")
    let scan = store.scan(included: included)
    #expect(scan.extensions.count == 1)
    #expect(scan.extensions.first?.origin == .bundled)
    #expect(scan.extensions.first?.manifest.version == "1")
    #expect(scan.issues.count == 1)
    #expect(!store.isManaged(scan.extensions[0]))
}
