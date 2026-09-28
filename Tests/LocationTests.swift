import Foundation
@main
struct LocationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("quota-path-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func executable(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        let modern = try executable("Applications/ChatGPT.app/" + CodexLocation.bundledPaths[0])
        let old = try executable("User/Applications/Codex.app/Contents/Resources/codex")
        let cli = try executable("bin/codex")
        let apps = root.appendingPathComponent("Applications").path
        let userApps = root.appendingPathComponent("User/Applications").path
        let modernResolved = try CodexLocation.executable(custom: "", applications: [apps, userApps], cliPaths: [])
        precondition(modernResolved == modern)
        let userResolved = try CodexLocation.executable(custom: "", applications: [userApps], cliPaths: [])
        precondition(userResolved == old)
        let fallback = try CodexLocation.executable(custom: "", applications: [], cliPaths: [cli.path])
        precondition(fallback == cli)
        let manual = try CodexLocation.executable(custom: cli.path, applications: [apps], cliPaths: [])
        precondition(manual == cli)
        let legacy = try CodexLocation.resolve(old.path)
        precondition(legacy == old)
        let bundle = root.appendingPathComponent("Applications/ChatGPT.app").path
        let selected = try CodexLocation.resolve(bundle)
        precondition(selected == modern)
        // Moving the CLI within an app must be discovered from the saved app root.
        try fm.removeItem(at: modern)
        let relocated = try executable("Applications/ChatGPT.app/Contents/Resources/codex")
        let moved = try CodexLocation.resolve(bundle)
        precondition(moved == relocated)
        do {
            _ = try CodexLocation.executable(custom: root.appendingPathComponent("missing").path, applications: [apps], cliPaths: [cli.path])
            fatalError("Invalid manual path must not fall back")
        } catch { precondition(error.localizedDescription.contains("路径无效")) }
        do { _ = try CodexLocation.resolve(root.path); fatalError("Directory must not be executable") } catch {}
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cli.path)
        do { _ = try CodexLocation.resolve(cli.path); fatalError("Non executable must fail") } catch {}
        print("PASS: modern/legacy bundles, user Applications, manual precedence, legacy settings, relocation, invalid paths")
    }
}
