import Foundation

/// Stores the selected application root so app updates can relocate their bundled CLI.
enum CodexLocation {
    static let bundledPaths = [
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "Contents/Resources/codex",
        "Contents/Resources/codex-cli/bin/codex"
    ]
    static func resolve(_ selection: String) throws -> URL {
        let url = URL(fileURLWithPath: (selection as NSString).expandingTildeInPath)
        if url.pathExtension.lowercased() == "app" {
            for relative in bundledPaths {
                let candidate = url.appendingPathComponent(relative)
                if isExecutable(candidate) { return candidate }
            }
        } else if isExecutable(url) { return url }
        throw CodexClient.failure("路径无效或未找到 Codex 程序：\(selection)。请重新选择，或恢复自动查找。")
    }
    static func isExecutable(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
    static func executable(custom: String,
                           applications: [String] = ["/Applications", NSHomeDirectory() + "/Applications"],
                           cliPaths: [String] = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]) throws -> URL {
        if !custom.isEmpty { return try resolve(custom) }
        for directory in applications {
            for name in ["Codex.app", "ChatGPT.app"] {
                if let url = try? resolve(directory + "/" + name) { return url }
            }
        }
        for path in cliPaths {
            if let url = try? resolve(path) { return url }
        }
        throw CodexClient.failure("找不到 Codex。请在连接设置中选择 ChatGPT / Codex 应用，或选择 codex 可执行文件。")
    }
}
